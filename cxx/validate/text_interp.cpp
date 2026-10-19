// The interpreter of the decompiled text (text_interp.hpp).
#include "validate/text_interp.hpp"

#include <algorithm>
#include <cstring>
#include <utility>

namespace validate::text
{
namespace
{
constexpr std::uint32_t error_selector = 0x08c379a0;  // Error(string)
constexpr std::uint32_t panic_selector = 0x4e487b71;  // Panic(uint256)

/// The end of a call, thrown from wherever it happens (a revert in a
/// SafeMath function inside an expression...).
struct Halt
{
    End end;
};

/// A construct the text doesn't say precisely enough to run.
struct Unsup
{
    Unsupported why;
};

Word mask_of(unsigned bits) noexcept
{
    return bits >= 256 ? ~Word{0} : (Word{1} << bits) - 1;
}

/// The number of up to 32 bytes, big-endian.
Word from_be(BytesView b) noexcept
{
    std::uint8_t buf[32] = {};
    const std::size_t n = std::min<std::size_t>(b.size(), 32);
    std::memcpy(buf + 32 - n, b.data() + (b.size() - n), n);
    return intx::be::load<Word>(buf);
}

void put_word(Bytes& out, const Word& w)
{
    const auto b = to_bytes(w);
    out.insert(out.end(), b.begin(), b.end());
}

/// The n bytes of a number: its low n bytes, zeroes above its word.
void put_low(Bytes& out, const Word& w, std::size_t n)
{
    const auto b = to_bytes(w);
    if (n > 32)
    {
        out.insert(out.end(), n - 32, 0);
        out.insert(out.end(), b.begin(), b.end());
    }
    else
        out.insert(out.end(), b.end() - static_cast<std::ptrdiff_t>(n), b.end());
}

/// The last n bytes of b, zeroes before when it's shorter.
void put_last(Bytes& out, BytesView b, std::size_t n)
{
    if (b.size() >= n)
        out.insert(out.end(), b.end() - static_cast<std::ptrdiff_t>(n), b.end());
    else
    {
        out.insert(out.end(), n - b.size(), 0);
        out.insert(out.end(), b.begin(), b.end());
    }
}

void put_selector(Bytes& out, std::uint32_t sel)
{
    out.push_back(static_cast<std::uint8_t>(sel >> 24));
    out.push_back(static_cast<std::uint8_t>(sel >> 16));
    out.push_back(static_cast<std::uint8_t>(sel >> 8));
    out.push_back(static_cast<std::uint8_t>(sel));
}

/// A string ABI-encoded: its offset, its length, its bytes padded to words.
void put_abi_string(Bytes& out, BytesView s)
{
    put_word(out, Word{32});
    put_word(out, Word{s.size()});
    out.insert(out.end(), s.begin(), s.end());
    out.insert(out.end(), (32 - s.size() % 32) % 32, 0);
}

constexpr Word sign_bit = Word{1} << 255;

bool slt(const Word& a, const Word& b) noexcept
{
    return (a ^ sign_bit) < (b ^ sign_bit);
}

Word sar(const Word& x, const Word& shift) noexcept
{
    const bool neg = (x & sign_bit) != 0;
    if (shift >= 256)
        return neg ? ~Word{0} : Word{0};
    const auto s = static_cast<unsigned>(shift);
    if (!neg)
        return x >> s;
    return ~((~x) >> s);
}

Word signextend(const Word& b, const Word& x) noexcept
{
    if (b >= 31)
        return x;
    const auto bit = static_cast<unsigned>(b) * 8 + 7;
    const Word m = mask_of(bit + 1);
    return ((x >> bit) & 1) != 0 ? (x | ~m) : (x & m);
}

/// A word of the bits of a cast: the low `bits` sign-extended.
Word cast_int(const Word& x, unsigned bits) noexcept
{
    if (bits >= 256 || bits == 0)
        return x;
    const Word m = mask_of(bits);
    return ((x >> (bits - 1)) & 1) != 0 ? (x | ~m) : (x & m);
}

/// A word as a size in bytes the memory or the data can hold (else the
/// limit of the EVM: out of gas).
std::size_t size_of(const Word& n, std::uint64_t limit)
{
    if (n > Word{limit})
        throw Halt{End::exhausted("a size beyond the memory limit")};
    return static_cast<std::size_t>(n);
}

bool is_value(const SType& t) noexcept
{
    return t.kind == SType::value;
}

/// The bits a loc of type t is, read whole: a value's, else a word.
unsigned value_width(const Program& p, std::uint32_t t) noexcept
{
    return t != none && is_value(p.types[t]) ? p.types[t].width : 256;
}

/// The bits an element of type t takes in an array (a packed value's).
unsigned elem_width(const Program& p, std::uint32_t t) noexcept
{
    if (t == none)
        return 256;
    const auto& st = p.types[t];
    if (is_value(st) && st.width < 256 && st.width >= 8 && 256 % st.width == 0)
        return st.width;
    return 256;
}

/// The slots an element of type t takes in an array (a struct's).
unsigned stride_of(const Program& p, std::uint32_t t) noexcept
{
    if (t == none)
        return 1;
    const auto& st = p.types[t];
    return st.kind == SType::struct_ && st.width > 1 ? st.width : 1;
}

/// The place of a storage access: its slot, its bits, its type.
struct Loc
{
    Word slot;
    unsigned bit = 0;
    unsigned width = 256;
    std::uint32_t type = none;
    bool bytes_length = false;  // the length of a bytes: computed from its slot
};
}  // namespace

std::string_view to_string(Unsupported u) noexcept
{
    switch (u)
    {
    case Unsupported::msize: return "msize";
    case Unsupported::aborted: return "decompilation aborted";
    case Unsupported::unparsed: return "a line the parser couldn't read";
    case Unsupported::member: return "a member of a struct param (names unknown)";
    case Unsupported::mask_range: return "Mask of a size or offset out of range";
    case Unsupported::wide_number: return "bytes of more than 32 used as a number";
    case Unsupported::data_size: return "a memory write of data of another size";
    case Unsupported::unset_variable: return "a variable read before it is set";
    case Unsupported::storage_path: return "a storage place its type can't place";
    case Unsupported::param_path: return "a param place its type can't place";
    case Unsupported::recursion: return "internal functions nested too deep";
    case Unsupported::results: return "a function without the results it is used for";
    case Unsupported::no_function: return "no function for the selector, no fallback";
    case Unsupported::lvalue: return "an assignment to something that can't be set";
    case Unsupported::depth: return "blocks or expressions nested too deep";
    case Unsupported::bytes_encoding: return "a storage bytes of an invalid encoding";
    case Unsupported::other: return "other";
    case Unsupported::count: break;
    }
    return "?";
}

/// One call, run.
class Run
{
public:
    Run(Interpreter& in, Session& s)
      : in_(in), P(*in.program_), s_(s), lim_(in.limits_), ctx_(s.context())
    {}

    End call(const Function* fn);

private:
    enum class Ctl : std::uint8_t
    {
        next,
        continue_,
        break_,
        leave,
    };
    struct Flow
    {
        Ctl kind = Ctl::next;
        std::uint16_t label = 0;
    };

    struct Frame
    {
        const Function* fn = nullptr;
        std::vector<Word> vars;
        std::vector<std::uint8_t> set;
        std::vector<Word> args;  // an internal function's params
    };

    struct SmFrame
    {
        const SafeMathDef* def = nullptr;
        Word values[2];
        std::span<const ExprId> messages;
    };

    /// Counts a step (or ends the call: its budget is spent).
    void step()
    {
        if (++steps_ > lim_.steps)
            throw Halt{End::exhausted("the steps' limit")};
    }

    struct Deeper
    {
        explicit Deeper(Run& r) : r_(r)
        {
            if (++r_.depth_ > r_.lim_.depth)
                throw Unsup{Unsupported::depth};
        }
        ~Deeper() { --r_.depth_; }
        Run& r_;
    };

    const Expr& ex(ExprId e) const { return P.exprs[e]; }
    ExprId kid(ExprId e, unsigned i) const { return P.kids[P.exprs[e].kids + i]; }

    // values
    Word eval(ExprId e);
    Word eval_binary(const Expr& x, ExprId e);
    Word var(std::uint32_t id);
    Word number_of_bytes(ExprId e);

    // bytes
    bool sized(ExprId e) const;
    ExprId resolve(ExprId e) const;
    void elem(ExprId e, Bytes& out);
    void data(std::span<const ExprId> list, Bytes& out);
    Bytes abi_data(std::span<const ExprId> list);
    Bytes revert_data(const Stmt& s);

    // memory, calldata, return data, code
    Bytes mem_read(const Word& at, const Word& n);
    void mem_write(const Word& at, BytesView b);
    static void copy_out(BytesView src, const Word& at, std::size_t n, Bytes& out);

    // the storage and the params
    bool storage_path(ExprId e) const;
    bool param_path(ExprId e) const;
    Loc loc(ExprId e);
    Word read(const Loc& l);
    void write(const Loc& l, const Word& value, unsigned bits);
    std::pair<std::uint32_t, const PType*> param_place(ExprId e);
    Word param_value(ExprId e);
    const std::vector<NameTree>* names_of_params();

    // statements
    Flow block(const std::vector<StmtId>& b);
    Flow exec(StmtId id);
    void assign(ExprId lhs, const Word& value);
    void assign_memory(const Stmt& s);
    void call_stmt(const Stmt& s);
    void create_stmt(const Stmt& s);
    void precompiled(const Stmt& s);
    void internal_call(const Stmt& s);
    Word safemath(ExprId e);
    Frame& frame() { return frames_.back(); }

    Interpreter& in_;
    const Program& P;
    Session& s_;
    const InterpLimits& lim_;
    const CallContext& ctx_;
    std::uint64_t steps_ = 0;
    std::uint32_t depth_ = 0;
    std::vector<Frame> frames_;
    std::vector<SmFrame> sm_;
    std::vector<Word> leave_;
    Bytes mem_;
    Bytes ret_;
    Word last_success_ = 0;
    Word create_address_ = 0;
    std::optional<std::vector<NameTree>> names_;
    bool names_asked_ = false;
};

// --- values ------------------------------------------------------------------------------

Word Run::var(std::uint32_t id)
{
    Frame& f = frame();
    if (id >= f.vars.size() || !f.set[id])
        throw Unsup{Unsupported::unset_variable};
    return f.vars[id];
}

Word Run::number_of_bytes(ExprId e)
{
    Bytes b;
    elem(e, b);
    if (b.size() > 32)
        throw Unsup{Unsupported::wide_number};
    return from_be(b);
}

Word Run::eval(ExprId e)
{
    step();
    const Deeper d(*this);
    const Expr& x = ex(e);
    switch (x.op)
    {
    case Op::num: return P.nums[x.aux];
    case Op::big:
    {
        // modulo 2**256: its low 32 bytes
        const Bytes& b = P.strs[x.aux];
        return from_be(BytesView(b).subspan(b.size() > 32 ? b.size() - 32 : 0));
    }
    case Op::str: return number_of_bytes(e);
    case Op::var: return var(x.aux);
    case Op::param:
    case Op::member:
        return param_value(e);
    case Op::stor_var:
    case Op::stor_raw:
    case Op::field:
        return read(loc(e));
    case Op::index:
    case Op::length:
        if (param_path(e))
            return param_value(e);
        return read(loc(e));
    case Op::all: return number_of_bytes(e);
    case Op::selector: return Word{x.aux};
    case Op::sm_param:
        if (sm_.empty())
            throw Unsup{Unsupported::other};
        if (x.aux < sm_.back().def->words)
            return sm_.back().values[x.aux];
        return number_of_bytes(e);
    case Op::caller: return ctx_.caller;
    case Op::origin: return ctx_.origin;
    case Op::gas_price: return ctx_.gas_price;
    case Op::call_value: return ctx_.value;
    case Op::func_hash: return load_word(ctx_.calldata, 0) & (mask_of(32) << 224);
    case Op::calldata_size: return Word{ctx_.calldata.size()};
    case Op::return_data_size: return Word{ret_.size()};
    case Op::this_address: return s_.address();
    case Op::gas: return Word{static_cast<std::uint64_t>(fixed_gas)};
    case Op::chain_id: return s_.block().chain_id;
    case Op::msize: throw Unsup{Unsupported::msize};
    case Op::number: return s_.block().number;
    case Op::timestamp: return s_.block().timestamp;
    case Op::coinbase: return s_.block().coinbase;
    case Op::difficulty: return s_.block().prevrandao;
    case Op::gas_limit: return s_.block().gas_limit;
    case Op::base_fee: return s_.block().base_fee;
    case Op::blob_base_fee: return s_.block().blob_base_fee;
    case Op::call_success: return last_success_;
    case Op::create_address: return create_address_;
    case Op::neg: return Word{0} - eval(kid(e, 0));
    case Op::bit_not: return ~eval(kid(e, 0));
    case Op::not_: return eval(kid(e, 0)) == 0 ? Word{1} : Word{0};
    case Op::land:
    {
        const Word a = eval(kid(e, 0));
        return a == 0 ? a : eval(kid(e, 1));
    }
    case Op::lor:
    {
        const Word a = eval(kid(e, 0));
        return a != 0 ? a : eval(kid(e, 1));
    }
    case Op::to_bool: return eval(kid(e, 0)) != 0 ? Word{1} : Word{0};
    case Op::cast_uint: return eval(kid(e, 0)) & mask_of(x.aux);
    case Op::cast_int: return cast_int(eval(kid(e, 0)), x.aux);
    case Op::mask:
    {
        const Word size = eval(kid(e, 0));
        const Word off = eval(kid(e, 1));
        const Word v = eval(kid(e, 2));
        if (size > 256 || off > 256)
            throw Unsup{Unsupported::mask_range};
        const auto sz = static_cast<unsigned>(size);
        const auto of = static_cast<unsigned>(off);
        return of >= 256 ? Word{0} : v & (mask_of(sz) << of);
    }
    case Op::ceil32: return (eval(kid(e, 0)) + 31) & ~Word{31};
    case Op::floor32: return eval(kid(e, 0)) & ~Word{31};
    case Op::min:
    case Op::max:
    {
        Word r = eval(kid(e, 0));
        for (unsigned i = 1; i < x.n; ++i)
        {
            const Word v = eval(kid(e, i));
            r = x.op == Op::min ? std::min(r, v) : std::max(r, v);
        }
        return r;
    }
    case Op::byte:
    {
        const Word i = eval(kid(e, 0));
        const Word v = eval(kid(e, 1));
        return i >= 32 ? Word{0} : (v >> (248 - 8 * static_cast<unsigned>(i))) & 0xff;
    }
    case Op::clz:
    {
        const Word v = eval(kid(e, 0));
        return v == 0 ? Word{256} : Word{intx::clz(v)};
    }
    case Op::signextend:
    {
        const Word b = eval(kid(e, 0));
        return signextend(b, eval(kid(e, 1)));
    }
    case Op::shift:
    {
        // shift(x, n): x << n when n is positive as a signed number, x >> -n else
        const Word v = eval(kid(e, 0));
        const Word n = eval(kid(e, 1));
        return (n & sign_bit) == 0 ? v << n : v >> (Word{0} - n);
    }
    case Op::addmod:
    {
        const Word a = eval(kid(e, 0)), b = eval(kid(e, 1)), m = eval(kid(e, 2));
        return m == 0 ? Word{0} : intx::addmod(a, b, m);
    }
    case Op::mulmod:
    {
        const Word a = eval(kid(e, 0)), b = eval(kid(e, 1)), m = eval(kid(e, 2));
        return m == 0 ? Word{0} : intx::mulmod(a, b, m);
    }
    case Op::sha3:
    {
        Bytes b;
        data(std::span<const ExprId>(P.kids.data() + x.kids, x.n), b);
        return keccak256(b);
    }
    case Op::concat:
    case Op::bytes:
    case Op::mem_range:
    case Op::call_data:
    case Op::return_data:
    case Op::code_data:
    case Op::ext_code_copy:
        return number_of_bytes(e);
    case Op::balance: return s_.balance(to_address(eval(kid(e, 0))));
    case Op::ext_code_size: return s_.code_size(to_address(eval(kid(e, 0))));
    case Op::ext_code_hash: return s_.code_hash(to_address(eval(kid(e, 0))));
    case Op::block_hash: return s_.block_hash(eval(kid(e, 0)));
    case Op::blob_hash: return s_.blob_hash(eval(kid(e, 0)));
    case Op::safemath: return safemath(e);
    case Op::mem: return from_be(mem_read(eval(kid(e, 0)), Word{32}));
    case Op::cd: return load_word(ctx_.calldata, eval(kid(e, 0)));
    case Op::transient: return s_.tload(eval(kid(e, 0)));
    case Op::array:
    case Op::panic:
    case Op::ext_code:
    case Op::range:
    case Op::callee_sig:
    case Op::callee_mem:
        throw Unsup{Unsupported::other};
    default:
        return eval_binary(x, e);
    }
}

Word Run::eval_binary(const Expr& x, ExprId e)
{
    const Word a = eval(kid(e, 0));
    const Word b = eval(kid(e, 1));
    switch (x.op)
    {
    case Op::add:
    case Op::sadd: return a + b;
    case Op::sub: return a - b;
    case Op::mul:
    case Op::smul: return a * b;
    case Op::div: return b == 0 ? Word{0} : a / b;
    case Op::mod: return b == 0 ? Word{0} : a % b;
    case Op::sdiv: return b == 0 ? Word{0} : intx::sdivrem(a, b).quot;
    case Op::smod: return b == 0 ? Word{0} : intx::sdivrem(a, b).rem;
    case Op::pow: return intx::exp(a, b);
    case Op::shl: return a << b;
    case Op::shr: return a >> b;
    case Op::sar: return sar(a, b);
    case Op::bit_and: return a & b;
    case Op::bit_or: return a | b;
    case Op::bit_xor: return a ^ b;
    case Op::eq: return a == b ? Word{1} : Word{0};
    case Op::ne: return a != b ? Word{1} : Word{0};
    case Op::lt: return a < b ? Word{1} : Word{0};
    case Op::gt: return a > b ? Word{1} : Word{0};
    case Op::le: return a <= b ? Word{1} : Word{0};
    case Op::ge: return a >= b ? Word{1} : Word{0};
    case Op::slt: return slt(a, b) ? Word{1} : Word{0};
    case Op::sgt: return slt(b, a) ? Word{1} : Word{0};
    case Op::sle: return !slt(b, a) ? Word{1} : Word{0};
    case Op::sge: return !slt(a, b) ? Word{1} : Word{0};
    default: throw Unsup{Unsupported::other};
    }
}

// --- bytes --------------------------------------------------------------------------------

ExprId Run::resolve(ExprId e) const
{
    // errorMessage: the message the SafeMath function is called with
    const Expr& x = ex(e);
    if (x.op == Op::sm_param && !sm_.empty() && x.aux >= sm_.back().def->words)
    {
        const auto i = x.aux - sm_.back().def->words;
        if (i < sm_.back().messages.size())
            return sm_.back().messages[i];
    }
    return e;
}

bool Run::sized(ExprId e) const
{
    switch (ex(resolve(e)).op)
    {
    case Op::str:
    case Op::big:
    case Op::bytes:
    case Op::mem_range:
    case Op::call_data:
    case Op::return_data:
    case Op::code_data:
    case Op::ext_code_copy:
    case Op::concat:
    case Op::array:
    case Op::selector:
    case Op::panic:
    case Op::all:
        return true;
    default:
        return false;
    }
}

void Run::copy_out(BytesView src, const Word& at, std::size_t n, Bytes& out)
{
    // n bytes of src from at, zeroes past its end
    const std::size_t start = out.size();
    out.resize(start + n, 0);
    if (at < Word{src.size()})
    {
        const auto a = static_cast<std::size_t>(at);
        std::memcpy(out.data() + start, src.data() + a, std::min(n, src.size() - a));
    }
}

void Run::elem(ExprId e0, Bytes& out)
{
    step();
    const ExprId e = resolve(e0);
    const Expr& x = ex(e);
    switch (x.op)
    {
    case Op::str:
    case Op::big:
    {
        const Bytes& b = P.strs[x.aux];
        out.insert(out.end(), b.begin(), b.end());
        return;
    }
    case Op::selector: put_selector(out, x.aux); return;
    case Op::panic:
        put_selector(out, panic_selector);
        put_word(out, eval(kid(e, 0)));
        return;
    case Op::bytes:
    {
        const auto n = size_of(eval(kid(e, 0)), lim_.memory);
        const ExprId v = kid(e, 1);
        Bytes vb;
        if (sized(v))
            elem(v, vb);
        else
            put_word(vb, eval(v));
        put_last(out, vb, n);
        return;
    }
    case Op::mem_range:
    {
        const Bytes b = mem_read(eval(kid(e, 0)), eval(kid(e, 1)));
        out.insert(out.end(), b.begin(), b.end());
        return;
    }
    case Op::call_data:
    {
        const Word at = eval(kid(e, 0));
        copy_out(ctx_.calldata, at, size_of(eval(kid(e, 1)), lim_.memory), out);
        return;
    }
    case Op::return_data:
    {
        const Word at = eval(kid(e, 0));
        copy_out(ret_, at, size_of(eval(kid(e, 1)), lim_.memory), out);
        return;
    }
    case Op::code_data:
    {
        const Word at = eval(kid(e, 0));
        copy_out(s_.code(), at, size_of(eval(kid(e, 1)), lim_.memory), out);
        return;
    }
    case Op::ext_code_copy:
    {
        const Bytes code = s_.code_of(to_address(eval(kid(e, 0))));
        const Word at = eval(kid(e, 1));
        copy_out(code, at, size_of(eval(kid(e, 2)), lim_.memory), out);
        return;
    }
    case Op::concat:
    case Op::array:
        data(std::span<const ExprId>(&e, 1), out);
        return;
    case Op::all:
    {
        const ExprId base = kid(e, 0);
        if (param_path(base))
        {
            // p[all]: the p.length bytes after the length
            const Word p = param_value(base);
            const Word len = load_word(ctx_.calldata, p + 4);
            copy_out(ctx_.calldata, p + 36, size_of(len, lim_.memory), out);
            return;
        }
        // a bytes of the storage: its length's bytes, in its slot (short)
        // or from keccak(slot) (long)
        const Loc l = loc(base);
        if (l.type == none || P.types[l.type].kind != SType::bytes)
            throw Unsup{Unsupported::storage_path};
        const Word w = s_.sload(l.slot);
        if ((w & 1) == 0)
        {
            const auto len = static_cast<std::size_t>((w & 0xff) >> 1);
            if (len > 31)
                throw Unsup{Unsupported::bytes_encoding};
            const auto b = to_bytes(w);
            out.insert(out.end(), b.begin(), b.begin() + static_cast<std::ptrdiff_t>(len));
            return;
        }
        if ((w >> 1) < 32)
            throw Unsup{Unsupported::bytes_encoding};
        const auto len = size_of(w >> 1, lim_.memory);
        const auto slot = keccak256(to_bytes(l.slot));
        for (std::size_t i = 0; i * 32 < len; ++i)
        {
            const auto b = to_bytes(s_.sload(slot + Word{i}));
            out.insert(out.end(), b.begin(), b.begin() + static_cast<std::ptrdiff_t>(std::min<std::size_t>(32, len - i * 32)));
        }
        return;
    }
    default:
        put_word(out, eval(e));
        return;
    }
}

void Run::data(std::span<const ExprId> list, Bytes& out)
{
    // the elements one after the other - an Array(len=l, data=...) ABI-
    // encoded: its offset there, its length and its data (padded to a word)
    // after all of them (runtrace.evb's)
    Bytes heads;
    std::vector<std::size_t> offsets;
    std::vector<Bytes> tails;
    for (const ExprId e0 : list)
    {
        const ExprId e = resolve(e0);
        if (ex(e).op == Op::array && list.size() > 0)
        {
            offsets.push_back(heads.size());
            heads.resize(heads.size() + 32, 0);
            Bytes tail;
            put_word(tail, eval(kid(e, 0)));
            const Expr& x = ex(e);
            if (x.n > 1)
                data(std::span<const ExprId>(P.kids.data() + x.kids + 1, x.n - 1u), tail);
            tail.resize(32 + (tail.size() - 32 + 31) / 32 * 32, 0);
            tails.push_back(std::move(tail));
        }
        else if (ex(e).op == Op::concat)
        {
            const Expr& x = ex(e);
            data(std::span<const ExprId>(P.kids.data() + x.kids, x.n), heads);
        }
        else
            elem(e, heads);
    }
    std::size_t pos = heads.size();
    for (std::size_t i = 0; i < offsets.size(); ++i)
    {
        const auto w = to_bytes(Word{pos});
        std::memcpy(heads.data() + offsets[i], w.data(), 32);
        pos += tails[i].size();
    }
    out.insert(out.end(), heads.begin(), heads.end());
    for (const auto& t : tails)
        out.insert(out.end(), t.begin(), t.end());
}

Bytes Run::abi_data(std::span<const ExprId> list)
{
    // the data of a return, a revert, a constant: a string that is all of
    // it (after a 4-byte selector) is ABI-encoded
    Bytes out;
    std::size_t first = 0;
    if (!list.empty())
    {
        const Expr& x = ex(resolve(list[0]));
        if (x.op == Op::selector || (x.op == Op::bytes && ex(kid(resolve(list[0]), 0)).op == Op::num
                                        && P.nums[ex(kid(resolve(list[0]), 0)).aux] == 4))
            first = 1;
    }
    if (list.size() == first + 1 && ex(resolve(list[first])).op == Op::str)
    {
        if (first == 1)
            elem(list[0], out);
        put_abi_string(out, P.strs[ex(resolve(list[first])).aux]);
        return out;
    }
    data(list, out);
    return out;
}

Bytes Run::revert_data(const Stmt& s)
{
    if (s.list.empty())
        return {};
    if (s.aux == 1 || (s.list.size() == 1 && ex(resolve(s.list[0])).op == Op::str))
    {
        // revert with 'text': Error(string) of it
        Bytes out;
        put_selector(out, error_selector);
        put_abi_string(out, P.strs[ex(resolve(s.list[0])).aux]);
        return out;
    }
    return abi_data(s.list);
}

// --- memory ------------------------------------------------------------------------------------

Bytes Run::mem_read(const Word& at, const Word& n)
{
    if (n == 0)
        return {};
    if (at >= Word{1} << 32 || n >= Word{1} << 32 || at + n > Word{lim_.memory})
        throw Halt{End::exhausted("memory")};
    const auto a = static_cast<std::size_t>(at);
    const auto len = static_cast<std::size_t>(n);
    Bytes out(len, 0);
    if (a < mem_.size())
        std::memcpy(out.data(), mem_.data() + a, std::min(len, mem_.size() - a));
    return out;
}

void Run::mem_write(const Word& at, BytesView b)
{
    if (b.empty())
        return;
    if (at >= Word{1} << 32 || at + Word{b.size()} > Word{lim_.memory})
        throw Halt{End::exhausted("memory")};
    const auto a = static_cast<std::size_t>(at);
    if (mem_.size() < a + b.size())
        mem_.resize((a + b.size() + 31) / 32 * 32, 0);
    std::memcpy(mem_.data() + a, b.data(), b.size());
}

// --- the storage and the params -------------------------------------------------------------------

bool Run::storage_path(ExprId e) const
{
    for (;;)
    {
        const Expr& x = ex(e);
        switch (x.op)
        {
        case Op::stor_var:
        case Op::stor_raw:
            return true;
        case Op::index:
        case Op::length:
        case Op::field:
        case Op::all:
            e = kid(e, 0);
            continue;
        default:
            return false;
        }
    }
}

bool Run::param_path(ExprId e) const
{
    for (;;)
    {
        const Expr& x = ex(e);
        switch (x.op)
        {
        case Op::param:
            return true;
        case Op::index:
        case Op::length:
        case Op::member:
        case Op::all:
            e = kid(e, 0);
            continue;
        default:
            return false;
        }
    }
}

Loc Run::loc(ExprId e)
{
    step();
    const Expr& x = ex(e);
    switch (x.op)
    {
    case Op::stor_var:
    {
        const auto& d = P.storage[x.aux];
        return {d.slot, d.offset, value_width(P, d.type), d.type, false};
    }
    case Op::stor_raw:
        return {eval(kid(e, 0)), 0, 256, none, false};
    case Op::field:
    {
        // .field_N: from the bit N on - the slot N / 256 after
        const Loc l = loc(kid(e, 0));
        const unsigned bit = x.aux % 256;
        return {l.slot + Word{x.aux / 256}, bit, 256 - bit, none, false};
    }
    case Op::length:
    {
        const Loc l = loc(kid(e, 0));
        if (l.type == none)
            throw Unsup{Unsupported::storage_path};
        const auto k = P.types[l.type].kind;
        if (k == SType::array)
            return {l.slot, 0, 256, none, false};
        if (k == SType::bytes)
            return {l.slot, 0, 256, none, true};
        throw Unsup{Unsupported::storage_path};
    }
    case Op::index:
    {
        const Loc l = loc(kid(e, 0));
        if (l.type == none)
            throw Unsup{Unsupported::storage_path};
        const SType& t = P.types[l.type];
        const ExprId key = kid(e, 1);
        switch (t.kind)
        {
        case SType::mapping:
        {
            // keccak(key . slot) - Vyper's: slot . key; a key of bytes is
            // hashed as its bytes
            Bytes kb;
            if (sized(key))
                elem(key, kb);
            else
                put_word(kb, eval(key));
            Bytes in;
            if (P.vyper)
            {
                put_word(in, l.slot);
                in.insert(in.end(), kb.begin(), kb.end());
            }
            else
            {
                in = std::move(kb);
                put_word(in, l.slot);
            }
            return {keccak256(in), 0, value_width(P, t.elem), t.elem, false};
        }
        case SType::array:
        case SType::fixed:
        {
            const Word start = t.kind == SType::array ? keccak256(to_bytes(l.slot)) : l.slot;
            const Word i = eval(key);
            const unsigned w = elem_width(P, t.elem);
            if (w < 256)
            {
                // packed: 256 / w in a slot, from its lowest bits
                const unsigned per = 256 / w;
                return {start + i / per, w * static_cast<unsigned>(i % per), w, t.elem, false};
            }
            return {start + i * Word{stride_of(P, t.elem)}, 0, value_width(P, t.elem), t.elem, false};
        }
        case SType::bytes:
            return {keccak256(to_bytes(l.slot)) + eval(key), 0, 256, none, false};
        default:
            throw Unsup{Unsupported::storage_path};
        }
    }
    default:
        throw Unsup{Unsupported::storage_path};
    }
}

Word Run::read(const Loc& l)
{
    const Word w = s_.sload(l.slot);
    if (l.bytes_length)
    {
        // the length of a bytes: its slot halved - the low byte of a short
        // one (its lowest bit 0), all of a long one
        return (w & 1) == 0 ? (w & 0xff) >> 1 : w >> 1;
    }
    return (w >> l.bit) & mask_of(l.width);
}

void Run::write(const Loc& l, const Word& value, unsigned bits)
{
    if (l.bytes_length)
        throw Unsup{Unsupported::lvalue};
    if (l.bit == 0 && bits >= 256)
    {
        s_.sstore(l.slot, value);
        return;
    }
    const Word m = mask_of(bits) << l.bit;
    const Word old = s_.sload(l.slot);
    s_.sstore(l.slot, (old & ~m) | ((value << l.bit) & m));
}

const std::vector<NameTree>* Run::names_of_params()
{
    if (!names_asked_)
    {
        names_asked_ = true;
        const Function* fn = frames_.empty() ? nullptr : frames_.front().fn;
        if (fn != nullptr && in_.param_names_ && fn->kind == Function::regular)
            names_ = in_.param_names_(fn->selector);
    }
    return names_ ? &*names_ : nullptr;
}

std::pair<std::uint32_t, const PType*> Run::param_place(ExprId e)
{
    // the calldata offset of a static place of a param: the param, an
    // element of a static array, a member of a static tuple
    const Expr& x = ex(e);
    const Function* fn = frame().fn;
    switch (x.op)
    {
    case Op::param:
    {
        if (fn->kind == Function::internal || x.aux >= fn->params.size())
            throw Unsup{Unsupported::param_path};
        const Param& p = fn->params[x.aux];
        return {p.position, &p.type};
    }
    case Op::index:
    {
        const auto [pos, t] = param_place(kid(e, 0));
        if (!t->is_array || t->dynamic || t->count == 0 || t->components.empty())
            throw Unsup{Unsupported::param_path};
        const Word k = eval(kid(e, 1));
        if (k >= Word{t->count})
            throw Unsup{Unsupported::param_path};
        return {pos + 32 * static_cast<std::uint32_t>(k) * t->elem_words, &t->components[0]};
    }
    case Op::member:
    {
        // the names of the tuple's components: the signature database's
        const ExprId base = kid(e, 0);
        if (ex(base).op != Op::param)
            throw Unsup{Unsupported::member};
        const auto* names = names_of_params();
        const Param& p = fn->params[ex(base).aux];
        if (names == nullptr || ex(base).aux >= names->size() || p.type.dynamic)
            throw Unsup{Unsupported::member};
        const NameTree& tree = (*names)[ex(base).aux];
        if (tree.components.size() != p.type.components.size())
            throw Unsup{Unsupported::member};
        std::uint32_t pos = p.position;
        for (std::size_t i = 0; i < tree.components.size(); ++i)
        {
            if (tree.components[i].name == P.names[x.aux])
                return {pos, &p.type.components[i]};
            pos += 32 * p.type.components[i].words;
        }
        throw Unsup{Unsupported::member};
    }
    default:
        throw Unsup{Unsupported::param_path};
    }
}

Word Run::param_value(ExprId e)
{
    const Expr& x = ex(e);
    Frame& f = frame();
    if (x.op == Op::param && f.fn->kind == Function::internal)
    {
        if (x.aux >= f.args.size())
            throw Unsup{Unsupported::param_path};
        return f.args[x.aux];
    }
    switch (x.op)
    {
    case Op::length:
    {
        // p.length: the word of calldata at 4 + p
        const ExprId base = kid(e, 0);
        const auto [pos, t] = param_place(base);
        if (!t->has_length)
            throw Unsup{Unsupported::param_path};
        return load_word(ctx_.calldata, load_word(ctx_.calldata, Word{pos}) + 4);
    }
    case Op::index:
    {
        const ExprId base = kid(e, 0);
        const auto [pos, t] = param_place(base);
        if (t->is_array && t->dynamic)
        {
            // an element of a dynamic array of words: at p + 36 + 32 k
            if (t->elem_words != 1 || t->elem_dynamic)
                throw Unsup{Unsupported::param_path};
            const Word p = load_word(ctx_.calldata, Word{pos});
            return load_word(ctx_.calldata, p + 36 + 32 * eval(kid(e, 1)));
        }
        const auto [epos, et] = param_place(e);
        (void)et;
        return load_word(ctx_.calldata, Word{epos});
    }
    default:
    {
        const auto [pos, t] = param_place(e);
        (void)t;
        return load_word(ctx_.calldata, Word{pos});
    }
    }
}

// --- statements ---------------------------------------------------------------------------------------

void Run::assign(ExprId lhs, const Word& value)
{
    const Expr& x = ex(lhs);
    switch (x.op)
    {
    case Op::var:
    {
        Frame& f = frame();
        if (x.aux >= f.vars.size())
            throw Unsup{Unsupported::lvalue};
        f.vars[x.aux] = value;
        f.set[x.aux] = 1;
        return;
    }
    case Op::mem:
    {
        const auto b = to_bytes(value);
        mem_write(eval(kid(lhs, 0)), b);
        return;
    }
    case Op::transient:
        s_.tstore(eval(kid(lhs, 0)), value);
        return;
    case Op::cast_uint:
        // uint8(x.field_8) = v: its low bits only
        if (storage_path(kid(lhs, 0)))
        {
            const Loc l = loc(kid(lhs, 0));
            write(l, value, std::min<unsigned>(x.aux, 256));
            return;
        }
        throw Unsup{Unsupported::lvalue};
    default:
        if (storage_path(lhs) && x.op != Op::all)
        {
            const Loc l = loc(lhs);
            write(l, value, l.width);
            return;
        }
        throw Unsup{Unsupported::lvalue};
    }
}

void Run::assign_memory(const Stmt& s)
{
    const Expr& x = ex(s.a);
    const Word at = eval(kid(s.a, 0));
    const Word n = x.op == Op::mem ? Word{32} : eval(kid(s.a, 1));
    const auto len = size_of(n, lim_.memory);
    Bytes b;
    if (s.list.size() == 1 && !sized(s.list[0]))
    {
        // a number: its low n bytes
        put_low(b, eval(s.list[0]), len);
    }
    else
    {
        data(s.list, b);
        if (b.size() != len)
            throw Unsup{Unsupported::data_size};
    }
    mem_write(at, b);
}

void Run::call_stmt(const Stmt& s)
{
    Word target;
    Bytes input;
    const Expr& x = ex(s.a);
    if (x.op == Op::callee_sig)
    {
        target = eval(kid(s.a, 0));
        put_selector(input, x.aux);
    }
    else if (x.op == Op::callee_mem)
    {
        target = eval(kid(s.a, 0));
        elem(kid(s.a, 1), input);
        if (input.size() != 4)
            throw Unsup{Unsupported::other};
    }
    else
        target = eval(s.a);
    if (s.b != none)
    {
        // funct x: the low 4 bytes of x
        Bytes f;
        if (sized(s.b))
            elem(s.b, f);
        else
            put_word(f, eval(s.b));
        put_last(input, f, 4);
    }
    const Word value = s.c != none ? eval(s.c) : Word{0};
    if (s.has_args)
        data(s.list, input);
    auto r = s_.call(static_cast<CallKind>(s.aux), to_address(target), value, input);
    last_success_ = r.success ? 1 : 0;
    ret_ = std::move(r.output);
}

void Run::create_stmt(const Stmt& s)
{
    const Word value = s.a != none ? eval(s.a) : Word{0};
    const Word salt = s.b != none ? eval(s.b) : Word{0};
    Bytes code;
    data(s.list, code);
    auto r = s_.create(static_cast<CreateKind>(s.aux), value, code, salt);
    create_address_ = r.success ? r.address : Word{0};
    ret_ = std::move(r.output);
}

void Run::precompiled(const Stmt& s)
{
    Bytes input;
    data(s.list, input);
    auto r = s_.call(CallKind::staticcall, Word{s.aux}, 0, input);
    last_success_ = r.success ? 1 : 0;
    ret_ = std::move(r.output);
    // the variable: the first word it returns (zeroes past it)
    Frame& f = frame();
    const auto id = s.vars.at(0);
    f.vars.at(id) = load_word(ret_, 0);
    f.set.at(id) = 1;
}

void Run::internal_call(const Stmt& s)
{
    const Function& callee = P.functions[s.aux];
    std::vector<Word> args;
    for (const ExprId e : s.list)
        args.push_back(eval(e));
    if (args.size() != callee.params.size())
        throw Unsup{Unsupported::results};
    if (frames_.size() > lim_.internal_depth)
        throw Unsup{Unsupported::recursion};
    Frame f;
    f.fn = &callee;
    f.vars.assign(callee.vars.size(), 0);
    f.set.assign(callee.vars.size(), 0);
    f.args = std::move(args);
    frames_.push_back(std::move(f));
    const Flow flow = block(callee.body);
    frames_.pop_back();
    std::vector<Word> results;
    if (flow.kind == Ctl::leave)
        results = std::move(leave_);
    if (results.size() < s.vars.size())
        throw Unsup{Unsupported::results};
    Frame& caller = frame();
    for (std::size_t i = 0; i < s.vars.size(); ++i)
    {
        caller.vars.at(s.vars[i]) = results[i];
        caller.set.at(s.vars[i]) = 1;
    }
}

Word Run::safemath(ExprId e)
{
    const Expr& x = ex(e);
    const SafeMathDef& d = P.safemath[x.aux];
    SmFrame f;
    f.def = &d;
    for (unsigned i = 0; i < d.words && i < 2 && i < x.n; ++i)
        f.values[i] = eval(kid(e, i));
    if (x.n > d.words)
        f.messages = std::span<const ExprId>(P.kids.data() + x.kids + d.words, x.n - d.words);
    sm_.push_back(f);
    const Flow flow = block(d.body);
    sm_.pop_back();
    if (flow.kind != Ctl::leave || leave_.size() != 1)
        throw Unsup{Unsupported::results};
    return leave_[0];
}

Run::Flow Run::block(const std::vector<StmtId>& b)
{
    const Deeper d(*this);
    for (const StmtId id : b)
    {
        const Flow f = exec(id);
        if (f.kind != Ctl::next)
            return f;
    }
    return {};
}

Run::Flow Run::exec(StmtId id)
{
    step();
    const Stmt& s = P.stmts[id];
    switch (s.kind)
    {
    case St::assign:
    {
        const Op op = ex(s.a).op;
        if (op == Op::mem_range || (op == Op::mem && !s.list.empty()))
            assign_memory(s);
        else
            assign(s.a, eval(s.b));
        return {};
    }
    case St::add_assign: assign(s.a, eval(s.a) + eval(s.b)); return {};
    case St::sub_assign: assign(s.a, eval(s.a) - eval(s.b)); return {};
    case St::inc: assign(s.a, eval(s.a) + 1); return {};
    case St::dec: assign(s.a, eval(s.a) - 1); return {};
    case St::if_:
        if (s.a == none)
            throw Unsup{Unsupported::unparsed};
        return block(eval(s.a) != 0 ? s.body : s.orelse);
    case St::while_:
        for (;;)
        {
            if (eval(s.a) == 0)
                return {};
            const Flow f = block(s.body);
            if (f.kind == Ctl::next)
                continue;  // the end of its body: back to the condition
            if (f.kind == Ctl::continue_ && (f.label == 0 || f.label == s.aux))
                continue;
            if (f.kind == Ctl::break_)
                return {};
            return f;  // a continue of an outer loop, a leave
        }
    case St::continue_: return {Ctl::continue_, s.aux};
    case St::break_: return {Ctl::break_, 0};
    case St::require:
        if (eval(s.a) == 0)
            throw Halt{End::reverted({})};
        return {};
    case St::assert_:
        if (eval(s.a) == 0)
            throw Halt{End::invalid(Fault::invalid_instruction)};
        return {};
    case St::revert: throw Halt{End::reverted(revert_data(s))};
    case St::return_: throw Halt{End::returned(abi_data(s.list))};
    case St::revert_memory:
    case St::return_memory:
    {
        const Word from = eval(s.a);
        const Word n = s.aux == 1 ? eval(s.b) - from : eval(s.b);
        Bytes b = mem_read(from, n);
        throw Halt{s.kind == St::revert_memory ? End::reverted(std::move(b)) : End::returned(std::move(b))};
    }
    case St::stop: throw Halt{End::stop()};
    case St::invalid: throw Halt{End::invalid(Fault::invalid_instruction)};
    case St::selfdestruct:
        s_.selfdestruct(to_address(eval(s.a)));
        throw Halt{End::stop()};
    case St::log:
    {
        std::vector<Word> topics;
        for (const ExprId t : s.list2)
            topics.push_back(eval(t));
        Bytes b;
        data(s.list, b);
        s_.log(topics, b);
        return {};
    }
    case St::call: call_stmt(s); return {};
    case St::create: create_stmt(s); return {};
    case St::precompiled: precompiled(s); return {};
    case St::internal_call: internal_call(s); return {};
    case St::leave:
    {
        std::vector<Word> values;
        for (const ExprId e : s.list)
            values.push_back(eval(e));
        leave_ = std::move(values);
        return {Ctl::leave, 0};
    }
    case St::aborted: throw Unsup{s.aux == 1 ? Unsupported::unparsed : Unsupported::aborted};
    }
    throw Unsup{Unsupported::other};
}

End Run::call(const Function* fn)
{
    try
    {
        if (fn == nullptr)
            throw Unsup{Unsupported::no_function};
        if (!fn->payable && ctx_.value != 0)
        {
            // sent ether, it reverts with no data - or runs an invalid opcode
            return fn->value_invalid ? End::invalid(Fault::invalid_instruction) : End::reverted({});
        }
        Frame f;
        f.fn = fn;
        f.vars.assign(fn->vars.size(), 0);
        f.set.assign(fn->vars.size(), 0);
        frames_.push_back(std::move(f));
        if (fn->kind == Function::constant)
            return End::returned(abi_data(fn->data));
        block(fn->body);
        return End::stop();
    }
    catch (const Halt& h)
    {
        return h.end;
    }
    catch (const Unsup& u)
    {
        ++in_.unsupported_[static_cast<std::size_t>(u.why)];
        return End::unsupported(std::string(to_string(u.why)));
    }
}

// --- the interpreter ----------------------------------------------------------------------------------

Interpreter::Interpreter(const Program& program, InterpLimits limits)
  : program_(&program), limits_(limits)
{
    for (std::uint32_t i = 0; i < program.functions.size(); ++i)
    {
        const auto& f = program.functions[i];
        if (f.kind == Function::regular || f.kind == Function::constant)
            by_selector_.emplace_back(f.selector, i);
        else if (f.kind == Function::fallback && !fallback_)
            fallback_ = i;
    }
    std::ranges::sort(by_selector_);
}

std::optional<std::uint32_t> Interpreter::function_of(std::uint32_t selector) const
{
    const auto it = std::ranges::lower_bound(by_selector_, std::pair{selector, 0u});
    if (it != by_selector_.end() && it->first == selector)
        return it->second;
    return std::nullopt;
}

Effects Interpreter::run(Session& session)
{
    const Bytes& cd = session.context().calldata;
    std::optional<std::uint32_t> fn;
    if (cd.size() >= 4)
        fn = function_of(static_cast<std::uint32_t>(load_word(cd, 0) >> 224));
    if (!fn)
        fn = fallback_;
    Run run(*this, session);
    End end = run.call(fn ? &program_->functions[*fn] : nullptr);
    return session.finish(std::move(end));
}

Effects Interpreter::run(State& state, const CallContext& call)
{
    Session session(state, call);
    return run(session);
}
}  // namespace validate::text
