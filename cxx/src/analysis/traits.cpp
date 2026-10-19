// The function traits (traits.hpp; python function.py, contract.py's
// replace_names, utils/signatures.py's calldata_params; asm function.s,
// sigs.s): the params of a function (the signature database's, or inferred
// from the calldata it reads), the callvalue check out of its body,
// cleanup_masks, CALLDATALOAD(4 + 32k) -> Name(PARAM, k), read_only,
// const, getter.
#include "analysis/traits.hpp"

#include <algorithm>
#include <memory_resource>
#include <utility>
#include <vector>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/memo.hpp"
#include "core/smallvec.hpp"
#include "mem/memory.hpp"
#include "sigdb.hpp"

namespace pan::traits {

namespace {

// ---- helpers ----------------------------------------------------------------------

std::optional<i64> small_of(Value v) noexcept
{
    if (v.is_small())
        return v.small_val();
    return std::nullopt;
}

std::span<const Value> lines_of(Value t) noexcept { return t.is_list() ? t.args() : std::span<const Value>{}; }

// a per-job vector of values (the budget's memory)
using Values = std::pmr::vector<Value>;
Values values() { return Values(cx().budget.resource()); }

bool is_node_with_children(Value v) noexcept { return v.is_expr() || v.is_list(); }

// a line rebuilt with these operands: a pure op through the algebra (its
// normal form), any other as it is, its byte elements as wide as they were
// (python keep_widths); a line keeps its pc
Value rebuild(Value orig, std::span<const Value> args)
{
    if (orig.is_list())
        return mk_like(orig, args);
    const Op op = orig.op();
    if (alg::is_pure(op))
        return alg::apply(op, args);
    Value r = mk_like(orig, args);
    if (r != orig) {
        r = mem::keep_widths(orig, r);
        cx().pcs.inherit(r, orig);
    }
    return r;
}

// Every node equal to a key replaced by its value, top-down (a replaced
// node's operands aren't looked at), the rest rebuilt (rebuild). Memoized.
class Subst {
public:
    void add(Value from, Value to) { map_.put(from, to); }
    bool empty() const noexcept { return map_.empty(); }
    usize size() const noexcept { return map_.size(); }
    template <class F>
    void each(F&& f) const
    {
        map_.each([&](const Value& k, const Value& v) { f(k, v); });
    }

    Value operator()(Value v)
    {
        check_stack();
        if (!is_node_with_children(v))
            return v;
        if (const Value* r = map_.find(v))
            return *r;
        if (const Value* m = memo_.find(v))
            return *m;
        SmallVec<Value, 8> args;
        bool changed = false;
        for (const Value a : v.children()) {
            const Value na = (*this)(a);
            changed |= na != a;
            args.push_back(na);
        }
        const Value r = changed ? rebuild(v, args.span()) : v;
        memo_.put(v, r);
        return r;
    }

private:
    Memo<Value, Value> map_, memo_;
};

// The lines of a trace whose operand traces (IF's branches, WHILE's body...)
// are visited too, each distinct trace once: f(line).
template <class F>
void each_line(Value trace, F&& f)
{
    Values todo = values();
    todo.push_back(trace);
    MemoSet<Value> seen;
    while (!todo.empty()) {
        poll();
        const Value t = todo.back();
        todo.pop_back();
        if (!t.is_list() || !seen.add(t))
            continue;
        for (const Value l : t.args()) {
            f(l);
            if (l.is_expr())
                for (const Value a : l.args())
                    if (a.is_trace())
                        todo.push_back(a);
        }
    }
}

// Every distinct node under root (EXPR and LIST, root included), each once:
// f(node) -> whether to visit its operands.
template <class F>
void each_node(Value root, F&& f)
{
    Values todo = values();
    todo.push_back(root);
    MemoSet<Value> seen;
    while (!todo.empty()) {
        poll();
        const Value v = todo.back();
        todo.pop_back();
        if (!is_node_with_children(v) || !seen.add(v))
            continue;
        if (f(v))
            for (const Value c : v.children())
                todo.push_back(c);
    }
}

// CALLDATALOAD at a constant offset
std::optional<i64> cd_offset(Value v) noexcept
{
    if (v.is(Op::CALLDATALOAD, 1))
        return small_of(v[0]);
    return std::nullopt;
}

bool is_halting_failure(Value l) noexcept { return l.is(Op::REVERT, 1) ? l[0].is_none() : l.is(Op::INVALID); }

// python cleanup_masks' reverts: the branch only reverts with no data, or is invalid
bool reverts(Value branch) noexcept
{
    const auto ls = lines_of(branch);
    return ls.size() == 1 && is_halting_failure(ls[0]);
}

// ---- the types of the params --------------------------------------------------------

struct PType {
    AbiKind kind = AbiKind::Word;
    u16 bits = 256;
    bool dynamic = false;
    bool operator==(const PType&) const = default;
};

// python mask_to_type(size): the types of the masks it knows
std::optional<PType> mask_to_type(i64 size) noexcept
{
    switch (size) {
        case 1: return PType{AbiKind::Bool, 256, false};
        case 8:
        case 16:
        case 32:
        case 64:
        case 128:
        case 256: return PType{AbiKind::Uint, u16(size), false};
        case 160: return PType{AbiKind::Address, 256, false};
        default: return std::nullopt;
    }
}

// python mask_to_type(size, force=True): the smallest type it knows past
// size (its lookup's order: 1 8 16 32 64 128 160 256)
PType mask_to_type_forced(i64 size) noexcept
{
    if (const auto t = mask_to_type(size))
        return *t;
    for (const i64 s : {1, 8, 16, 32, 64, 128, 160, 256})
        if (s > size)
            return *mask_to_type(s);
    return PType{};  // (past 256: python's "big<n>", never a param's)
}

// python make_params' kind of a size: -2 a tuple, -1 an array, 1 a bool, a
// whole number of bytes its uintN (address for 160), else the next type
PType kind_of_size(i64 size) noexcept
{
    if (size == -2)
        return PType{AbiKind::Tuple, 256, true};
    if (size == -1)
        return PType{AbiKind::Array, 256, true};
    if (size == 1)
        return PType{AbiKind::Bool, 256, false};
    if (size > 0 && size < 256 && size % 8 == 0) {
        if (const auto t = mask_to_type(size))
            return *t;
        return PType{AbiKind::Uint, u16(size), false};
    }
    if (size == 256)
        return PType{};  // (nothing known: a word, printed uint256)
    return mask_to_type_forced(size);
}

// python validation's f: the type of the param cd is if x is the check's
// other side - cd as a valid value of a type
std::optional<PType> validation_type(Value x, Value cd)
{
    if (x.is(Op::MASK_SHL, 4) && x[3] == cd && x[2] == Value::small(0)) {
        const auto size = small_of(x[0]), off = small_of(x[1]);
        if (!size || !off)
            return std::nullopt;
        if (*off == 0 && *size % 8 == 0 && *size > 0 && *size <= 256) {
            if (const auto t = mask_to_type(*size))
                return *t;
            return PType{AbiKind::Uint, u16(*size), false};
        }
        if (*off + *size == 256 && *size % 8 == 0 && *size > 0)
            return PType{AbiKind::BytesN, u16(*size), false};
        return std::nullopt;
    }
    if (x.is(Op::BOOL, 1) && x[0] == cd)
        return PType{AbiKind::Bool, 256, false};
    if (x.is(Op::SIGNEXTEND, 2) && x[1] == cd)
        if (const auto b = small_of(x[0]); b && *b >= 0 && *b < 32)
            return PType{AbiKind::Int, u16(8 * (*b + 1)), false};
    return std::nullopt;
}

// ---- python make_params' inference ----------------------------------------------------

struct Inference {
    // per constant offset (not 0): the sizes of its uses (python's uses: a
    // mask's size when at bit 0; -1 none, -3 a size that isn't an int)
    std::pmr::vector<std::pair<i64, std::pmr::vector<i64>>> uses{cx().budget.resource()};
    // the offsets read inside the offset of another read (python pointers)
    std::pmr::vector<i64> pointers{cx().budget.resource()};
    bool unusual = false;  // an offset past what a param's can be

    std::pmr::vector<i64>& sizes_of(i64 off)
    {
        for (auto& [o, s] : uses)
            if (o == off)
                return s;
        uses.emplace_back(off, std::pmr::vector<i64>(cx().budget.resource()));
        return uses.back().second;
    }

    void note(Value off, i64 size)
    {
        if (const auto c = small_of(off)) {
            if (*c == 0)
                return;  // (the selector's word)
            if (*c < 0 || *c > i64(0xffffffff)) {
                unusual = true;
                return;
            }
            sizes_of(*c).push_back(size);
            return;
        }
        if (off.is_big()) {
            unusual = true;
            return;
        }
        // an element of an array, or its length: what it's read relatively
        // to is a pointer to it (every constant read inside the offset)
        each_node(off, [&](Value v) {
            if (const auto p = cd_offset(v); p && std::find(pointers.begin(), pointers.end(), *p) == pointers.end())
                pointers.push_back(*p);
            return true;
        });
    }

    // python reads(): a mask of a read is that read (its size when at bit 0),
    // a bare read none; the mask's fields and the read's offset walked too
    void collect(Value root)
    {
        each_node(root, [&](Value v) {
            if (v.is(Op::MASK_SHL, 4) && v[3].is(Op::CALLDATALOAD, 1)) {
                i64 size = -1;
                if (v[1] == Value::small(0)) {
                    const auto s = small_of(v[0]);
                    size = s ? *s : -3;
                }
                note(v[3][0], size);
                // the fields and the offset, not the read itself (no bare use)
                for (const Value c : {v[0], v[1], v[2], v[3][0]})
                    if (is_node_with_children(c))
                        collect_from(c);
                return false;
            }
            if (v.is(Op::CALLDATALOAD, 1)) {
                note(v[0], -1);
                return true;
            }
            return true;
        });
    }

private:
    void collect_from(Value v)
    {
        check_stack();
        collect(v);
    }
};

// A failing condition that holds unless a param is a valid value of a type,
// as the algebra writes `x != cleaned(x)`: the bits above the type set
// (MASK_SHL(256 - n, n, 0 or -n, x): x isn't an n-bit number), or the bits
// below a left-aligned type's (MASK_SHL(n, 0, 0, x): x isn't a bytesN of
// 256 - n bits). The param and its clean form (what equals it past the
// check), the type.
struct MaskCheck {
    Value cd, clean;
    PType type;
};
std::optional<MaskCheck> mask_check(Value cond)
{
    if (!cond.is(Op::MASK_SHL, 4) || !cd_offset(cond[3]))
        return std::nullopt;
    const auto size = small_of(cond[0]), off = small_of(cond[1]), shl = small_of(cond[2]);
    if (!size || !off || !shl)
        return std::nullopt;
    const Value cd = cond[3];
    if (*size + *off == 256 && *off > 0 && *off < 256 && (*shl == 0 || *shl == -*off)) {
        PType t = mask_to_type_forced(*off);
        if (*off % 8 == 0) {
            if (const auto m = mask_to_type(*off))
                t = *m;
            else
                t = PType{AbiKind::Uint, u16(*off), false};
        }
        return MaskCheck{cd, alg::mask(*off, 0, 0, cd), t};
    }
    if (*off == 0 && *shl == 0 && *size > 0 && *size < 256 && (256 - *size) % 8 == 0)
        return MaskCheck{cd, alg::mask(256 - *size, *size, 0, cd), PType{AbiKind::BytesN, u16(256 - *size), false}};
    return std::nullopt;
}

// python validation(idx) for every offset at once: the types each param is
// checked to be a valid value of (`require x == address(x)`, and the mask
// forms of the checks that fail unless it is)
void validations(Value root, std::pmr::vector<std::pair<i64, std::pmr::vector<PType>>>& found)
{
    auto add = [&](i64 off, PType t) {
        for (auto& [o, ts] : found)
            if (o == off) {
                if (std::find(ts.begin(), ts.end(), t) == ts.end())
                    ts.push_back(t);
                return;
            }
        found.emplace_back(off, std::pmr::vector<PType>(cx().budget.resource()));
        found.back().second.push_back(t);
    };
    each_node(root, [&](Value v) {
        if (v.is(Op::EQ, 2))
            for (int side = 0; side < 2; ++side) {
                const Value cd = v[side], other = v[1 - side];
                const auto off = cd_offset(cd);
                if (!off || other == cd)
                    continue;
                if (const auto t = validation_type(other, cd))
                    add(*off, *t);
            }
        if (v.is(Op::IF, 3) && reverts(v[1]))
            if (const auto m = mask_check(v[0]))
                add(*cd_offset(m->cd), m->type);
        return true;
    });
}

// the offsets read (CALLDATALOAD of a constant) that are an operand of
// anything but BOOL, IF or ISZERO (python's bool test: every parent of
// ('cd', idx) one of those)
void non_bool_parents(Value root, std::pmr::vector<i64>& out)
{
    each_node(root, [&](Value v) {
        const bool truth = v.is(Op::BOOL) || v.is(Op::IF) || v.is(Op::ISZERO);
        for (const Value c : v.children())
            if (const auto off = cd_offset(c); off && !truth)
                if (std::find(out.begin(), out.end(), *off) == out.end())
                    out.push_back(*off);
        return true;
    });
}

// python make_params when the abi has no inputs
std::vector<ParamInfo> infer_params(std::span<const Value> roots)
{
    Inference inf;
    for (const Value r : roots)
        inf.collect(r);
    if (inf.unusual)
        return {};
    for (const auto& [off, sizes] : inf.uses)
        if ((off - 4) % 32 != 0)
            return {};  // python: "unusual cd (not aligned)"
    std::pmr::vector<std::pair<i64, std::pmr::vector<PType>>> valid(cx().budget.resource());
    validations(roots[0], valid);
    for (usize i = 1; i < roots.size(); ++i)
        validations(roots[i], valid);
    auto validated = [&](i64 off) -> std::optional<PType> {
        for (const auto& [o, ts] : valid)
            if (o == off && ts.size() == 1)
                return ts[0];
        return std::nullopt;
    };
    auto pointer = [&](i64 off) { return std::find(inf.pointers.begin(), inf.pointers.end(), off) != inf.pointers.end(); };

    struct Found {
        i64 off;
        PType type;
    };
    std::pmr::vector<Found> found(cx().budget.resource());
    for (const auto& [off, sizes] : inf.uses) {
        PType t;
        if (pointer(off)) {
            t = kind_of_size(-1);
        } else if (const auto v = validated(off)) {
            t = *v;
        } else if (!sizes.empty() && std::all_of(sizes.begin(), sizes.end(), [](i64 s) { return s > 0 && s <= 256; })) {
            // masked everywhere, as the compilers did before validating the
            // params (by masks of known sizes)
            t = kind_of_size(*std::min_element(sizes.begin(), sizes.end()));
        } else {
            t = kind_of_size(256);
        }
        found.push_back(Found{off, t});
    }
    for (const i64 p : inf.pointers)
        if (p > 0 && (p - 4) % 32 == 0 && std::none_of(found.begin(), found.end(), [&](const Found& f) { return f.off == p; }))
            found.push_back(Found{p, kind_of_size(-1)});
    // a bool: used only as a truth value
    std::pmr::vector<i64> non_bool(cx().budget.resource());
    for (const Value r : roots)
        non_bool_parents(r, non_bool);
    for (Found& f : found)
        if (std::find(non_bool.begin(), non_bool.end(), f.off) == non_bool.end())
            f.type = kind_of_size(1);
    std::sort(found.begin(), found.end(), [](const Found& a, const Found& b) { return a.off < b.off; });
    std::vector<ParamInfo> out;
    out.reserve(found.size());
    for (const Found& f : found) {
        ParamInfo p;
        p.calldata_offset = u32(f.off);
        p.kind = f.type.kind;
        p.bits = f.type.bits;
        p.dynamic = f.type.dynamic;
        out.push_back(p);
    }
    return out;
}

// ---- the params of the abi ----------------------------------------------------------------

constexpr u64 kMaxHeadWords = u64{1} << 16;  // python MAX_HEAD_WORDS

// the head words a static type takes (capped past kMaxHeadWords)
u64 head_count(const sigdb::Type& t)
{
    check_stack();
    if (t.dynamic())
        return 1;
    switch (t.kind()) {
        case sigdb::TypeKind::static_array: {
            const u64 per = head_count(t.element());
            const u64 n = t.length();
            if (per && n > (kMaxHeadWords + 1) / per)
                return kMaxHeadWords + 1;
            return n * per;
        }
        case sigdb::TypeKind::tuple: {
            u64 sum = 0;
            for (const sigdb::Field f : t.fields()) {
                sum += head_count(f.type());
                if (sum > kMaxHeadWords)
                    return kMaxHeadWords + 1;
            }
            return sum;
        }
        default:
            return 1;
    }
}

PType word_type(const sigdb::Type& t) noexcept
{
    switch (t.kind()) {
        case sigdb::TypeKind::uintN: return PType{AbiKind::Uint, u16(t.bits()), false};
        case sigdb::TypeKind::intN: return PType{AbiKind::Int, u16(t.bits()), false};
        case sigdb::TypeKind::bytesN: return PType{AbiKind::BytesN, u16(8 * t.size()), false};
        case sigdb::TypeKind::address: return PType{AbiKind::Address, 256, false};
        case sigdb::TypeKind::boolean: return PType{AbiKind::Bool, 256, false};
        case sigdb::TypeKind::string: return PType{AbiKind::String, 256, true};
        case sigdb::TypeKind::bytes: return PType{AbiKind::Bytes, 256, true};
        case sigdb::TypeKind::function: return PType{AbiKind::BytesN, 192, false};
        case sigdb::TypeKind::fixed: return PType{AbiKind::Int, u16(t.bits()), false};
        case sigdb::TypeKind::ufixed: return PType{AbiKind::Uint, u16(t.bits()), false};
        case sigdb::TypeKind::array: return PType{AbiKind::Array, 256, true};
        case sigdb::TypeKind::static_array: return PType{AbiKind::Array, 256, t.dynamic()};
        case sigdb::TypeKind::tuple: return PType{AbiKind::Tuple, 256, t.dynamic()};
        case sigdb::TypeKind::storage:
        case sigdb::TypeKind::memory:
        case sigdb::TypeKind::calldata:
        case sigdb::TypeKind::named: return PType{AbiKind::Unknown, 256, t.dynamic()};
    }
    return PType{};
}

// python head_words(type): a dynamic type's offset, a static tuple's or
// array's words, any other one word
void head_words(const sigdb::Type& t, u32 index, std::vector<ParamInfo>& out)
{
    check_stack();
    auto one = [&](PType pt) {
        ParamInfo p;
        p.kind = pt.kind;
        p.bits = pt.bits;
        p.dynamic = pt.dynamic;
        p.abi_index = index;
        out.push_back(p);
    };
    if (t.dynamic()) {
        one(word_type(t));
        return;
    }
    switch (t.kind()) {
        case sigdb::TypeKind::static_array: {
            if (head_count(t) > kMaxHeadWords) {
                one(word_type(t));  // (more words than calldata can hold: as one)
                return;
            }
            const u64 n = t.length();
            for (u64 i = 0; i < n; ++i)
                head_words(t.element(), index, out);
            return;
        }
        case sigdb::TypeKind::tuple:
            for (const sigdb::Field f : t.fields())
                head_words(f.type(), index, out);
            return;
        default:
            one(word_type(t));
            return;
    }
}

// ---- the callvalue check (python analyse's payable) -------------------------------------

// a test of a nonzero callvalue
bool is_value_test(Value d)
{
    const Value cv = Value::leaf(Op::CALLVALUE);
    const Value zero = Value::small(0);
    d = alg::truth(d);
    if (d == cv)
        return true;
    if ((d.is(Op::GT, 2) && d[0] == cv && d[1] == zero) || (d.is(Op::LT, 2) && d[0] == zero && d[1] == cv))
        return true;
    if (d.is(Op::ISZERO, 1)) {
        const Value e = d[0];
        if (e.is(Op::EQ, 2) && ((e[0] == cv && e[1] == zero) || (e[0] == zero && e[1] == cv)))
            return true;
        if ((e.is(Op::LE, 2) && e[0] == cv && e[1] == zero) || (e.is(Op::GE, 2) && e[0] == zero && e[1] == cv))
            return true;
    }
    return false;
}

// python disjuncts: the conditions cond holds where one of them does
void disjuncts(Value cond, SmallVec<Value, 4>& out)
{
    check_stack();
    if (cond.is(Op::OR) && cond.size() > 1) {
        for (const Value e : cond.args())
            disjuncts(alg::truth(e), out);
        return;
    }
    out.push_back(cond);
}

// The callvalue check of a trace's first line past its SETMEM / SETVAR
// lines (python: its last line at the latest): the trace without it, the
// halting line it fails with (fails); nullopt when there's none.
std::optional<Value> without_value_check(Value body, Value& fails_line)
{
    const auto ls = lines_of(body);
    if (ls.empty())
        return std::nullopt;
    usize k = 0;
    while (k + 1 < ls.size() && (ls[k].is(Op::SETMEM) || ls[k].is(Op::SETVAR)))
        ++k;
    const Value first = ls[k];
    if (!first.is(Op::IF, 3))
        return std::nullopt;
    const Value cond = alg::truth(first[0]);
    Value fails = first[1], rest = first[2];
    SmallVec<Value, 4> ds;
    SmallVec<Value, 4> others;
    if (is_value_test(alg::iszero(cond))) {
        // `if not callvalue: rest else: fail`
        std::swap(fails, rest);
    } else {
        disjuncts(cond, ds);
        for (const Value d : ds)
            if (!is_value_test(d))
                others.push_back(d);
        if (others.size() == ds.size())
            return std::nullopt;
    }
    const auto fl = lines_of(fails);
    if (fl.empty() || !is_halting_failure(fl[0]))
        return std::nullopt;
    fails_line = fl[0];
    // the lines before it, then what runs when there's no value, then the
    // lines after it (an IF's continuation)
    Values out = values();
    out.assign(ls.begin(), ls.begin() + isize(k));
    if (!others.empty()) {
        // (Vyper 0.3.10: `if call.value or calldata.size < 36: revert` - the
        // size check stays)
        const Value other = others.size() == 1 ? others[0] : alg::bor(others.span());
        const Value l = mk(Op::IF, other, fails, rest);
        cx().pcs.inherit(l, first);
        out.push_back(l);
    } else {
        for (const Value l : lines_of(rest))
            out.push_back(l);
    }
    out.insert(out.end(), ls.begin() + isize(k) + 1, ls.end());
    return mk_trace(std::span<const Value>(out.data(), out.size()));
}

// the line a failing branch halts with, when it halts at its first line
std::optional<Value> first_failure(Value branch)
{
    const auto ls = lines_of(branch);
    if (ls.empty() || !is_halting_failure(ls[0]))
        return std::nullopt;
    return ls[0];
}

// two halting lines end a run the same way (an INVALID's pc aside)
bool same_failure(Value a, Value b) noexcept
{
    if (a == b)
        return true;
    return a.is(Op::INVALID, 2) && b.is(Op::INVALID, 2) && a[0] == b[0];
}

// The dispatcher's callvalue check (solc's when no function is payable):
// the first check of the entry's lines (past SETMEMs / SETVARs), removed
// when every check after it fails the same way (the trace machine checks
// the value after the entry's lines: the order of the failures can't
// matter then). The entry lines without it; nullopt when there's none.
std::optional<Value> entry_without_value_check(Value entry, Value& fails_line)
{
    const auto ls = lines_of(entry);
    usize k = 0;
    while (k < ls.size() && (ls[k].is(Op::SETMEM) || ls[k].is(Op::SETVAR)))
        ++k;
    if (k == ls.size() || !ls[k].is(Op::IF, 3))
        return std::nullopt;
    const Value check = ls[k];
    std::optional<Value> fail;
    if (lines_of(check[1]).empty() && is_value_test(alg::iszero(check[0])))
        fail = first_failure(check[2]);  // IF(no value, {}, fail)
    else if (lines_of(check[2]).empty() && is_value_test(check[0]))
        fail = first_failure(check[1]);  // IF(value, fail, {})
    if (!fail)
        return std::nullopt;
    for (usize i = k + 1; i < ls.size(); ++i) {
        const Value l = ls[i];
        if (l.is(Op::SETMEM) || l.is(Op::SETVAR))
            continue;
        if (!l.is(Op::IF, 3))
            return std::nullopt;
        std::optional<Value> f;
        if (lines_of(l[1]).empty())
            f = first_failure(l[2]);
        else if (lines_of(l[2]).empty())
            f = first_failure(l[1]);
        if (!f || !same_failure(*f, *fail))
            return std::nullopt;
    }
    fails_line = *fail;
    Values out = values();
    out.assign(ls.begin(), ls.end());
    out.erase(out.begin() + isize(k));
    return mk_trace(std::span<const Value>(out.data(), out.size()));
}

// ---- python cleanup_masks -------------------------------------------------------------

// x is cd as a valid value of a type (python clean_form)
bool clean_form(Value x, Value cd) noexcept
{
    if (x.is(Op::MASK_SHL, 4))
        return x[3] == cd && x[2] == Value::small(0);
    if (x.is(Op::BOOL, 1))
        return x[0] == cd;
    if (x.is(Op::SIGNEXTEND, 2))
        return x[1] == cd;
    return false;
}

struct Known {
    Value x, cd;  // past the check, x (a clean form of cd) is cd
};

// python validated(cond): where cond holds, the branch reverts unless cd == x
std::optional<Known> validated(Value cond)
{
    if (cond.is(Op::ISZERO, 1) && cond[0].is(Op::EQ, 2)) {
        const Value e = cond[0];
        for (int side = 0; side < 2; ++side) {
            const Value cd = e[side], x = e[1 - side];
            if (cd_offset(cd) && clean_form(x, cd))
                return Known{x, cd};
        }
    }
    // the bits above the type are 0 (python: a mask at shl 0; a right shift
    // of them to 0 is as true), or those below a left-aligned one's
    if (const auto m = mask_check(cond))
        return Known{m->clean, m->cd};
    return std::nullopt;
}

class CleanupMasks {
public:
    // The lines of t, what's known put in (python rem): past an IF one branch
    // of which only fails unless a param is clean, its clean form is the
    // param in the other branch - and in the lines after the IF (only that
    // branch goes on to them).
    Value trace(Value t, const std::vector<Known>& known)
    {
        check_stack();
        const auto ls = lines_of(t);
        SmallVec<Value, 32> out;
        bool changed = false;
        std::vector<Known> cur = known;
        for (const Value l : ls) {
            poll();
            Subst& si = subst_for(cur);
            Value nl = l;
            if (l.is(Op::IF, 3)) {
                const Value cond = si(l[0]);
                Value t1 = l[1], t2 = l[2];
                std::optional<Known> v;
                bool in_true = false;
                if (reverts(t1)) {
                    v = validated(l[0]);
                } else if (reverts(t2) && l[0].is(Op::EQ, 2)) {
                    for (int side = 0; side < 2 && !v; ++side)
                        if (cd_offset(l[0][side]) && clean_form(l[0][1 - side], l[0][side]))
                            v = Known{l[0][1 - side], l[0][side]};
                    in_true = v.has_value();
                }
                if (v) {
                    std::vector<Known> k2 = cur;
                    k2.push_back(*v);
                    t1 = trace(t1, in_true ? k2 : cur);
                    t2 = trace(t2, in_true ? cur : k2);
                    cur = std::move(k2);
                } else {
                    t1 = trace(t1, cur);
                    t2 = trace(t2, cur);
                }
                const Value ops[] = {cond, t1, t2};
                nl = mk_like(l, ops);
            } else if (l.is(Op::WHILE, 4)) {
                const Value body = trace(l[1], cur);
                const Value ops[] = {si(l[0]), body, l[2], si(l[3])};
                nl = mk_like(l, ops);
            } else {
                nl = si(l);
            }
            if (nl != l)
                cx().pcs.inherit(nl, l);
            changed |= nl != l;
            out.push_back(nl);
        }
        return changed ? mk_trace(out.span()) : t;
    }

private:
    // a Subst per set of knowns (few: a param's check each)
    Subst& subst_for(const std::vector<Known>& known)
    {
        for (auto& [k, s] : substs_)
            if (k.size() == known.size() &&
                std::equal(k.begin(), k.end(), known.begin(), [](const Known& a, const Known& b) { return a.x == b.x && a.cd == b.cd; }))
                return *s;
        substs_.emplace_back(known, std::make_unique<Subst>());
        Subst& s = *substs_.back().second;
        for (const Known& k : known)
            s.add(k.x, k.cd);
        return s;
    }
    std::vector<std::pair<std::vector<Known>, std::unique_ptr<Subst>>> substs_;
};

// ---- the traits -------------------------------------------------------------------------

// a line that changes the state, or does something that stays (a log - or
// may: a recursive internal function): python's read_only list
bool state_line(Value l) noexcept
{
    switch (l.op()) {
        case Op::STORE:
        case Op::SET:
        case Op::TSTORE:
        case Op::SELFDESTRUCT:
        case Op::CALL:
        case Op::DELEGATECALL:
        case Op::CALLCODE:
        case Op::CREATE:
        case Op::CREATE2:
        case Op::LOG0:
        case Op::LOG1:
        case Op::LOG2:
        case Op::LOG3:
        case Op::LOG4:
        case Op::INTERNAL:
            return true;
        default:
            return false;
    }
}

bool read_only(Value trace)
{
    if (!(trace.flags() & F_WRITES))
        return true;
    bool ro = true;
    each_line(trace, [&](Value l) { ro = ro && !state_line(l); });
    return ro;
}

// the RETURN lines (python find_returns, with multiplicity): 0, 1 or 2 (more)
u32 count_returns(Value trace, Memo<Value, u32>& memo)
{
    check_stack();
    if (!trace.is_list())
        return 0;
    if (const u32* c = memo.find(trace))
        return *c;
    u32 n = 0;
    for (const Value l : trace.args()) {
        if (n >= 2)
            break;
        if (l.is(Op::RETURN)) {
            ++n;
            continue;
        }
        if (l.is_expr())
            for (const Value a : l.args())
                if (a.is_trace())
                    n += count_returns(a, memo);
    }
    n = std::min<u32>(n, 2);
    memo.put(trace, n);
    return n;
}

// python varies: exp reads something that isn't a constant of the contract
// (where it is: ADDRESS, CODESIZE) - the calldata, the state, the
// environment; a variable's value is set in the trace (and checked there)
bool reads_varying(Value v, Memo<Value, u8>& memo)
{
    check_stack();
    if (v.is_leaf())
        return !(v.is(Op::ADDRESS) || v.is(Op::CODESIZE));
    if (v.is_name())
        return v.is_name(NameKind::PARAM);
    if (!is_node_with_children(v))
        return false;
    if (const u8* m = memo.find(v))
        return *m == 2;
    bool r = false;
    switch (v.op()) {
        case Op::CALLDATALOAD:
        case Op::CALLDATA_BYTES:
        case Op::STORAGE:
        case Op::LENGTH:
        case Op::SBYTES:
        case Op::ST:
        case Op::SALL:
        case Op::TLOAD:
        case Op::BALANCE:
        case Op::EXTCODESIZE:
        case Op::EXTCODEHASH:
        case Op::EXTCODE_BYTES:
        case Op::BLOCKHASH:
        case Op::BLOBHASH:
        case Op::RETURNDATA_BYTES:
        case Op::PRECOMPILED:
        case Op::STATICCALL:
        case Op::CALL:
        case Op::CALLCODE:
        case Op::DELEGATECALL:
        case Op::CREATE:
        case Op::CREATE2:
        case Op::UNDEFINED:
            r = true;
            break;
        case Op::ASM:
            r = false;  // (--verbose's: no semantics)
            break;
        default:
            for (const Value c : v.children())
                if (reads_varying(c, memo)) {
                    r = true;
                    break;
                }
            break;
    }
    memo.put(v, r ? 2 : 1);
    return r;
}

// python word(): a word of data (SIZED(32, v)) as its value
Value word(Value d) noexcept
{
    if (d.is(Op::SIZED, 2) && d[0] == Value::small(32))
        return d[1];
    return d;
}

// kitties' l2: the small slot n of SHA3(key, n) or SHA3(n)
std::optional<i64> small_sha3_slot(Value x) noexcept
{
    if (!x.is(Op::SHA3))
        return std::nullopt;
    auto int_of = [](Value e) -> std::optional<i64> {
        e = word(e);
        if (const auto n = small_of(e); n && *n >= 0 && *n < 1000)
            return n;
        return std::nullopt;
    };
    if (x.size() == 2)
        return int_of(x[1]);
    if (x.size() == 1) {
        const Value e = x[0];
        if (e.is(Op::DATA, 2))
            return int_of(e[1]);
        return int_of(e);
    }
    return std::nullopt;
}

// python find_f(e, l2): the first (pre-order) small slot in e
std::optional<i64> find_small_slot(Value e)
{
    check_stack();
    if (const auto n = small_sha3_slot(e))
        return n;
    for (const Value c : e.children())
        if (const auto n = find_small_slot(c))
            return n;
    return std::nullopt;
}

std::optional<Getter> getter_of_return(Value ret)
{
    if (!ret.is(Op::RETURN, 1))
        return std::nullopt;
    const Value v = word(ret[0]);
    if (v.is(Op::BOOL, 1) && v[0].is(Op::STORAGE, 3))
        return Getter{Getter::Kind::Read, v[0], v, 0};
    if (v.is(Op::MASK_SHL, 4) && v[3].is(Op::STORAGE, 3))
        return Getter{Getter::Kind::Read, v[3], v, 0};
    // (a read moved left: the algebra's 2^k * x)
    if (v.is(Op::MUL, 2) && v[1].is(Op::STORAGE, 3) && v[0].is_int()) {
        const EvmInt k(v[0]);
        if (k.sign() > 0 && (k & (k - EvmInt(Value::small(1)))).is_zero())
            return Getter{Getter::Kind::Read, v[1], v, 0};
    }
    if (v.is(Op::STORAGE, 3))
        return Getter{Getter::Kind::Read, v, v, 0};
    if (v.is(Op::DATA) && v.size() > 0) {
        // a struct: all its words storage of one place
        const Value t0 = word(v[0]);
        if (t0.is(Op::STORAGE, 3) && t0[0] == Value::small(256) && t0[1] == Value::small(0)) {
            const Value loc = t0[2];
            bool all = true;
            for (u32 i = 1; i < v.size() && all; ++i) {
                const Value e = word(v[i]);
                all = e.is(Op::STORAGE, 3) && e[0] == Value::small(256) && e[1] == Value::small(0) &&
                      e[2].is(Op::ADD, 2) && e[2][1] == loc;
            }
            if (all)
                return Getter{Getter::Kind::Struct, t0, v, 0};
        }
        // kitties getKitten
        std::optional<i64> loc;
        for (const Value t : v.args()) {
            const auto l = find_small_slot(word(t));
            if (!l || *l == 0 || (loc && *loc != *l))
                return std::nullopt;
            loc = l;
        }
        if (loc)
            return Getter{Getter::Kind::Kitties, NIL, v, u64(*loc)};
    }
    return std::nullopt;
}

// the first RETURN line of a trace (pre-order), NIL when none
Value first_return(Value trace)
{
    check_stack();
    for (const Value l : lines_of(trace)) {
        if (l.is(Op::RETURN))
            return l;
        if (l.is_expr())
            for (const Value a : l.args())
                if (a.is_trace())
                    if (const Value r = first_return(a); !r.nil())
                        return r;
    }
    return NIL;
}

// ---- CALLDATALOAD(4 + 32k) -> Name(PARAM, k) ---------------------------------------------

Value rename_params(Value v, Subst& s) { return s(v); }

}  // namespace

// ---- the public functions -------------------------------------------------------------------

std::vector<ParamInfo> abi_params(const sigdb::Entry& entry)
{
    std::vector<ParamInfo> out;
    u32 index = 0;
    for (const sigdb::Field f : entry.params()) {
        head_words(f.type(), index, out);
        ++index;
    }
    u32 loc = 4;
    for (ParamInfo& p : out) {
        p.calldata_offset = loc;
        loc += 32;
    }
    return out;
}

void analyse_function(FunctionInfo& fn, const ContractShared& shared, const Options& opts)
{
    if (fn.kind == FunctionInfo::Kind::Internal || !fn.trace.is_trace())
        return;
    // the signature database's entry (python fetch_sig: only a verified one)
    std::optional<sigdb::Entry> entry;
    if (fn.kind == FunctionInfo::Kind::Selector && shared.db)
        if (auto e = shared.db->function(fn.selector); e && e->trust() == sigdb::Trust::verified)
            entry = e;
    fn.name_known = entry.has_value();

    Value body = fn.trace;
    Value entry_lines = fn.entry.entry_lines;

    // the params: the abi's words, or what the calldata's uses say (once:
    // analysed again, its reads are its params' names already)
    if (opts.params && fn.params.empty()) {
        if (entry) {
            fn.params = abi_params(*entry);
        } else {
            SmallVec<Value, 2> roots;
            roots.push_back(body);
            if (entry_lines.is_trace())
                roots.push_back(entry_lines);
            fn.params = infer_params(roots.span());
        }
    }

    // a param as it is once it's checked
    if (opts.cleanup_masks) {
        CleanupMasks cm;
        body = cm.trace(body, {});
    }

    // payable: the callvalue check of the dispatcher's (solc's when no
    // function is payable), or of the body's start, out of the trace
    if (opts.payable && !fn.entry.nonpayable) {
        Value fails;
        bool done = false;
        if (entry_lines.is_trace())
            if (const auto e = entry_without_value_check(entry_lines, fails)) {
                entry_lines = *e;
                done = true;
                // a body that fails the same way at once (past its SETMEMs)
                // whatever it's sent: payable as python has it (its
                // simplifier merged the check's branches), the check gone
                const auto ls = lines_of(body);
                usize k = 0;
                while (k < ls.size() && (ls[k].is(Op::SETMEM) || ls[k].is(Op::SETVAR)))
                    ++k;
                if (!(k < ls.size() && is_halting_failure(ls[k]) && same_failure(ls[k], fails))) {
                    fn.entry.nonpayable = true;
                    fn.entry.value_fails = fails;
                }
            }
        if (!done)
            if (const auto b = without_value_check(body, fails)) {
                body = *b;
                fn.entry.nonpayable = true;
                fn.entry.value_fails = fails;
            }
    }
    fn.payable = !fn.entry.nonpayable;

    // read_only, const, getter (python analyse)
    fn.read_only = read_only(body);
    Memo<Value, u32> rmemo;
    const u32 nreturns = count_returns(body, rmemo);
    fn.is_const = false;
    fn.getter = false;
    if (fn.read_only && nreturns == 1) {
        Memo<Value, u8> vmemo;
        const bool reverts_on_value = fn.entry.nonpayable && fn.entry.value_fails.is(Op::REVERT, 1) &&
                                      fn.entry.value_fails[0].is_none();
        fn.is_const = reverts_on_value && !reads_varying(body, vmemo);
        if (!fn.is_const)
            fn.getter = getter_of_return(first_return(body)).has_value();
    }

    // CALLDATALOAD(4 + 32k) -> Name(PARAM, k) (python replace_names)
    if (opts.params && !fn.params.empty()) {
        Subst s;
        for (u32 k = 0; k < fn.params.size(); ++k)
            s.add(mk(Op::CALLDATALOAD, mk_int(i64(fn.params[k].calldata_offset))), Value::name(NameKind::PARAM, k));
        body = rename_params(body, s);
        if (entry_lines.is_trace())
            entry_lines = rename_params(entry_lines, s);
    }
    fn.trace = body;
    fn.entry.entry_lines = entry_lines;
}

void analyse_stage(std::span<const FunctionInfo> in, std::vector<FunctionInfo>& out, const ContractShared& shared,
                   const Options& opts)
{
    out.assign(in.begin(), in.end());
    for (FunctionInfo& f : out) {
        if (f.problem || !f.trace.is_trace())
            continue;
        try {
            analyse_function(f, shared, opts);
        } catch (const Error&) {
            f.trace = Value();
            f.problem = 0;
        }
    }
}

void returns_of(Value trace, std::vector<Value>& out)
{
    check_stack();
    for (const Value l : lines_of(trace)) {
        poll();
        if (l.is(Op::RETURN)) {
            out.push_back(l);
            continue;
        }
        if (l.is_expr())
            for (const Value a : l.args())
                if (a.is_trace())
                    returns_of(a, out);
    }
}

std::optional<Getter> getter_of(const FunctionInfo& fn)
{
    if (!fn.getter || !fn.trace.is_trace())
        return std::nullopt;
    return getter_of_return(first_return(fn.trace));
}

Value const_of(const FunctionInfo& fn)
{
    if (!fn.is_const || !fn.trace.is_trace())
        return NIL;
    const Value r = first_return(fn.trace);
    return r.is(Op::RETURN, 1) ? r[0] : NIL;
}

}  // namespace pan::traits
