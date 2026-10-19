// The expressions of the text (python prettify.prettify, pretty_bytes,
// pretty_memory, pretty_stor/pretty_loc's raw forms, signatures.
// get_param_name): python's printed forms of the IR's ops, by python's
// precedences - parentheses only where the context binds tighter (ctx: how
// tightly the printed expression must bind, 0 for nothing). The rewrites
// python made of a node before printing it again (a mask as a division, a
// number as n * 3600...) are printed directly: nothing here makes a Value.
#include <algorithm>
#include <format>

#include "algebra/masks.hpp"
#include "analysis/safemath.hpp"
#include "core/budget.hpp"
#include "core/node.hpp"
#include "mem/memory.hpp"
#include "output/print.hpp"

namespace pan::output::detail {

namespace {

// ---- python's values ------------------------------------------------------------------

bool is_small(Value v, i64 x) noexcept { return v.is_small() && v.small_val() == x; }

// python's is_bool: 0 or 1 for every value of the leaves
bool is_bool(Value e) noexcept
{
    if (e.is_int())
        return is_small(e, 0) || is_small(e, 1);
    if (e.is_bool())
        return true;
    switch (e.op()) {
        case Op::BOOL:
        case Op::ISZERO:
        case Op::LT:
        case Op::GT:
        case Op::LE:
        case Op::GE:
        case Op::EQ:
        case Op::SLT:
        case Op::SGT:
        case Op::SLE:
        case Op::SGE:
        case Op::CALL_SUCCESS:
            return true;
        case Op::AND:
        case Op::OR:
        case Op::XOR:
        case Op::LOR:
        case Op::FAND:
        case Op::FOR:
            if (!e.is_expr())
                return false;
            for (const Value a : e.args())
                if (!is_bool(a))
                    return false;
            return true;
        case Op::LAND:
            return e.is_expr() && e.size() && is_bool(e[e.size() - 1]);
        case Op::MASK_SHL:
            // a single bit, moved down to the lowest one
            return e.size() == 4 && is_small(e[0], 1) && e[1].is_small() && e[2].is_small() &&
                   e[1].small_val() + e[2].small_val() == 0;
        case Op::STORAGE:
            return e.size() == 3 && is_small(e[0], 1) && e[1].is_small() && e[1].small_val() >= 0;
        default:
            return false;
    }
}

// python's mask_to_type(size) (without force): the names of the usual widths
std::optional<std::string_view> mask_to_type(i64 size) noexcept
{
    switch (size) {
        case 1: return "bool";
        case 8: return "uint8";
        case 16: return "uint16";
        case 32: return "uint32";
        case 64: return "uint64";
        case 128: return "uint128";
        case 160: return "address";
        case 256: return "uint256";
        default: return std::nullopt;
    }
}

// a python atom (a str of the IR, an int): what the eq printing puts on the right
bool atom_or_int(Value v) noexcept { return v.is_int() || v.is_leaf(); }

// python's to_real_int: a number whose bit 255 is set as the negative of
// its word (pretty_adds' constant)
EvmInt to_real_int(const EvmInt& x)
{
    if (x.test_bit(255))
        return x.word() - two_256();
    return x;
}

// python's fits_bytes(val, size)
bool fits_bytes(const EvmInt& v, i64 size)
{
    return size >= 0 && size <= (i64(1) << 24) && v.sign() >= 0 && v.bit_length() <= u64(8) * u64(size);
}

// the significant bytes of a non-negative int, big-endian (none for 0):
// as many as the int is long, never more
std::vector<u8> int_sig_bytes(const EvmInt& v)
{
    const usize n = usize((v.bit_length() + 7) / 8);
    std::vector<u8> b(n, 0);
    if (v.fits_i64()) {
        u64 m = u64(v.to_i64());
        for (usize i = 0; i < n; ++i, m >>= 8)
            b[n - 1 - i] = u8(m & 0xff);
        return b;
    }
    usize count = 0;
    mpz_export(b.data(), &count, 1, 1, 1, 0, v.big()->get_mpz_t());
    return b;
}

// the bytes past which pretty_memory no longer looks for text in the
// elements of a data (the asm's PM_BYTES_MAX, 16 MiB: what fits_bytes
// allows one element) - the elements are then printed one by one
constexpr u64 kTextBytesMax = u64(1) << 24;

// python's data_bytes(e), the bytes of an element of a data if they're
// known (Bytes(n, int), an int word, the contract's bytes), as `zeros`
// zeroes then `rest` (an int's significant bytes, the contract's bytes):
// no zero is text, so its zeroes are counted, never written out - a
// Bytes(2^24, 0) is 16 MiB of them
struct ElemBytes {
    u64 zeros = 0;
    std::vector<u8> rest;
    u64 size() const noexcept { return zeros + rest.size(); }
};

std::optional<ElemBytes> elem_bytes(Value e)
{
    const auto of_int = [](const EvmInt& v, u64 n) {
        ElemBytes b;
        b.rest = int_sig_bytes(v);
        b.zeros = n - b.rest.size();
        return b;
    };
    const auto of_bytes = [](Value b) {
        const auto s = b.bytes();
        ElemBytes r;
        r.rest.assign(s.begin(), s.end());
        return r;
    };
    if (e.is(Op::SIZED, 2) && e[0].is_small()) {
        const i64 n = e[0].small_val();
        if (e[1].is_int()) {
            const EvmInt v(e[1]);
            if (fits_bytes(v, n))
                return of_int(v, u64(n));
            return std::nullopt;
        }
        if (e[1].is_bytes() && i64(e[1].size()) == n)
            return of_bytes(e[1]);
        return std::nullopt;
    }
    if (e.is_int()) {
        const EvmInt v(e);
        if (v.sign() >= 0 && v.bit_length() <= 256)
            return of_int(v, 32);
        return std::nullopt;
    }
    if (e.is_bytes())
        return of_bytes(e);
    return std::nullopt;
}

// the bytes of elements of a data, one after the other as python
// concatenates them (b += data_bytes(el)), in their parts
struct DataBytes {
    struct Part {
        u64 at;  // where its zeroes start; its rest is at + zeros
        u64 zeros;
        std::vector<u8> rest;
    };
    std::vector<Part> parts;
    u64 size = 0;

    void add(ElemBytes&& b)
    {
        const u64 n = b.size();
        parts.push_back(Part{size, b.zeros, std::move(b.rest)});
        size += n;
    }

    // not any(b[from:])
    bool zero_from(u64 from) const
    {
        for (const Part& p : parts) {
            const u64 r = p.at + p.zeros;
            if (r + p.rest.size() <= from)
                continue;
            for (u64 i = from > r ? from - r : 0; i < p.rest.size(); ++i)
                if (p.rest[i])
                    return false;
        }
        return true;
    }

    // python's pretty_text(b[:end], short): b[:end] is made only when none
    // of the parts' zeroes is in it (a zero is no text)
    std::optional<std::string> text(u64 end, bool short_ok = false) const
    {
        std::vector<u8> b;
        for (const Part& p : parts) {
            if (p.at >= end)
                break;
            if (p.zeros)
                return std::nullopt;
            const u64 k = std::min<u64>(p.rest.size(), end - p.at);
            b.insert(b.end(), p.rest.begin(), p.rest.begin() + i64(k));
        }
        return pretty_text(b, short_ok);
    }
};

// python's word(e) of pretty_memory: the int a word of the data is
std::optional<EvmInt> word_int(Value e)
{
    if (e.is_int())
        return EvmInt(e);
    if (e.is(Op::SIZED, 2) && is_small(e[0], 32) && e[1].is_int())
        return EvmInt(e[1]);
    return std::nullopt;
}

// SIZED(4, int): a selector's (python ("bytes", 4, :int:))
std::optional<EvmInt> selector_int(Value e)
{
    if (e.is(Op::SIZED, 2) && is_small(e[0], 4) && e[1].is_int())
        return EvmInt(e[1]);
    return std::nullopt;
}

bool sized4(Value e) noexcept { return e.is(Op::SIZED, 2) && is_small(e[0], 4); }

// a DATA's elements, flattened (fix_widths: a data of data is its elements)
void flat_elements(Value d, std::vector<Value>& out)
{
    for (const Value e : d.args()) {
        if (e.is(Op::DATA))
            flat_elements(e, out);
        else
            out.push_back(e);
    }
}

// a byte element's length operand (structurally; NIL when not said)
Value elem_len(Value e) noexcept
{
    switch (e.op()) {
        case Op::SIZED: return e.size() == 2 ? e[0] : Value();
        case Op::MEM: return e.size() == 1 && e[0].is(Op::RANGE, 2) ? e[0][1] : Value();
        case Op::CALLDATA_BYTES:
        case Op::CODE_BYTES: return e.size() == 2 ? e[1] : Value();
        case Op::RETURNDATA_BYTES: return e.size() == 3 ? e[2] : Value();
        case Op::EXTCODE_BYTES: return e.size() == 2 && e[1].is(Op::RANGE, 2) ? e[1][1] : Value();
        default: return e.is_bytes() ? Value::small(i64(e.size())) : Value();
    }
}

// The zeroes an ABI array's data is padded with, last of its terms: the
// text's Array pads its data to a word itself - dropped when the data
// before them is len bytes (one element of that length, or a known length
// short of a word)
bool padding_at_end(std::span<const Value> terms, Value len) noexcept
{
    if (terms.size() < 2)
        return false;
    const Value el = terms.back();
    if (!el.is(Op::SIZED, 2) || !is_small(el[1], 0))
        return false;
    const Value n = el[0];
    if (terms.size() == 2 && elem_len(terms[0]) == len)
        return !n.is_small() || (n.small_val() >= 0 && n.small_val() < 32);
    if (n.is_small() && len.is_small()) {
        i64 before = 0;
        for (const Value t : terms.first(terms.size() - 1)) {
            const Value w = elem_len(t);
            if (!w.is_small())
                return false;
            before += w.small_val();
        }
        return before == len.small_val() && n.small_val() >= 0 && n.small_val() < 32 && (before + n.small_val()) % 32 == 0;
    }
    return false;
}

}  // namespace

EvmInt display_int(const EvmInt& x)
{
    // python's simplify_exp: an int whose to_real_int is past -(8**22) is it
    if (x.sign() > 0 && x.bit_length() == 256) {
        static const EvmInt limit = -EvmInt::pow2(66);
        EvmInt r = x - two_256();
        if (r > limit)
            return r;
    }
    return x;
}

std::optional<std::string> error_message_text(Value data)
{
    // python safemath.failure: data[0] the selector of Error(string), data[1]
    // 32, data[2] the length (> 0), then the words of the bytes - what
    // follows them in the last word isn't part of the string
    if (!data.is(Op::DATA))
        return std::nullopt;
    std::vector<Value> els;
    flat_elements(data, els);
    if (els.size() < 3)
        return std::nullopt;
    const auto sel = selector_int(els[0]);
    const auto w1 = word_int(els[1]);
    const auto w2 = word_int(els[2]);
    if (!sel || *sel != EvmInt(i64(0x08c379a0)) || !w1 || *w1 != EvmInt(i64(32)) || !w2)
        return std::nullopt;
    const EvmInt& len = *w2;
    if (len.sign() <= 0 || len.bit_length() > 40)
        return std::nullopt;
    const u64 length = len.to_u64().value_or(0);
    DataBytes b;
    for (usize i = 3; i < els.size() && b.size < length; ++i) {
        if (b.size >= kTextBytesMax)
            return std::nullopt;
        auto c = elem_bytes(els[i]);
        if (!c)
            return std::nullopt;
        b.add(std::move(*c));
    }
    if (b.size < length)
        return std::nullopt;
    return b.text(length);
}

// ---- the printer -----------------------------------------------------------------------

struct ExpImpl {
    Printer& p;
    Out& o;
    const FnEnv& env;

    explicit ExpImpl(Printer& pr) : p(pr), o(pr.o_), env(pr.env_) {}

    // python's wrap(text, prec): parentheses when the form binds less tightly than ctx
    struct Wrap {
        Out& o;
        bool on;
        Wrap(Out& out, int prec, int ctx) : o(out), on(prec < ctx) {
            if (on) o.put('(');
        }
        ~Wrap() {
            if (on) o.put(')');
        }
    };

    void op_form(std::string_view f) { o.col(Col::bold, f); }
    void pret(Value e) { exp(e, P_NONE, false); }

    // ---- ints ----
    // an int as python's trace has it (display_int: the top of the words as
    // negatives), printed
    void print_int(const EvmInt& x, int ctx) { print_word(display_int(x), ctx); }

    // python's prettify of an int as it is
    void print_word(const EvmInt& x, int ctx)
    {
        static const EvmInt day(i64(24 * 3600)), hour(i64(3600));
        if (x > day && pymod(x, day).is_zero()) {
            // python: ("mul", x // 86400, 24, 3600)
            Wrap w(o, P_MUL, ctx);
            print_int(floordiv(x, day), P_MUL);
            op_form(" * ");
            print_int(EvmInt(i64(24)), P_MUL + 1);
            op_form(" * ");
            print_int(hour, P_MUL + 1);
            return;
        }
        if (x > hour && pymod(x, hour).is_zero()) {
            // python: ("mul", x // 3600, 3600) - a power of 2 past 2**32 times it a shift
            const EvmInt q = floordiv(x, hour);
            if (q.sign() > 0 && q == EvmInt::pow2(q.bit_length() - 1) && q.bit_length() - 1 > 32) {
                Wrap w(o, P_SHIFT, ctx);
                print_int(hour, P_SHIFT);
                op_form(" << ");
                print_int(EvmInt(i64(q.bit_length() - 1)), P_SHIFT + 1);
                return;
            }
            Wrap w(o, P_MUL, ctx);
            print_int(q, P_MUL);
            op_form(" * ");
            print_int(hour, P_MUL + 1);
            return;
        }
        const std::string t = pretty_num(x);
        Wrap w(o, num_precedence(t), ctx);
        o.put(t);
    }

    // ---- names, leaves ----
    void name(Value n)
    {
        if (const Printer::Subst* sub = p.subst())
            for (const auto& [from, text] : *sub)
                if (from == n) {
                    o.col(Col::blue, text);
                    return;
                }
        o.col(env.name_color(n), env.name_text(n));
    }

    void leaf(Value l)
    {
        switch (l.op()) {
            case Op::ADDRESS: o.put("this.address"); return;
            case Op::ORIGIN: o.put("tx.origin"); return;
            case Op::CALLER: o.put("caller"); return;
            case Op::CALLVALUE: o.put("call.value"); return;
            case Op::CALLDATASIZE: o.put("calldata.size"); return;
            case Op::CODESIZE: o.put("code.size"); return;
            case Op::GASPRICE: o.put("tx.gasprice"); return;
            case Op::RETURNDATASIZE: o.put("return_data.size"); return;
            case Op::COINBASE: o.put("block.coinbase"); return;
            case Op::TIMESTAMP: o.put("block.timestamp"); return;
            case Op::NUMBER: o.put("block.number"); return;
            case Op::DIFFICULTY: o.put("block.difficulty"); return;
            case Op::GASLIMIT: o.put("block.gas_limit"); return;
            case Op::CHAINID: o.put("chainid"); return;
            case Op::SELFBALANCE: o.put("eth.balance(this.address)"); return;
            case Op::BASEFEE: o.put("block.basefee"); return;
            case Op::BLOBBASEFEE: o.put("block.blobbasefee"); return;
            case Op::MSIZE: o.put("msize"); return;
            case Op::GAS: o.put("gas_remaining"); return;
            case Op::CALL_SUCCESS: {
                const u32 id = l.leaf_n();
                switch (env.call_kind(id)) {
                    case Op::DELEGATECALL: o.put("delegate.return_code"); return;
                    case Op::CALLCODE: o.put("callcode.return_code"); return;
                    case Op::PRECOMPILED: {
                        const u32 a = env.precompile_address(id);
                        if (a == 4) {
                            o.put("memcopy.success");
                            return;
                        }
                        o.put(precompile_name(a));
                        o.put(".result");
                        return;
                    }
                    default: o.put("ext_call.success"); return;
                }
            }
            case Op::CREATE_ADDRESS:
                o.put(env.call_kind(l.leaf_n()) == Op::CREATE2 ? "create2.new_address" : "create.new_address");
                return;
            default:
                o.put(op_name(l.op()));
                return;
        }
    }

    static std::string_view precompile_name(u32 a) noexcept
    {
        switch (a) {
            case 1: return "ecrecover";
            case 2: return "sha256hash";
            case 3: return "ripemd160hash";
            case 4: return "identity";
            case 5: return "bigModExp";
            case 6: return "bn256Add";
            case 7: return "bn256ScalarMul";
            case 8: return "bn256Pairing";
            default: return "precompiled";
        }
    }

    // ---- the main dispatch: python prettify ----
    void exp(Value e, int ctx, bool rem_bool)
    {
        check_stack();
        if (rem_bool) {
            // python: simplify_bool, then a xor's truth (they differ), a bool again
            const SB s = simplify_bool(e);
            if (s.neg) {
                is_zero(s.v, ctx, true);
                return;
            }
            e = s.v;
            if (e.is(Op::XOR, 2)) {
                iszero_eq(e[0], e[1], ctx);
                return;
            }
            if (e.is(Op::BOOL)) {
                exp(e, ctx, true);
                return;
            }
        }
        if (e.is_int()) {
            print_int(EvmInt(e), ctx);
            return;
        }
        if (e.is_bool()) {
            o.put(e.is_true() ? "True" : "False");
            return;
        }
        if (e.is_none()) {
            o.put("None");
            return;
        }
        if (e.nil()) {
            o.put("NIL");
            return;
        }
        if (e.is_bytes()) {
            bytes_node(e, ctx);
            return;
        }
        if (e.is_name()) {
            name(e);
            return;
        }
        if (e.is_leaf()) {
            leaf(e);
            return;
        }
        if (e.is_list()) {
            o.put('[');
            bool first = true;
            for (const Value a : e.args()) {
                if (!first)
                    o.put(", ");
                first = false;
                pret(a);
            }
            o.put(']');
            return;
        }
        if (!e.is_expr()) {
            o.put("?");
            return;
        }
        expr(e, ctx, rem_bool);
    }

    // python's simplify_bool, as a view: v, or (neg) is_zero(v)
    struct SB {
        Value v;
        bool neg;
    };
    SB simplify_bool(Value e)
    {
        check_stack();
        if (e.is(Op::ISZERO, 1)) {
            const SB in = simplify_bool(e[0]);
            if (!in.neg && in.v.is(Op::ISZERO, 1))
                return {in.v[0], false};
            return {in.v, !in.neg};
        }
        if (e.is(Op::BOOL, 1))
            return {e[0], false};
        return {e, false};
    }

    // python: prettify(is_zero(y), rem_bool, parentheses=ctx)
    void is_zero(Value y, int ctx, bool rem_bool)
    {
        check_stack();
        if (y.is_int()) {
            o.put(EvmInt(y).word().is_zero() ? "True" : "False");
            return;
        }
        if (y.is_bool()) {
            o.put(y.is_true() ? "False" : "True");
            return;
        }
        switch (y.op()) {
            case Op::ISZERO:
                if (y.size() == 1) {
                    const Value z = y[0];
                    if (z.is(Op::EQ)) {
                        exp(z, ctx, rem_bool);
                        return;
                    }
                    if (z.is(Op::ISZERO, 1)) {
                        is_zero(z[0], ctx, rem_bool);
                        return;
                    }
                    // ("bool", z)
                    if (rem_bool)
                        exp(z, ctx, true);
                    else
                        bool_case(z, ctx);
                    return;
                }
                break;
            case Op::BOOL:
                if (y.size() == 1) {
                    is_zero(y[0], ctx, rem_bool);
                    return;
                }
                break;
            case Op::OR: {
                // all of them are 0: python's and_op of their is_zero
                std::vector<Value> parts;
                bool is_false = false;
                or_zero_parts(y, parts, is_false);
                if (is_false) {
                    o.put("False");
                    return;
                }
                if (parts.empty()) {
                    o.put("True");
                    return;
                }
                if (parts.size() == 1) {
                    is_zero(parts[0], ctx, rem_bool);
                    return;
                }
                Wrap w(o, P_AND, ctx);
                for (usize i = 0; i < parts.size(); ++i) {
                    if (i)
                        op_form(" and ");
                    is_zero(parts[i], P_AND + 1, rem_bool || i + 1 < parts.size());
                }
                return;
            }
            case Op::AND: {
                if (!is_bool(y))
                    break;
                // one of them is false: python's or_op of their is_zero
                std::vector<Value> parts;
                for (const Value r : y.args()) {
                    if (r.is_int()) {
                        if (EvmInt(r).word().is_zero()) {
                            o.put("True");
                            return;
                        }
                        continue;
                    }
                    parts.push_back(r);
                }
                if (parts.empty()) {
                    o.put("False");
                    return;
                }
                if (parts.size() == 1) {
                    is_zero(parts[0], ctx, rem_bool);
                    return;
                }
                Wrap w(o, P_OR, ctx);
                for (usize i = 0; i < parts.size(); ++i) {
                    if (i)
                        op_form(" or ");
                    is_zero(parts[i], P_OR + 1, rem_bool);
                }
                return;
            }
            case Op::LE: if (y.size() == 2) { arith(Op::GT, y, ctx, rem_bool); return; } break;
            case Op::LT: if (y.size() == 2) { arith(Op::GE, y, ctx, rem_bool); return; } break;
            case Op::GE: if (y.size() == 2) { arith(Op::LT, y, ctx, rem_bool); return; } break;
            case Op::GT: if (y.size() == 2) { arith(Op::LE, y, ctx, rem_bool); return; } break;
            case Op::SLE: if (y.size() == 2) { arith(Op::SGT, y, ctx, rem_bool); return; } break;
            case Op::SLT: if (y.size() == 2) { arith(Op::SGE, y, ctx, rem_bool); return; } break;
            case Op::SGE: if (y.size() == 2) { arith(Op::SLT, y, ctx, rem_bool); return; } break;
            case Op::SGT: if (y.size() == 2) { arith(Op::SLE, y, ctx, rem_bool); return; } break;
            default:
                break;
        }
        iszero_case(y, ctx);
    }

    // python is_zero(or): its operands' is_zero, an or's flattened (and_op);
    // a nonzero int decides it (False), a zero one adds nothing
    void or_zero_parts(Value y, std::vector<Value>& parts, bool& is_false)
    {
        for (const Value r : y.args()) {
            if (r.is_int()) {
                if (!EvmInt(r).word().is_zero())
                    is_false = true;
                continue;
            }
            if (r.is(Op::OR)) {
                or_zero_parts(r, parts, is_false);
                continue;
            }
            parts.push_back(r);
        }
    }

    // python's ("iszero", val) case
    void iszero_case(Value val, int ctx)
    {
        // (an unsigned comparison's numbers: their words, see arith)
        auto operand = [&](Value x, bool ordering) {
            if (ordering && x.is_int())
                print_word(EvmInt(x), P_CMP + 1);
            else
                exp(x, P_CMP + 1, false);
        };
        auto comparison = [&](Value l, std::string_view op, Value r, bool ordering) {
            Wrap w(o, P_CMP, ctx);
            operand(l, ordering);
            o.put(op);
            operand(r, ordering);
        };
        if (val.is(Op::GT, 2))
            return comparison(val[0], " <= ", val[1], true);
        if (val.is(Op::LT, 2))
            return comparison(val[0], " >= ", val[1], true);
        if (val.is(Op::EQ, 2)) {
            if (atom_or_int(val[0]))
                return comparison(val[1], " != ", val[0], false);
            return comparison(val[0], " != ", val[1], false);
        }
        // (of its operand, only the truth counts: not bool(x) is not x)
        Wrap w(o, P_NOT, ctx);
        o.put("not ");
        exp(val, P_NOT, true);
    }

    // python: ("iszero", ("eq", a, b)) printed
    void iszero_eq(Value a, Value b, int ctx)
    {
        Wrap w(o, P_CMP, ctx);
        if (atom_or_int(a)) {
            exp(b, P_CMP + 1, false);
            o.put(" != ");
            exp(a, P_CMP + 1, false);
        } else {
            exp(a, P_CMP + 1, false);
            o.put(" != ");
            exp(b, P_CMP + 1, false);
        }
    }

    // python's ("bool", val) case
    void bool_case(Value val, int ctx)
    {
        switch (val.op()) {
            case Op::LT:
            case Op::GT:
            case Op::ISZERO:
            case Op::LE:
            case Op::GE:
            case Op::BOOL:
                if (val.is_expr()) {
                    exp(val, ctx, false);
                    return;
                }
                break;
            default:
                break;
        }
        o.put("bool(");
        pret(val);
        o.put(')');
    }

    // ---- python's opcode_to_arithm --------------------------------------------------------
    static std::string_view arith_form(Op op) noexcept
    {
        switch (op) {
            case Op::SUB: return " - ";
            case Op::DIV: return " / ";
            case Op::MUL: return " * ";
            case Op::GT: return " > ";
            case Op::LT: return " < ";
            case Op::LE: return " <= ";
            case Op::GE: return " >= ";
            case Op::OR: return " | ";
            case Op::EQ: return " == ";
            case Op::MOD: return " % ";
            case Op::SHL: return " << ";
            case Op::SHR: return " >> ";
            case Op::EXP: return "**";
            case Op::AND: return " & ";
            case Op::SGE: return " >=′ ";
            case Op::SLE: return " <=′ ";
            case Op::SGT: return " >′ ";
            case Op::SLT: return " <′ ";
            case Op::SDIV: return " /′ ";
            case Op::SMOD: return " %′ ";
            case Op::XOR: return " ^ ";
            default: return {};
        }
    }
    static int arith_prec(Op op) noexcept
    {
        switch (op) {
            case Op::OR: return P_BOR;
            case Op::XOR: return P_BXOR;
            case Op::AND: return P_BAND;
            case Op::EQ:
            case Op::LT:
            case Op::GT:
            case Op::LE:
            case Op::GE:
            case Op::SLT:
            case Op::SGT:
            case Op::SLE:
            case Op::SGE: return P_CMP;
            case Op::SHL:
            case Op::SHR: return P_SHIFT;
            case Op::SUB: return P_ADD;
            case Op::MUL:
            case Op::DIV:
            case Op::MOD:
            case Op::SDIV:
            case Op::SMOD: return P_MUL;
            case Op::EXP: return P_POW;
            default: return P_ATOM;
        }
    }

    // python's fold_ands: the operands of an and, nested ands flattened
    void and_parts(Value e, std::vector<Value>& out)
    {
        for (const Value a : e.args()) {
            if (a.is(Op::AND))
                and_parts(a, out);
            else
                out.push_back(a);
        }
    }

    // e's operands printed with op's form (op may differ from e's: a flipped comparison)
    void arith(Op op, Value e, int ctx, bool rem_bool)
    {
        std::span<const Value> args = e.args();
        Value swapped[2];
        if ((op == Op::SHL || op == Op::SHR) && args.size() == 2) {
            swapped[0] = args[1];
            swapped[1] = args[0];
            args = std::span<const Value>(swapped, 2);
        }
        const std::string_view form = arith_form(op);
        int prec = arith_prec(op);
        if ((op == Op::AND || op == Op::OR) && ((rem_bool && op == Op::OR) || std::all_of(args.begin(), args.end(), is_bool))) {
            // python's and / or: of truth values, the bitwise ones; where its
            // value counts, the operand that decides (the last of an and, any
            // of an or) as the 0 or 1 it is
            std::vector<Value> parts;
            if (op == Op::AND)
                and_parts(e, parts);
            else
                parts.assign(args.begin(), args.end());
            prec = op == Op::AND ? P_AND : P_OR;
            Wrap w(o, prec, ctx);
            for (usize i = 0; i < parts.size(); ++i) {
                if (i)
                    op_form(op == Op::AND ? " and " : " or ");
                exp(parts[i], prec + 1, rem_bool || (op == Op::AND && i + 1 < parts.size()));
            }
            return;
        }
        // the operands after the first bind tighter: a / (b / c) isn't a / b / c
        const int rest_prec = prec + 1;
        const int first_prec = prec == P_CMP ? P_CMP + 1 : prec;  // (comparisons don't chain)
        // (the numbers an unsigned comparison is made with are the words
        // python's trace has: `x < 0xff..ff`, never `x < -1`)
        const bool ordering = op == Op::LT || op == Op::GT || op == Op::LE || op == Op::GE;
        Wrap w(o, prec, ctx);
        for (usize i = 0; i < args.size(); ++i) {
            if (i)
                op_form(form);
            if (ordering && args[i].is_int())
                print_word(EvmInt(args[i]), i ? rest_prec : first_prec);
            else
                exp(args[i], i ? rest_prec : first_prec, false);
        }
    }

    // ---- sums: python's pretty_adds ----
    void adds(Value e, int ctx)
    {
        std::span<const Value> terms = e.args();
        std::optional<EvmInt> real;
        if (!terms.empty() && terms[0].is_int()) {
            real = to_real_int(EvmInt(terms[0]));
            terms = terms.subspan(1);
        }
        Wrap w(o, P_ADD, ctx);
        bool first = true;
        for (const Value x : terms) {
            if (first) {
                exp(x, P_ADD, false);
                first = false;
                continue;
            }
            if (x.is(Op::MUL) && x.size() >= 2 && x[0].is_int() && display_int(EvmInt(x[0])).sign() < 0) {
                o.put(" - ");
                mul_minus(x, P_ADD + 1);
                continue;
            }
            o.put(" + ");
            exp(x, P_ADD, false);
        }
        if (real) {
            static const EvmInt big = EvmInt::pow2(128);
            if (real->sign() > 0 || *real <= -big) {
                // a big one - a hash, say - is added, however large it is
                o.put(" + ");
                print_word(real->word(), P_ADD);
            } else if (real->sign() < 0) {
                o.put(" - ");
                print_word(-*real, P_ADD + 1);
            }
        }
    }

    // python: operand(minus_op(x), ctx) for x = MUL(-k, f...): k times them
    void mul_minus(Value x, int ctx)
    {
        const EvmInt k = -display_int(EvmInt(x[0]));
        std::span<const Value> fs = x.args().subspan(1);
        if (k == 1) {
            if (fs.size() == 1) {
                exp(fs[0], ctx, false);
                return;
            }
            mul_parts(std::nullopt, fs, ctx);
            return;
        }
        mul_parts(k, fs, ctx);
    }

    // python's ("mul", k, f...) printed (k absent: the factors alone)
    void mul_parts(std::optional<EvmInt> k, std::span<const Value> fs, int ctx)
    {
        // a power of 2 past 2**32 times one factor: a shift
        if (k && fs.size() == 1 && k->sign() > 0) {
            const u64 b = k->bit_length() - 1;
            if (b > 32 && *k == EvmInt::pow2(b)) {
                Wrap w(o, P_SHIFT, ctx);
                exp(fs[0], P_SHIFT, false);
                op_form(" << ");
                print_int(EvmInt(i64(b)), P_SHIFT + 1);
                return;
            }
        }
        if (k && *k == -1 && fs.size() == 1) {
            Wrap w(o, P_UNARY, ctx);
            o.put('-');
            exp(fs[0], P_UNARY, false);
            return;
        }
        if (k && *k == 1) {
            if (fs.size() == 1) {
                exp(fs[0], ctx, false);
                return;
            }
            k.reset();
        }
        Wrap w(o, P_MUL, ctx);
        bool first = true;
        if (k) {
            print_int(*k, P_MUL);
            first = false;
        }
        for (const Value f : fs) {
            if (!first)
                op_form(" * ");
            exp(f, first ? P_MUL : P_MUL + 1, false);
            first = false;
        }
    }

    void mul(Value e, int ctx)
    {
        if (e.size() >= 1 && e[0].is_int())
            mul_parts(display_int(EvmInt(e[0])), e.args().subspan(1), ctx);
        else
            mul_parts(std::nullopt, e.args(), ctx);
    }

    // ---- bytes ----
    // python's pretty_bytes(size, val)
    void pretty_bytes(Value size, Value val, int ctx)
    {
        if (is_small(size, 32)) {
            exp(val, ctx, false);
            return;
        }
        if (size.is_small() && val.is_int()) {
            // (python's trace has the top of the words as negatives: no bytes)
            const EvmInt v = display_int(EvmInt(val));
            const i64 n = size.small_val();
            if (fits_bytes(v, n)) {
                // text, as a string literal (short: a separator) - which
                // the n bytes aren't when a zero comes before v's own
                const auto b = int_sig_bytes(v);
                if (i64(b.size()) == n)
                    if (auto t = pretty_text(b, true)) {
                        o.put(*t);
                        return;
                    }
                o.col(Col::gray, "Bytes(");
                o.put(std::to_string(n));
                o.col(Col::gray, ", ");
                if (v.is_zero()) {
                    o.put('0');
                } else {
                    std::string h = int_hex(v).substr(2);
                    o.put("0x");
                    if (h.size() < usize(2 * n))
                        o.put(std::string(usize(2 * n) - h.size(), '0'));
                    o.put(h);
                }
                o.col(Col::gray, ")");
                return;
            }
        }
        if (size.is_small() && val.is_bytes() && i64(val.size()) == size.small_val()) {
            bytes_node(val, ctx);
            return;
        }
        o.col(Col::gray, "Bytes(");
        pret(size);
        o.col(Col::gray, ", ");
        pret(val);
        o.col(Col::gray, ")");
    }

    // the contract's bytes (a BYTES node): python's long int of them as n bytes
    void bytes_node(Value b, int)
    {
        const auto s = b.bytes();
        if (auto t = pretty_text(s, true)) {
            o.put(*t);
            return;
        }
        o.col(Col::gray, "Bytes(");
        o.put(std::to_string(s.size()));
        o.col(Col::gray, ", ");
        bool zero = std::all_of(s.begin(), s.end(), [](u8 c) { return c == 0; });
        if (zero) {
            o.put('0');
        } else {
            static constexpr char hx[] = "0123456789abcdef";
            std::string h;
            h.reserve(2 + 2 * s.size());
            h += "0x";
            for (const u8 c : s) {
                h += hx[c >> 4];
                h += hx[c & 15];
            }
            o.put(h);
        }
        o.col(Col::gray, ")");
    }

    // python's with_width + prettify: an element of a data
    void element(Value el)
    {
        if (el.is(Op::SIZED, 2)) {
            pretty_bytes(el[0], el[1], P_NONE);
            return;
        }
        if (mem::is_bytes(el) || el.is_int()) {
            pret(el);
            return;
        }
        // a word without its width (a stage's slip): python's sizeof
        const auto w = mem::implicit_width(el);
        if (w && *w != 32) {
            o.col(Col::gray, "Bytes(");
            o.put(std::to_string(*w));
            o.col(Col::gray, ", ");
            pret(el);
            o.col(Col::gray, ")");
            return;
        }
        pret(el);
    }

    // python's arr_text: an ARR of text as a string literal
    std::optional<std::string> arr_text(Value e)
    {
        if (!e.is(Op::ARR) || e.size() < 2 || !e[0].is_small())
            return std::nullopt;
        const i64 l = e[0].small_val();
        DataBytes b;
        for (const Value t : e.args().subspan(1)) {
            // (past 16 MiB of bytes no text, as pretty_memory's)
            if (b.size >= kTextBytesMax)
                return std::nullopt;
            auto c = elem_bytes(t);
            if (!c)
                return std::nullopt;
            b.add(std::move(*c));
        }
        // len(b) >= l, not any(b[l:]), pretty_text(b[:l]) - python's
        // slices of a negative l
        const i64 size = i64(b.size);
        if (size < l)
            return std::nullopt;
        const u64 end = u64(l >= 0 ? l : std::max<i64>(0, l + size));
        if (!b.zero_from(end))
            return std::nullopt;
        return b.text(end);
    }

    // python's raw_text(el, printed): Bytes(n, 'text') when it's bytes of text
    void raw_text(Value el, Out& item)
    {
        if (item.s.empty() || item.s[0] != '\'')
            return;
        const auto b = elem_bytes(el);
        if (!b)
            return;
        Out r = item.sub();
        r.put("Bytes(" + std::to_string(b->size()) + ", ");
        r.append(item);
        r.put(')');
        item = std::move(r);
    }

    // python's pretty_memory
    void memory(Value e, const MemoryOpts& m, std::vector<Out>& res)
    {
        if (e.is_none() || e.nil())
            return;
        if (!e.is(Op::DATA)) {
            Out item = o.sub();
            {
                ExpImpl sub(p, item);
                sub.exp(e, P_NONE, false);
            }
            if (m.abi_text)
                raw_text(e, item);
            res.push_back(std::move(item));
            return;
        }
        std::vector<Value> els;
        flat_elements(e, els);
        memory_elements(els, m, res);
    }

    ExpImpl(Printer& pr, Out& other) : p(pr), o(other), env(pr.env_) {}

    void memory_joined(Value e, const MemoryOpts& m)
    {
        std::vector<Out> items;
        memory(e, m, items);
        for (usize i = 0; i < items.size(); ++i) {
            if (i)
                o.put(", ");
            o.append(items[i]);
        }
    }

    // ---- calldata: python's get_param_name ----
    void calldataload(Value e)
    {
        const Value loc = e[0];
        if (loc.is_small()) {
            if (const auto* w = env_word(loc.small_val())) {
                o.col(Col::green, w->name);
                return;
            }
        } else if (loc.is(Op::ADD, 2) && loc[0].is_small()) {
            const i64 off = loc[0].small_val();
            const Value base = loc[1];
            const ParamWordView pw = param_of(base);
            if (pw.word) {
                // a param is where the data it points to is (after the selector)
                if (off == 4 && pw.word->has_length) {
                    o.col(Col::green, pw.word->name + ".length");
                    return;
                }
                if (off >= 36 && (off - 36) % 32 == 0 && pw.word->array_of_words) {
                    o.col(Col::green, std::format("{}[{}]", pw.word->name, (off - 36) / 32));
                    return;
                }
            }
        }
        o.put("cd[");
        pret(loc);
        o.put(']');
    }

    struct ParamWordView {
        const ParamWord* word = nullptr;
    };
    const ParamWord* env_word(i64 loc) const noexcept { return env.word_at(loc); }
    ParamWordView param_of(Value v) const noexcept
    {
        if (v.is(Op::CALLDATALOAD, 1) && v[0].is_small())
            return {env.word_at(v[0].small_val())};
        if (v.is_name(NameKind::PARAM))
            return {env.word_of_param(v.name_id())};
        return {};
    }

    // ---- the expression ops ----
    void expr(Value e, int ctx, bool rem_bool)
    {
        const Op op = e.op();
        const u32 n = e.size();
        switch (op) {
            case Op::SIZED:
                if (n == 2) {
                    pretty_bytes(e[0], e[1], ctx);
                    return;
                }
                break;
            case Op::DATA:
                // the bytes of its elements one after the other
                o.put("concat(");
                memory_joined(e, {});
                o.put(')');
                return;
            case Op::RANGE:
                if (n == 2) {
                    pret(e[0]);
                    o.put(' ');
                    o.col(Col::header, "len");
                    o.put(' ');
                    pret(e[1]);
                    return;
                }
                break;
            case Op::SIGNEXTEND:
                if (n == 2) {
                    if (e[0].is_small()) {
                        o.col(Col::gray, std::format("int{}(", 8 * (e[0].small_val() + 1)));
                        pret(e[1]);
                        o.col(Col::gray, ")");
                        return;
                    }
                    o.put("signextend(");
                    pret(e[0]);
                    o.put(", ");
                    pret(e[1]);
                    o.put(')');
                    return;
                }
                break;
            case Op::ARR:
                if (n >= 1) {
                    o.col(Col::gray, "Array(len=");
                    pret(e[0]);
                    o.col(Col::gray, ", data=");
                    std::vector<Out> items;
                    // ("data",) + terms, but the zeroes that pad them to a word
                    // (the ABI's: the text's Array pads its data)
                    std::span<const Value> terms = e.args().subspan(1);
                    if (padding_at_end(terms, e[0]))
                        terms = terms.first(terms.size() - 1);
                    memory_terms(terms, {}, items);
                    for (usize i = 0; i < items.size(); ++i) {
                        if (i)
                            o.put(", ");
                        o.append(items[i]);
                    }
                    o.col(Col::gray, ")");
                    return;
                }
                break;
            case Op::BLOCKHASH: return call_form("block.hash", e);
            case Op::EXTCODEHASH: return call_form("ext_code.hash", e);
            case Op::EXTCODESIZE: return call_form("ext_code.size", e);
            case Op::BALANCE: return call_form("eth.balance", e);
            case Op::BLOBHASH: return call_form("blobhash", e);
            case Op::EXTCODE_BYTES:
                if (n == 2 && e[1].is(Op::RANGE, 2)) {
                    // the bytes of the code of the account
                    o.put("ext_code(");
                    pret(e[0]);
                    o.put(").data[");
                    pret(e[1][0]);
                    o.put(" len ");
                    pret(e[1][1]);
                    o.put(']');
                    return;
                }
                break;
            case Op::MAX: return call_form("max", e);
            case Op::MIN: return call_form("min", e);
            case Op::BYTE: return call_form("byte", e);
            case Op::CLZ: return call_form("clz", e);
            case Op::ADDMOD: return call_form("addmod", e);
            case Op::MULMOD: return call_form("mulmod", e);
            case Op::TLOAD:
                if (n == 1) {
                    o.col(Col::gray, "transient[");
                    pret(e[0]);
                    o.col(Col::gray, "]");
                    return;
                }
                break;
            case Op::CODE_BYTES:
                if (n == 2) {
                    o.put("code.data[");
                    pret(e[0]);
                    o.put(" len ");
                    pret(e[1]);
                    o.put(']');
                    return;
                }
                break;
            case Op::SHA3: {
                // of the bytes of its terms one after the other
                std::span<const Value> terms = e.args();
                if (terms.size() == 1 && terms[0].is(Op::DATA))
                    terms = terms[0].args();
                o.put("sha3(");
                std::vector<Out> items;
                memory_terms(terms, {}, items);
                for (usize i = 0; i < items.size(); ++i) {
                    if (i)
                        o.put(", ");
                    o.append(items[i]);
                }
                o.put(')');
                return;
            }
            case Op::CALLDATA_BYTES:
                if (n == 2) {
                    // a param's bytes: p[all]
                    if (e[0].is(Op::ADD, 2) && is_small(e[0][0], 36)) {
                        const ParamWordView pw = param_of(e[0][1]);
                        if (pw.word && e[1].is(Op::CALLDATALOAD, 1) && e[1][0].is(Op::ADD, 2) &&
                            is_small(e[1][0][0], 4) && e[1][0][1] == e[0][1]) {
                            o.col(Col::green, pw.word->name + "[");
                            o.put("all");
                            o.col(Col::green, "]");
                            return;
                        }
                    }
                    array_form("call.data", e[0], e[1]);
                    return;
                }
                break;
            case Op::RETURNDATA_BYTES:
                if (n == 3) {
                    array_form("ext_call.return_data", e[1], e[2]);
                    return;
                }
                break;
            case Op::MEM:
                if (n == 1 && e[0].is(Op::RANGE, 2)) {
                    o.col(Col::header, "mem[");
                    pret(e[0][0]);
                    if (!is_small(e[0][1], 32)) {
                        o.col(Col::header, " len ");
                        pret(e[0][1]);
                    }
                    o.col(Col::header, "]");
                    return;
                }
                break;
            case Op::CALLDATALOAD:
                if (n == 1) {
                    calldataload(e);
                    return;
                }
                break;
            case Op::STORAGE:
                if (n == 3) {
                    storage_read(e[0], e[1], e[2], ctx);
                    return;
                }
                break;
            case Op::LENGTH:
                if (n == 1) {
                    bytes_length(e[0], ctx);
                    return;
                }
                break;
            case Op::LOC:
                if (n == 1) {
                    exp(e[0], ctx, false);
                    return;
                }
                break;
            case Op::ST:
                if (n == 3) {
                    st(e[0], e[1], e[2]);
                    return;
                }
                break;
            case Op::SALL:
                if (n == 1) {
                    // the bytes of a bytes (or string) of the storage
                    loc(e[0]);
                    o.col(Col::green, "[all]");
                    return;
                }
                break;
            case Op::SV:
            case Op::SI:
            case Op::SL:
            case Op::SBL:
            case Op::SF:
            case Op::SR:
                // (a place alone: only inside ST, SET, SALL)
                loc(e);
                return;
            case Op::SAFEMATH:
                if (n >= 2 && e[0].is_small() && e[0].small_val() >= 0) {
                    safemath_call(e);
                    return;
                }
                break;
            case Op::MASK_SHL:
                if (n == 4) {
                    mask_shl(e[0], e[1], e[2], e[3], ctx);
                    return;
                }
                break;
            case Op::MASK:
                if (n == 3) {
                    mask(e[0], e[1], e[2], ctx);
                    return;
                }
                break;
            case Op::BOOL:
                if (n == 1) {
                    bool_case(e[0], ctx);
                    return;
                }
                break;
            case Op::SAR:
                if (n == 2) {
                    // the arithmetic shift (>>′, like the other signed operations)
                    Wrap w(o, P_SHIFT, ctx);
                    exp(e[1], P_SHIFT, false);
                    op_form(" >>′ ");
                    exp(e[0], P_SHIFT + 1, false);
                    return;
                }
                break;
            case Op::NOT:
                if (n == 1) {
                    // bitwise, as in python: `not` is the logical one (iszero)
                    Wrap w(o, P_UNARY, ctx);
                    o.col(Col::bold, "~");
                    exp(e[0], P_UNARY, false);
                    return;
                }
                break;
            case Op::ADD:
                adds(e, ctx);
                return;
            case Op::MUL:
                mul(e, ctx);
                return;
            case Op::DIV:
                if (n == 2 && is_small(e[1], 1)) {
                    exp(e[0], ctx, false);
                    return;
                }
                arith(op, e, ctx, rem_bool);
                return;
            case Op::EXP:
                if (n == 2) {
                    Wrap w(o, P_POW, ctx);
                    exp(e[0], P_POW + 1, false);
                    o.put("**");
                    exp(e[1], P_POW, false);
                    return;
                }
                break;
            case Op::LAND:
            case Op::LOR: {
                // python's and / or (postprocess.short_circuits): the operand
                // that decides - printed as the value it is where it may be the
                // one given (the last of an and, any of an or), unless only its
                // truth counts
                const bool land = op == Op::LAND;
                const int prec = land ? P_AND : P_OR;
                Wrap w(o, prec, ctx);
                for (u32 i = 0; i < n; ++i) {
                    if (i)
                        op_form(land ? " and " : " or ");
                    exp(e[i], prec, rem_bool || (land && i + 1 < n));
                }
                return;
            }
            case Op::FAND:
            case Op::FOR:
                arith(op == Op::FAND ? Op::AND : Op::OR, e, ctx, true);
                return;
            case Op::ISZERO:
                if (n == 1) {
                    iszero_case(e[0], ctx);
                    return;
                }
                break;
            case Op::SUB:
            case Op::SDIV:
            case Op::MOD:
            case Op::SMOD:
            case Op::SHL:
            case Op::SHR:
            case Op::AND:
            case Op::OR:
            case Op::XOR:
            case Op::EQ:
            case Op::SGE:
            case Op::SLE:
            case Op::SGT:
            case Op::SLT:
            case Op::LT:
            case Op::GT:
            case Op::LE:
            case Op::GE:
                arith(op, e, ctx, rem_bool);
                return;
            default:
                break;
        }
        generic(e);
    }

    // anything else: its op and operands (python's str(exp) of a tuple it can't print)
    void generic(Value e)
    {
        o.put(op_name(e.op()));
        o.put('(');
        for (u32 i = 0; i < e.size(); ++i) {
            if (i)
                o.put(", ");
            pret(e[i]);
        }
        o.put(')');
    }

    // ---- lot 9's storage forms (python pretty_loc, prettify's st, sall) ----

    // python's pretty_loc: a place of the storage - name[key].field_n,
    // name.length, stor[slot]
    void loc(Value l)
    {
        check_stack();
        switch (l.op()) {
            case Op::SV:
                if (l.size() == 1 && l[0].is_name()) {
                    o.col(Col::green, env.name_text(l[0]));
                    return;
                }
                break;
            case Op::SI:
                if (l.size() == 2) {
                    loc(l[0]);
                    o.col(Col::green, "[");
                    pret(l[1]);
                    o.col(Col::green, "]");
                    return;
                }
                break;
            case Op::SL:
            case Op::SBL:
                if (l.size() == 1) {
                    loc(l[0]);
                    o.col(Col::green, ".length");
                    return;
                }
                break;
            case Op::SF:
                if (l.size() == 2) {
                    loc(l[0]);
                    o.col(Col::green, ".field_");
                    pret(l[1]);
                    return;
                }
                break;
            case Op::SR:
                if (l.size() == 1) {
                    o.col(Col::green, "stor[");
                    pret(l[0]);
                    o.col(Col::green, "]");
                    return;
                }
                break;
            default:
                break;
        }
        // (python's str(loc): no place)
        if (l.is_expr())
            generic(l);
        else
            pret(l);
    }

    // python's st: an access of the storage - the place, cast when fewer
    // bits are read than the place has
    void st(Value size, Value l, Value width)
    {
        if (size == width || width.is_none() || width.nil()) {
            loc(l);
            return;
        }
        // (address or uint{pret(size)})(text)
        Out name = o.sub();
        if (is_small(size, 160)) {
            name.put("address");
        } else {
            name.put("uint");
            ExpImpl sub(p, name);
            sub.pret(size);
        }
        name.put('(');
        if (o.add_color)
            o.code(Col::gray);
        o.append(name);
        if (o.add_color)
            o.end();
        loc(l);
        o.col(Col::gray, ")");
    }

    // a call of a function of the contract's SafeMath (lot 8): its operands,
    // then the messages it fails with, string literals
    void safemath_call(Value e)
    {
        const SafeMathTable* t = env.safemath();
        const u32 index = u32(std::min<i64>(e[0].small_val(), i64(UINT32_MAX)));
        const bool known = t && index < t->fns.size();
        const u32 operands = known ? t->fns[index].params : std::min<u32>(2, e.size() - 1);
        o.put("SafeMath.");
        o.put(known ? safemath_name(*t, index) : std::format("f{}", index));
        o.put('(');
        for (u32 i = 1; i < e.size(); ++i) {
            if (i > 1)
                o.put(", ");
            if (i <= operands) {
                pret(e[i]);
            } else if (const auto m = error_message_text(e[i])) {
                o.put(*m);
            } else {
                pret(e[i]);
            }
        }
        o.put(')');
    }

    // ("data",) + terms through pretty_memory
    void memory_terms(std::span<const Value> terms, const MemoryOpts& m, std::vector<Out>& items)
    {
        // as a DATA's elements (flattened)
        std::vector<Value> els;
        for (const Value t : terms) {
            if (t.is(Op::DATA))
                flat_elements(t, els);
            else
                els.push_back(t);
        }
        memory_elements(els, m, items);
    }
    void memory_elements(std::span<const Value> els, const MemoryOpts& m, std::vector<Out>& items);

    void call_form(std::string_view name, Value e)
    {
        o.put(name);
        o.put('(');
        for (u32 i = 0; i < e.size(); ++i) {
            if (i)
                o.put(", ");
            pret(e[i]);
        }
        o.put(')');
    }

    // python's array ops (call.data, ext_call.return_data): x[off] or x[off len n]
    void array_form(std::string_view name, Value off, Value len)
    {
        o.put(name);
        o.put('[');
        pret(off);
        if (!is_small(len, 32)) {
            o.put(" len ");
            pret(len);
        }
        o.put(']');
    }

    // ---- storage, before lot 9's names (python's storage.raw: the access
    // as the slot it is) ----
    void stor_slot(Value slot)
    {
        if (slot.is(Op::LOC, 1))
            slot = slot[0];
        o.col(Col::green, "stor[");
        pret(slot);
        o.col(Col::green, "]");
    }

    // python storage.raw of the length of a bytes (solidity's: the slot's
    // low bit says short or long): (stor[k] & 256 * (not uint1(stor[k])) - 1) / 2
    void bytes_length(Value key, int ctx)
    {
        if (key.is(Op::LOC, 1))
            key = key[0];
        Wrap w(o, P_MUL, ctx);
        o.put('(');
        stor_slot(key);
        op_form(" & ");
        print_int(EvmInt(i64(256)), P_MUL);
        op_form(" * ");
        o.put("(not ");
        o.col(Col::gray, "uint1(");
        stor_slot(key);
        o.col(Col::gray, ")");
        o.put(')');
        o.put(" - ");
        print_int(EvmInt(i64(1)), P_ADD + 1);
        o.put(')');
        op_form(" / ");
        print_int(EvmInt(i64(2)), P_MUL + 1);
    }

    // python raw(size, off, idx): st(size, sr(idx), 256), st(size, sf(sr(idx),
    // off), 256 - off); at an offset computed at runtime mask_shl(size, off,
    // -off, st(256, sr(idx), 256)); a bytes' length mask_shl(size, off, -off,
    // its formula)
    void storage_read(Value size, Value off, Value slot, int ctx)
    {
        if (slot.is(Op::LENGTH, 1)) {
            const Value key = slot[0];
            if (is_small(size, 256) && is_small(off, 0)) {
                bytes_length(key, ctx);
                return;
            }
            if (off.is_small()) {
                mask_shl_v(size, off, Value::small(-off.small_val()), [&](int c) { bytes_length(key, c); }, false, false,
                           ctx);
                return;
            }
            o.put("Mask(");
            pret(size);
            o.put(", ");
            pret(off);
            o.put(", ");
            bytes_length(key, P_NONE);
            o.put(')');
            return;
        }
        if (size.is_small() && off.is_small() && off.small_val() >= 0) {
            const i64 s = size.small_val(), f = off.small_val();
            const i64 width = 256 - f;
            const bool cast = s != width;
            if (cast) {
                o.col(Col::gray, s == 160 ? std::string("address(") : std::format("uint{}(", s));
            }
            stor_slot(slot);
            if (f > 0) {
                o.col(Col::green, ".field_");
                o.put(std::to_string(f));
            }
            if (cast)
                o.col(Col::gray, ")");
            return;
        }
        if (off.is_small()) {
            mask_shl_v(size, off, Value::small(-off.small_val()), [&](int) { stor_slot(slot); }, false, false, ctx);
            return;
        }
        // bits at an offset computed at runtime: Mask(size, off, stor[idx]) >> off
        Wrap w(o, P_SHIFT, ctx);
        mask_v(size, off, [&](int) { stor_slot(slot); }, false, P_SHIFT);
        op_form(" >> ");
        exp(off, P_SHIFT + 1, false);
    }

    // ---- masks: python's mask_shl and mask cases ----
    // (the value masked: a Value, or a form python made of one - a storage
    // read - printed by a callback val(ctx); wide: it may have more than 256
    // bits (python's may_be_wide); data: it is a DATA)

    // python's ("mask", size, off, val) printed at ctx
    void mask(Value size, Value off, Value val, int ctx)
    {
        mask_v(size, off, [&](int c) { exp(val, c, false); }, alg::may_be_wide(val), ctx);
    }

    template <class F>
    void mask_v(Value size, Value off, F&& val, bool wide, int ctx)
    {
        if (is_small(off, 0)) {
            if (is_small(size, 256) && !wide) {
                val(ctx);
                return;
            }
            if (size.is_small()) {
                const i64 s = size.small_val();
                if (s != 1 && s != 256) {
                    // (the lowest bit of a number isn't a bool: x % 2, below)
                    std::optional<std::string> type_name;
                    if (s == 255)
                        type_name = "uint255";
                    else if (auto t = mask_to_type(s))
                        type_name = std::string(*t);
                    else if (s > 0 && s < 256 && s % 8 == 0)
                        type_name = std::format("uint{}", s);
                    if (type_name) {
                        o.col(Col::gray, *type_name + "(");
                        val(P_NONE);
                        o.col(Col::gray, ")");
                        return;
                    }
                }
            }
        }
        if (size.is_small() && is_small(off, 0) && size.small_val() < 64) {
            // ("mod", val, 2**size)
            Wrap w(o, P_MUL, ctx);
            val(P_MUL);
            op_form(" % ");
            const i64 s = size.small_val();
            print_int(s >= 0 ? EvmInt::pow2(u64(s)) : EvmInt(i64(0)), P_MUL + 1);
            return;
        }
        o.put("Mask(");
        pret(size);
        o.put(", ");
        pret(off);
        o.put(", ");
        val(P_NONE);
        o.put(')');
    }

    // ("div", X, 2**k) with X printed by f at a ctx
    template <class F>
    void div_pow2(F&& x, u64 k, int ctx)
    {
        Wrap w(o, P_MUL, ctx);
        x(P_MUL);
        op_form(" / ");
        print_int(EvmInt::pow2(k), P_MUL + 1);
    }

    void mask_shl(Value size, Value off, Value shl, Value val, int ctx)
    {
        const bool concrete = size.is_small() && off.is_small() && shl.is_small();
        const i64 s = concrete ? size.small_val() : 0, f = concrete ? off.small_val() : 0, h = concrete ? shl.small_val() : 0;
        // a storage access (lot 9's ST) under a mask, shifted right by its
        // offset: its bits from off on
        if (concrete && f > 0 && h == -f && val.is(Op::ST, 3) && val[0].is_small()) {
            const i64 bits = val[0].small_val();
            const i64 top = s + f;
            const bool usual = top == 8 || top == 16 || top == 32 || top == 64 || top == 128 || top == 256;
            // python's other_2: no wider than the mask's top, off 1..8: val / 2**off
            if (f <= 8 && usual && bits <= top) {
                div_pow2([&](int c) { exp(val, c, false); }, u64(f), ctx);
                return;
            }
            // prettify's: of fewer bits than the mask's top - val / 2**off
            // (off < 8), val >> off
            if (bits <= top) {
                if (f < 8) {
                    div_pow2([&](int c) { exp(val, c, false); }, u64(f), ctx);
                    return;
                }
                Wrap w(o, P_SHIFT, ctx);
                exp(val, P_SHIFT, false);
                op_form(" >> ");
                print_int(EvmInt(f), P_NONE);
                return;
            }
        }
        // ceil32 / floor32
        if (concrete && s == 251 && f == 5 && h == 0 && val.is(Op::ADD, 2) && is_small(val[0], 31)) {
            o.put("ceil32(");
            pret(val[1]);
            o.put(')');
            return;
        }
        // python's other_2: address(caller) is caller...
        if (concrete && s == 160 && f == 0 && h == 0 && val.is_leaf()) {
            switch (val.op()) {
                case Op::CALLER:
                case Op::ORIGIN:
                case Op::ADDRESS:
                case Op::COINBASE:
                    leaf(val);
                    return;
                default:
                    break;
            }
        }
        // the first 4 bytes of the calldata, as msg.sig
        if (concrete && s == 32 && f == 224 && val.is(Op::CALLDATALOAD, 1) && is_small(val[0], 0)) {
            if (h == 0) {
                o.col(Col::green, "call.func_hash");
                return;
            }
            if (h == -224) {
                Wrap w(o, P_SHIFT, ctx);
                o.col(Col::green, "call.func_hash");
                o.put(" >> 224");
                return;
            }
        }
        mask_shl_v(size, off, shl, [&](int c) { exp(val, c, false); }, alg::may_be_wide(val), val.is(Op::DATA), ctx);
    }

    template <class F>
    void mask_shl_v(Value size, Value off, Value shl, F&& val, bool wide, bool data, int ctx)
    {
        const bool concrete = size.is_small() && off.is_small() && shl.is_small();
        const i64 s = concrete ? size.small_val() : 0, f = concrete ? off.small_val() : 0, h = concrete ? shl.small_val() : 0;
        if (concrete && s == 251 && f == 5 && h == 0) {
            o.put("floor32(");
            val(P_NONE);
            o.put(')');
            return;
        }
        // python's other_2: Mask(size, off, e) >> off for off in 1..8 and a
        // usual top: uintN(e) / 2**off
        if (concrete && h == -f && f >= 1 && f <= 8) {
            const i64 top = s + f;
            if (top == 8 || top == 16 || top == 32 || top == 64 || top == 128 || top == 256) {
                div_pow2([&](int c) { mask_v(Value::small(top), Value::small(0), val, wide, c); }, u64(f), ctx);
                return;
            }
        }
        if (concrete) {
            // python A: of a word, the top of the mask its top, a small offset: a division
            if (s + f == 256 && f == -h && f < 8 && !wide) {
                if (f <= 0) {
                    val(ctx);
                    return;
                }
                div_pow2(val, u64(f), ctx);
                return;
            }
            // python B: moved left by its offset (< 8): the bits in place, times 2**shl
            if (f == h && f < 8) {
                const bool keep_mask = s + f != 256 || f != 0 || wide;
                auto inner = [&](int c) {
                    if (keep_mask)
                        mask_v(size, off, val, wide, c);
                    else
                        val(c);
                };
                if (h == 0) {
                    inner(ctx);
                    return;
                }
                if (h <= 8 && h >= -8) {
                    // ("mul", val, 2**shl)
                    if (h < 0) {
                        // (python's float 2**-k: a division, exactly)
                        div_pow2(inner, u64(-h), ctx);
                        return;
                    }
                    Wrap w(o, P_MUL, ctx);
                    inner(P_MUL);
                    op_form(" * ");
                    print_int(EvmInt::pow2(u64(h)), P_MUL + 1);
                    return;
                }
                Wrap w(o, P_SHIFT, ctx);
                inner(P_SHIFT);
                op_form(h > 0 ? " << " : " >> ");
                print_int(EvmInt(i64(h > 0 ? h : -h)), P_SHIFT + 1);
                return;
            }
            // python D: val >> offset, with the bits above size cut off
            if (f == -h && f >= 8 && f < 256 && s > 0 && s <= 256 - f && !data) {
                auto shifted = [&]() {
                    val(P_SHIFT);
                    op_form(" >> ");
                    print_int(EvmInt(f), P_NONE);
                };
                if (s + f == 256) {
                    Wrap w(o, P_SHIFT, ctx);
                    shifted();
                    return;
                }
                if (s == 1) {
                    // its lowest bit: not a bool (bool(x) is x != 0)
                    Wrap w(o, P_MUL, ctx);
                    o.put('(');
                    shifted();
                    o.put(')');
                    op_form(" % ");
                    o.put('2');
                    return;
                }
                std::optional<std::string> type_name;
                if (auto t = mask_to_type(s))
                    type_name = std::string(*t);
                else if (s % 8 == 0)
                    type_name = std::format("uint{}", s);
                if (type_name) {
                    o.col(Col::gray, *type_name + "(");
                    shifted();
                    o.col(Col::gray, ")");
                    return;
                }
            }
        }
        // python F: the mask, then the shift
        auto the_mask = [&](int c) { mask_v(size, off, val, wide, c); };
        if (is_small(shl, 0)) {
            the_mask(ctx);
            return;
        }
        const int sign = shift_sign(shl);
        if (sign == 1) {
            if (concrete && s + h == 256 && f == 0) {
                // the bits that the multiplication keeps: ("mul", 2**shl, val)
                mul_pow2(u64(h), val, ctx);
                return;
            }
            if (shl.is_small() && shl.small_val() < 7) {
                mul_pow2(u64(shl.small_val()), the_mask, ctx);
                return;
            }
            Wrap w(o, P_SHIFT, ctx);
            the_mask(P_SHIFT);
            op_form(" << ");
            exp(shl, P_SHIFT + 1, false);
            return;
        }
        if (sign == -1) {
            if (shl.is_small() && -shl.small_val() <= 8) {
                div_pow2(the_mask, u64(-shl.small_val()), ctx);
                return;
            }
            Wrap w(o, P_SHIFT, ctx);
            the_mask(P_SHIFT);
            op_form(" >> ");
            negated_amount(shl, P_SHIFT + 1);
            return;
        }
        // a shift that may be one way or the other
        o.put("shift(");
        the_mask(P_NONE);
        o.put(", ");
        pret(shl);
        o.put(')');
    }

    // ("mul", 2**k, X): 2**k * X, or X << k past 2**32
    template <class F>
    void mul_pow2(u64 k, F&& x, int ctx)
    {
        if (k > 32) {
            Wrap w(o, P_SHIFT, ctx);
            x(P_SHIFT);
            op_form(" << ");
            print_int(EvmInt(i64(k)), P_SHIFT + 1);
            return;
        }
        Wrap w(o, P_MUL, ctx);
        print_int(EvmInt::pow2(k), P_MUL);
        op_form(" * ");
        x(P_MUL + 1);
    }

    // python's shift_sign, structurally: 1 a left shift (a word), -1 a right one
    static int shift_sign(Value shl) noexcept
    {
        if (shl.is_small())
            return shl.small_val() > 0 ? 1 : shl.small_val() < 0 ? -1 : 0;
        if (shl.is(Op::MUL) && shl.size() >= 2 && shl[0].is_small() && shl[0].small_val() < 0)
            return -1;
        if (shl.is(Op::ADD) && shl.size() >= 2 && shl[0].is_small() && shl[0].small_val() < 0) {
            // -k + x: a right shift when every term is minus something
            for (const Value t : shl.args().subspan(1))
                if (!(t.is(Op::MUL) && t.size() >= 2 && t[0].is_small() && t[0].small_val() < 0))
                    return 0;
            return -1;
        }
        // masks, reads of a few bytes: words
        switch (shl.op()) {
            case Op::MASK_SHL:
            case Op::CALLDATALOAD:
            case Op::MEM:
            case Op::STORAGE:
                return 1;
            default:
                return 0;
        }
    }

    // python's minus_op(shl) printed: the amount of a right shift
    void negated_amount(Value shl, int ctx)
    {
        if (shl.is_small()) {
            print_int(EvmInt(-shl.small_val()), ctx);
            return;
        }
        if (shl.is(Op::MUL) && shl.size() >= 2 && shl[0].is_int()) {
            mul_minus(shl, ctx);
            return;
        }
        Wrap w(o, P_UNARY, ctx);
        o.put('-');
        exp(shl, P_UNARY, false);
    }
};

void ExpImpl::memory_elements(std::span<const Value> els, const MemoryOpts& m, std::vector<Out>& items)
{
    // pretty_memory of ("data",) + els: built as a view over the elements
    // (the same as memory() of a DATA of them)
    if (els.empty())
        return;
    // (a DATA node isn't made: memory() reads the elements through flat_elements)
    std::vector<Value> copy(els.begin(), els.end());
    const usize n = copy.size();
    usize idx = 0;
    while (idx < n) {
        poll();
        Out item = o.sub();
        if (m.selector && idx == 0) {
            if (const auto sel = selector_int(copy[0])) {
                const u32 s = u32(sel->mod_2exp(32).to_u64().value_or(0));
                if (!known_fname(item, env.db(), s))
                    item.put(std::format("{:#010x}", s));
                items.push_back(std::move(item));
                idx += 1;
                continue;
            }
        }
        const Value el = copy[idx];
        const bool first = idx == 0 || (idx == 1 && sized4(copy[0]));
        if (m.abi_text && first && idx == n - 1) {
            if (auto t = arr_text(el)) {
                item.put(*t);
                items.push_back(std::move(item));
                idx += 1;
                continue;
            }
        }
        // past 16 MiB of the bytes of its elements, an element is printed as
        // it is (the asm's PM_BYTES_MAX)
        bool as_element = false;
        if (first && idx + 1 < n) {
            const auto w0 = word_int(el);
            const auto w1 = word_int(copy[idx + 1]);
            if (w0 && *w0 == 32 && w1 && w1->sign() > 0) {
                // size = 32 * ((length + 31) // 32); a length past 2^40 is
                // past any data, its bytes made all the same (as the asm)
                const bool big = w1->bit_length() > 40;
                const u64 length = big ? ~u64(0) : w1->to_u64().value_or(0);
                const u64 size = big ? ~u64(0) : 32 * ((length + 31) / 32);
                DataBytes b;
                usize end = idx + 2;
                while (end < n && b.size < size) {
                    if (b.size >= kTextBytesMax) {
                        as_element = true;
                        break;
                    }
                    auto chunk = elem_bytes(copy[end]);
                    if (!chunk)
                        break;
                    b.add(std::move(*chunk));
                    end += 1;
                }
                if (!as_element && b.size == size && end == n && b.zero_from(length)) {
                    if (auto t = b.text(length)) {
                        if (!m.abi_text)
                            item.put(std::format("Array(len={}, data={})", length, *t));
                        else
                            item.put(*t);
                        items.push_back(std::move(item));
                        idx = end;
                        continue;
                    }
                }
            }
        }
        if (!as_element) {
            // bytes that are text, as parts of the data (hashed, say): no
            // zero is text, so the first element with one ends the search
            usize end = idx;
            DataBytes b;
            bool zero = false;
            while (end < n) {
                if (b.size >= kTextBytesMax) {
                    as_element = true;
                    break;
                }
                auto c = elem_bytes(copy[end]);
                if (!c)
                    break;
                zero = zero || c->zeros > 0 || std::ranges::find(c->rest, u8(0)) != c->rest.end();
                b.add(std::move(*c));
                ++end;
                if (zero)
                    break;
            }
            if (!as_element && !zero && b.size >= 4) {
                if (auto t = b.text(b.size)) {
                    if (m.abi_text && first && end == n)
                        item.put(std::format("Bytes({}, {})", b.size, *t));
                    else
                        item.put(*t);
                    items.push_back(std::move(item));
                    idx = end;
                    continue;
                }
            }
        }
        {
            ExpImpl sub(p, item);
            sub.element(el);
        }
        if (m.abi_text && first && idx == n - 1)
            raw_text(el, item);
        items.push_back(std::move(item));
        idx += 1;
    }
}

// ---- Printer's entries ---------------------------------------------------------------------

void Printer::exp(Value e, int ctx, bool rem_bool)
{
    ExpImpl x(*this);
    x.exp(e, ctx, rem_bool);
}

void Printer::memory(Value e, const MemoryOpts& m, std::vector<Out>& items)
{
    ExpImpl x(*this);
    x.memory(e, m, items);
}

void Printer::memory_elements(std::span<const Value> els, const MemoryOpts& m, std::vector<Out>& items)
{
    ExpImpl x(*this);
    std::vector<Value> flat;
    for (const Value e : els) {
        if (e.is(Op::DATA))
            flat_elements(e, flat);
        else
            flat.push_back(e);
    }
    x.memory_elements(flat, m, items);
}

void Printer::integer(const EvmInt& v, int ctx)
{
    ExpImpl x(*this);
    x.print_int(v, ctx);
}

void Printer::memory_joined(Value e, const MemoryOpts& m)
{
    std::vector<Out> items;
    memory(e, m, items);
    for (usize i = 0; i < items.size(); ++i) {
        if (i)
            o_.put(", ");
        o_.append(items[i]);
    }
}

void Printer::negated(Value e, int ctx)
{
    ExpImpl x(*this);
    // python: prettify(is_zero(e), rem_bool=True)
    const ExpImpl::SB s = x.simplify_bool(e);
    if (s.neg)
        x.exp(s.v, ctx, true);
    else
        x.is_zero(s.v, ctx, true);
}

}  // namespace pan::output::detail
