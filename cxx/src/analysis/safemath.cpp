// SafeMath (safemath.hpp; python safemath.py; asm safemath.s): the checked
// arithmetic of the asts as calls of the contract's SafeMath functions.
//
// Python's algorithm on the IR: in each block of lines (a trace, an IF's
// branch, a WHILE's body), a run of checks (as_check) followed - past lines
// that can't fail and change nothing the checks read (SETVAR SETMEM STORE
// SET LOGn) - by a line that uses the result of the arithmetic they check
// (match_check over its candidates) is rewritten: the checks out, the result
// SAFEMATH(n, a, b...) in that line and the next ones until one changes
// what it reads (lot 7's affects). An IF one branch of which only fails is
// read as the check and the other branch's lines after it (python's folder
// flattens them so). Each site's checks are abstracted over the params a, b
// (and verified: the conditions put back together equal the originals on
// random values); the sites with the same operation and checks are one
// function of the table, its messages parameters where the sites' differ.
#include "analysis/safemath.hpp"

#include <algorithm>
#include <utility>
#include <vector>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/evmint.hpp"
#include "core/memo.hpp"
#include "core/smallvec.hpp"
#include "simplify/effects.hpp"

namespace pan::safemath {

namespace {

using Table = SafeMathTable;
using Arith = Table::Arith;
using FailKind = Table::Fail;

constexpr u32 ERROR_SELECTOR = 0x08c379a0;  // Error(string)
constexpr u32 PANIC_SELECTOR = 0x4e487b71;  // Panic(uint256)
constexpr u32 PANIC_OVERFLOW = 0x11;
constexpr u32 PANIC_DIVISION = 0x12;

Value param(u32 k) { return Value::name(NameKind::SAFEMATH_PARAM, k); }

std::optional<i64> small_of(Value v) noexcept
{
    if (v.is_small())
        return v.small_val();
    return std::nullopt;
}

std::span<const Value> lines_of(Value t) noexcept { return t.is_list() ? t.args() : std::span<const Value>{}; }

bool empty_trace(Value t) noexcept { return t.is_list() && t.size() == 0; }

// ---- how a check fails (python failure) ----------------------------------------------

struct Failure {
    FailKind kind = FailKind::Revert;
    u32 panic = 0;
    u32 reason = 0;  // Invalid: the INVALID's reason
    Value line;      // the halting line
    Value data;      // a REVERT's data (None: none); NIL for an INVALID
};

// a word element of a DATA (SIZED(32, n) or n): its value, when a small int
std::optional<i64> word_int(Value e) noexcept
{
    if (e.is(Op::SIZED, 2) && e[0] == Value::small(32))
        e = e[1];
    return small_of(e);
}

// python data_bytes: the bytes of a constant element of a DATA
bool data_bytes(Value e, std::vector<u8>& out)
{
    if (e.is_bytes()) {
        const auto b = e.bytes();
        out.insert(out.end(), b.begin(), b.end());
        return true;
    }
    i64 n = 32;
    Value v = e;
    if (e.is(Op::SIZED, 2)) {
        const auto s = small_of(e[0]);
        if (!s || *s < 0 || *s > 32)
            return false;
        n = *s;
        v = e[1];
        if (v.is_bytes()) {
            if (i64(v.size()) != n)
                return false;
            const auto b = v.bytes();
            out.insert(out.end(), b.begin(), b.end());
            return true;
        }
    }
    if (!v.is_int())
        return false;
    const EvmInt x(v);
    if (x.sign() < 0)
        return false;
    if (n < 32 && x >= (EvmInt(Value::small(1)) << u64(8 * n)))
        return false;
    if (n == 32 && x >= (EvmInt(Value::small(1)) << 256))
        return false;
    u8 w[32];
    x.to_be32(w);
    out.insert(out.end(), w + 32 - n, w + 32);
    return true;
}

// python pretty_text's test: printable ASCII (\n \r \t too), a letter or a digit
bool is_text(std::span<const u8> b) noexcept
{
    if (b.empty())
        return false;
    bool alnum = false;
    for (const u8 c : b) {
        if (!((c >= 0x20 && c < 0x7f) || c == '\n' || c == '\r' || c == '\t'))
            return false;
        alnum |= (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    }
    return alnum;
}

// the selector word of a DATA's first element: SIZED(4, sel)
std::optional<u32> selector_of(Value e) noexcept
{
    if (!e.is(Op::SIZED, 2) || e[0] != Value::small(4))
        return std::nullopt;
    const auto s = small_of(e[1]);
    if (!s || *s < 0 || *s > i64(0xffffffff))
        return std::nullopt;
    return u32(*s);
}

// python failure() of one halting line
std::optional<Failure> failure_of_line(Value l)
{
    if (l.is(Op::INVALID)) {
        Failure f;
        f.kind = FailKind::Invalid;
        f.line = l;
        f.reason = l.size() > 0 && l[0].is_small() ? u32(l[0].small_val()) : 0;
        return f;
    }
    if (!l.is(Op::REVERT, 1))
        return std::nullopt;
    const Value d = l[0];
    Failure f;
    f.line = l;
    f.data = d;
    if (d.is_none() || (d.is(Op::DATA) && d.size() == 0)) {
        f.kind = FailKind::Revert;
        return f;
    }
    if (!d.is(Op::DATA) || d.size() < 2)
        return std::nullopt;
    const auto sel = selector_of(d[0]);
    if (!sel)
        return std::nullopt;
    if (*sel == PANIC_SELECTOR && d.size() == 2) {
        const auto code = word_int(d[1]);
        if (!code || *code < 0 || *code > i64(0xffffffff))
            return std::nullopt;
        f.kind = FailKind::Panic;
        f.panic = u32(*code);
        return f;
    }
    if (*sel == ERROR_SELECTOR && d.size() >= 3 && word_int(d[1]) == 32) {
        // the string: its length, then its bytes - what follows them in the
        // last word (memory the compiler didn't zero) isn't part of it
        const auto len = word_int(d[2]);
        if (!len || *len <= 0 || *len > i64(1) << 20)
            return std::nullopt;
        std::vector<u8> b;
        for (u32 k = 3; k < d.size() && i64(b.size()) < *len; ++k)
            if (!data_bytes(d[k], b))
                return std::nullopt;
        if (i64(b.size()) < *len || !is_text(std::span<const u8>(b.data(), usize(*len))))
            return std::nullopt;
        f.kind = FailKind::Error;
        return f;
    }
    return std::nullopt;
}

// python failure(body): a branch that only fails
std::optional<Failure> failure_of(Value branch)
{
    const auto ls = lines_of(branch);
    if (ls.size() != 1)
        return std::nullopt;
    return failure_of_line(ls[0]);
}

// ---- the checks of an ast -------------------------------------------------------------

struct Check {
    Value cond;  // fails where it's nonzero
    Failure fail;
};

// a line that fails where its condition holds, all it does then (python
// is_check, and the folded forms: REQUIRE, ASSERT, IF(c, [], [F]))
std::optional<Check> as_check(Value l)
{
    if (l.is(Op::IF, 3)) {
        if (empty_trace(l[2]))
            if (const auto f = failure_of(l[1]))
                return Check{l[0], *f};
        if (empty_trace(l[1]))
            if (const auto f = failure_of(l[2]))
                return Check{alg::iszero(l[0]), *f};
        return std::nullopt;
    }
    if (l.is(Op::REQUIRE)) {
        const Value data = l.size() > 1 ? l[1] : Value::none();
        const auto f = failure_of_line(mk(Op::REVERT, data));
        if (!f)
            return std::nullopt;
        return Check{alg::iszero(l[0]), *f};
    }
    if (l.is(Op::ASSERT, 1)) {
        Failure f;
        f.kind = FailKind::Invalid;
        f.reason = u32(InvalidReason::ASSERT_FAIL);
        f.line = mk(Op::INVALID, Value::small(i64(InvalidReason::ASSERT_FAIL)), Value::small(0));
        return Check{alg::iszero(l[0]), f};
    }
    return std::nullopt;
}

// ---- python match_check ---------------------------------------------------------------

struct Match {
    Arith op = Arith::Add;
    Value a, b;  // b NIL for inc / dec
    bool operator==(const Match&) const = default;
};

Value sum_of(std::span<const Value> terms)
{
    if (terms.empty())
        return Value::small(0);
    if (terms.size() == 1)
        return terms[0];
    return alg::add(terms);
}

Value product_of(std::span<const Value> terms)
{
    if (terms.size() == 1)
        return terms[0];
    return alg::mul(terms);
}

// what a term of a sum subtracts, if it's subtracted (python _negated)
std::optional<Value> negated(Value t)
{
    if (t.is_int()) {
        const EvmInt x(t);
        if (x.sign() < 0)
            return (-x).value();
        return std::nullopt;
    }
    if (t.is(Op::MUL) && t.size() >= 2 && t[0].is_int()) {
        const EvmInt k(t[0]);
        if (k.sign() >= 0)
            return std::nullopt;
        if (k == -1)
            return t.size() == 2 ? t[1] : product_of(t.args().subspan(1));
        SmallVec<Value, 4> f;
        f.push_back((-k).value());
        for (u32 i = 1; i < t.size(); ++i)
            f.push_back(t[i]);
        return alg::mul(f.span());
    }
    return std::nullopt;
}

bool is_cmp(Value c, Op op, Value x, Value y) noexcept { return c.is(op, 2) && c[0] == x && c[1] == y; }

// what cond tests to be 0 (python zero_test)
Value zero_test(Value cond) noexcept
{
    const Value zero = Value::small(0);
    if (cond.is(Op::ISZERO, 1))
        return cond[0];
    if ((cond.is(Op::EQ, 2) || cond.is(Op::LE, 2)) && cond[1] == zero)
        return cond[0];
    if (cond.is(Op::EQ, 2) && cond[0] == zero)
        return cond[1];
    return NIL;
}

// ~b as the algebra may write it (python _complement)
SmallVec<Value, 3> complements(Value b)
{
    SmallVec<Value, 3> r;
    r.push_back(alg::bnot(b));
    const Value nb = alg::add(Value::small(-1), alg::neg(b));
    if (nb != r[0])
        r.push_back(nb);
    return r;
}

bool fails_overflow(const Failure& f) noexcept { return f.kind == FailKind::Panic && f.panic == PANIC_OVERFLOW; }

std::optional<Match> match_check(Value cond, const Failure& fail, Value res)
{
    const Value zero = Value::small(0), minus1 = Value::small(-1);
    if (res.is(Op::ADD) && res.size() >= 2) {
        const auto terms = res.args();
        SmallVec<Value, 4> neg, pos;
        for (const Value t : terms) {
            if (const auto n = negated(t))
                neg.push_back(*n);
            else
                pos.push_back(t);
        }
        if (!neg.empty()) {
            const Value a = sum_of(pos.span()), b = sum_of(neg.span());
            // a - b: b compared with a (OpenZeppelin's require(b <= a)), or
            // a - b with a (ds-math's require((z = x - y) <= x))
            if (is_cmp(cond, Op::GT, b, a) || is_cmp(cond, Op::LT, a, b) || is_cmp(cond, Op::GT, res, a) ||
                is_cmp(cond, Op::LT, a, res))
                return Match{Arith::Sub, a, b};
            // solidity's a - 1 since 0.8: a isn't 0
            if (b == Value::small(1) && fails_overflow(fail) &&
                (cond == alg::iszero(a) || is_cmp(cond, Op::EQ, a, zero) || is_cmp(cond, Op::EQ, zero, a)))
                return Match{Arith::Dec, a, NIL};
            return std::nullopt;
        }
        for (usize i = 0; i < terms.size(); ++i) {
            const Value a = terms[i];
            SmallVec<Value, 4> others;
            for (usize k = 0; k < terms.size(); ++k)
                if (k != i)
                    others.push_back(terms[k]);
            const Value b = sum_of(others.span());
            // a + b: the sum compared with a (require(c >= a))
            if (is_cmp(cond, Op::LT, res, a) || is_cmp(cond, Op::LE, res, a) || is_cmp(cond, Op::GT, a, res) ||
                is_cmp(cond, Op::GE, a, res))
                return Match{Arith::Add, a, b};
            // a compared with ~b, the most b can be added to
            for (const Value nb : complements(b))
                if (is_cmp(cond, Op::GT, a, nb) || is_cmp(cond, Op::LT, nb, a))
                    return Match{Arith::Add, a, b};
            // solidity's a + 1 since 0.8: a isn't the largest word
            if (b == Value::small(1) && fails_overflow(fail)) {
                const Value max = alg::bnot(zero);
                if (is_cmp(cond, Op::EQ, a, minus1) || is_cmp(cond, Op::EQ, minus1, a) || is_cmp(cond, Op::EQ, a, max) ||
                    is_cmp(cond, Op::EQ, max, a))
                    return Match{Arith::Inc, a, NIL};
            }
        }
        return std::nullopt;
    }
    if (res.is(Op::MUL) && res.size() >= 2) {
        // a * b: divided by a, it's b (where a isn't 0)
        const auto terms = res.args();
        for (usize i = 0; i < terms.size(); ++i) {
            const Value a = terms[i];
            SmallVec<Value, 4> others;
            for (usize k = 0; k < terms.size(); ++k)
                if (k != i)
                    others.push_back(terms[k]);
            const Value b = product_of(others.span());
            const Value q = alg::div(res, a);
            for (const Value ne : {alg::iszero(alg::cmp(Op::EQ, q, b)), alg::iszero(alg::cmp(Op::EQ, b, q))}) {
                if (cond == ne || cond == alg::band(a, ne) || cond == alg::band(ne, a))
                    return Match{Arith::Mul, a, b};
                if (cond.is(Op::AND, 2) && ((cond[0] == a && cond[1] == ne) || (cond[0] == ne && cond[1] == a)))
                    return Match{Arith::Mul, a, b};
            }
            // b compared with the most a can be multiplied by, where a isn't 0
            for (const Value most : {alg::div(minus1, a), alg::div(alg::bnot(zero), a)})
                for (const Value gt : {alg::cmp(Op::GT, b, most), alg::cmp(Op::LT, most, b)}) {
                    if (cond == alg::band(a, gt) || cond == alg::band(gt, a))
                        return Match{Arith::Mul, a, b};
                    if (cond.is(Op::AND, 2) && ((cond[0] == a && cond[1] == gt) || (cond[0] == gt && cond[1] == a)))
                        return Match{Arith::Mul, a, b};
                }
        }
        return std::nullopt;
    }
    if ((res.is(Op::DIV, 2) || res.is(Op::MOD, 2))) {
        // a / b: b isn't 0
        if (zero_test(cond) == res[1])
            return Match{res.is(Op::DIV) ? Arith::Div : Arith::Mod, res[0], res[1]};
        return std::nullopt;
    }
    return std::nullopt;
}

// ---- the abstraction over a, b ---------------------------------------------------------

// what fns[n] returns, over its params (python RESULTS)
Value result_of(Arith op)
{
    const Value a = param(0), b = param(1);
    switch (op) {
        case Arith::Add: return alg::add(a, b);
        case Arith::Sub: return alg::sub(a, b);
        case Arith::Mul: return alg::mul(a, b);
        case Arith::Div: return alg::div(a, b);
        case Arith::Mod: return alg::mod(a, b);
        case Arith::Inc: return alg::add(Value::small(1), a);
        case Arith::Dec: return alg::add(Value::small(-1), a);
    }
    return NIL;
}

u32 params_of(Arith op) noexcept { return op == Arith::Inc || op == Arith::Dec ? 1 : 2; }

// python abstract: the condition as the function's - res its result, a and b its params
class Abstract {
public:
    Abstract(Value res, const Match& m) : res_(res), m_(m), result_(result_of(m.op)) {}
    Value operator()(Value v)
    {
        const Value r = sub(v);
        return alg::normalize(r);
    }

private:
    Value sub(Value v)
    {
        check_stack();
        if (v == res_)
            return result_;
        if (v == m_.a)
            return param(0);
        if (!m_.b.nil() && v == m_.b)
            return param(1);
        if (!v.is_expr())
            return v;
        if (const Value* r = memo_.find(v))
            return *r;
        SmallVec<Value, 8> args;
        bool changed = false;
        for (const Value a : v.args()) {
            const Value na = sub(a);
            changed |= na != a;
            args.push_back(na);
        }
        const Value r = changed ? mk_like(v, args.span()) : v;
        memo_.put(v, r);
        return r;
    }
    Value res_;
    Match m_;
    Value result_;
    Memo<Value, Value> memo_;
};

// the params put back: a function's expression at a site
class Concrete {
public:
    Concrete(Value a, Value b) : a_(a), b_(b) {}
    Value operator()(Value v) { return alg::normalize(sub(v)); }

private:
    Value sub(Value v)
    {
        check_stack();
        if (v == param(0))
            return a_;
        if (v == param(1))
            return b_.nil() ? v : b_;
        if (!v.is_expr())
            return v;
        SmallVec<Value, 8> args;
        bool changed = false;
        for (const Value x : v.args()) {
            const Value nx = sub(x);
            changed |= nx != x;
            args.push_back(nx);
        }
        return changed ? mk_like(v, args.span()) : v;
    }
    Value a_, b_;
};

// v reads nothing but the params and constants: pure operations of them
bool only_params(Value v)
{
    check_stack();
    if (v.is_int() || v.is_bool() || v.is_none())
        return true;
    if (v.is_name())
        return v.is_name(NameKind::SAFEMATH_PARAM) && v.name_id() < 2;
    if (!v.is_expr() || !alg::is_pure(v.op()))
        return false;
    for (const Value a : v.args())
        if (!only_params(a))
            return false;
    return true;
}

// x and y have the same value (on random values of what they read): the
// abstraction's insurance
bool same_value(Value x, Value y)
{
    if (x == y)
        return true;
    for (const u64 seed : {0x5afe0001ull, 0x5afe0002ull, 0x5afe0003ull, 0x5afe0004ull}) {
        alg::RandomEnv env(seed);
        alg::Evaluator ev(env);
        const auto a = ev.try_eval(x), b = ev.try_eval(y);
        if (!a || !b || *a != *b)
            return false;
    }
    return true;
}

// whether exp divides by d somewhere (python divides)
bool divides(Value d, Value exp)
{
    check_stack();
    if ((exp.is(Op::DIV, 2) || exp.is(Op::MOD, 2)) && exp[1] == d)
        return true;
    for (const Value c : exp.children())
        if (divides(d, c))
            return true;
    return false;
}

// ---- the sites -------------------------------------------------------------------------

struct KeyCheck {
    Value cond;  // abstract
    FailKind kind = FailKind::Revert;
    u32 panic = 0, reason = 0;
    bool operator==(const KeyCheck&) const = default;
};

struct Site {
    Arith op = Arith::Add;
    std::vector<KeyCheck> key;
    std::vector<Failure> fails;
    Value a, b;
};

// The rewrite of the asts (python block / inside / _convert / _call / _uses).
class Rewriter {
public:
    std::vector<Site> sites;

    Value ast(Value trace) { return block(trace); }

private:
    // python's folder flattening of an IF one branch of which only fails: the
    // check, then the other branch's lines
    void flatten_into(std::vector<Value>& out, Value trace)
    {
        check_stack();
        for (const Value l : lines_of(trace)) {
            if (l.is(Op::IF, 3) && !empty_trace(l[1]) && !empty_trace(l[2])) {
                const bool t_fails = failure_of(l[1]).has_value(), f_fails = failure_of(l[2]).has_value();
                if (t_fails != f_fails) {
                    const Value none = mk_trace({});
                    const Value c = t_fails ? mk(Op::IF, l[0], l[1], none) : mk(Op::IF, l[0], none, l[2]);
                    cx().pcs.inherit(c, l);
                    out.push_back(c);
                    flatten_into(out, t_fails ? l[2] : l[1]);
                    continue;
                }
            }
            out.push_back(l);
        }
    }

    Value block(Value trace)
    {
        check_stack();
        if (!trace.is_list())
            return trace;
        std::vector<Value> lines;
        flatten_into(lines, trace);
        std::vector<Value> out;
        bool changed = false;
        usize i = 0;
        while (i < lines.size()) {
            poll();
            if (as_check(lines[i]))
                if (auto rest = convert(lines, i)) {
                    lines.resize(i);
                    lines.insert(lines.end(), rest->begin(), rest->end());
                    changed = true;
                    continue;
                }
            const Value nl = inside(lines[i]);
            changed |= nl != lines[i];
            out.push_back(nl);
            ++i;
        }
        if (!changed)
            return trace;
        return mk_trace(std::span<const Value>(out.data(), out.size()));
    }

    // python inside: the checked arithmetic of a line's branches
    Value inside(Value l)
    {
        if (l.is(Op::IF, 3) || l.is(Op::MERGED_IF, 3)) {
            const Value t = block(l[1]), f = block(l[2]);
            if (t == l[1] && f == l[2])
                return l;
            const Value ops[] = {l[0], t, f};
            const Value r = mk_like(l, ops);
            cx().pcs.inherit(r, l);
            return r;
        }
        if (l.is(Op::WHILE, 4)) {
            const Value body = block(l[1]);
            if (body == l[1])
                return l;
            const Value ops[] = {l[0], body, l[2], l[3]};
            const Value r = mk_like(l, ops);
            cx().pcs.inherit(r, l);
            return r;
        }
        return l;
    }

    // what a line evaluates at once (python _convert's now): an if's
    // condition, not a loop's (run again, the checks aren't)
    static Value now_of(Value l) noexcept
    {
        if (l.is(Op::IF, 3) || l.is(Op::MERGED_IF, 3) || l.is(Op::REQUIRE) || l.is(Op::ASSERT, 1))
            return l[0];
        if (l.is(Op::WHILE) || l.is(Op::LOOP_PATH))
            return NIL;
        return l;
    }

    // what can't fail nor change what a check reads unless it says so
    static bool transparent(Value l) noexcept
    {
        switch (l.op()) {
            case Op::SETVAR:
            case Op::SETMEM:
            case Op::SET:
            case Op::STORE:
            case Op::LOG0:
            case Op::LOG1:
            case Op::LOG2:
            case Op::LOG3:
            case Op::LOG4:
                return !contains_safemath(l);
            default:
                return false;
        }
    }

    static bool contains_safemath(Value v)
    {
        check_stack();
        if (v.is(Op::SAFEMATH))
            return true;
        for (const Value c : v.children())
            if (c.is_node() && contains_safemath(c))
                return true;
        return false;
    }

    // python candidates: the results of arithmetic in exp, the outer ones
    // first (each once) - but a * b / a, which only a check of a * b computes
    static void candidates(Value exp, std::vector<Value>& out)
    {
        check_stack();
        if (!exp.is_expr() && !exp.is_list())
            return;
        const bool arith = exp.is(Op::ADD) || exp.is(Op::MUL) || exp.is(Op::DIV, 2) || exp.is(Op::MOD, 2);
        const bool mul_div = exp.is(Op::DIV, 2) && exp[0].is(Op::MUL) &&
                             std::find(exp[0].args().begin(), exp[0].args().end(), exp[1]) != exp[0].args().end();
        if (arith && !mul_div && std::find(out.begin(), out.end(), exp) == out.end())
            out.push_back(exp);
        for (const Value c : exp.children())
            if (c.is_expr() || c.is_list())
                candidates(c, out);
    }

    // python _of: the operation all the checks are of, if res is its result
    static std::optional<Match> of(const std::vector<Check>& checks, Value res)
    {
        const Check& last = checks.back();
        const auto m = match_check(last.cond, last.fail, res);
        if (!m)
            return std::nullopt;
        for (usize k = 0; k + 1 < checks.size(); ++k) {
            const Check& c = checks[k];
            // of it as well, followed only by the compiler's checks
            bool later_compiler = true;
            for (usize j = k + 1; j < checks.size(); ++j)
                later_compiler &= checks[j].fail.kind == FailKind::Invalid || checks[j].fail.kind == FailKind::Panic;
            if (later_compiler && match_check(c.cond, c.fail, res) == m)
                continue;
            // the compiler's check of a division a later one makes by a param
            const Value d = zero_test(c.cond);
            const bool div_fail = c.fail.kind == FailKind::Invalid ||
                                  (c.fail.kind == FailKind::Panic && c.fail.panic == PANIC_DIVISION);
            if (!d.nil() && div_fail) {
                Abstract ab(res, *m);
                const Value ad = ab(d);
                if (ad == param(0) || ad == param(1)) {
                    bool found = false;
                    for (usize j = k + 1; j < checks.size() && !found; ++j) {
                        Abstract abj(res, *m);
                        found = divides(ad, abj(checks[j].cond));
                    }
                    if (found)
                        continue;
                }
            }
            return std::nullopt;
        }
        return m;
    }

    // python _convert: the lines from i on, the checks there made a call
    std::optional<std::vector<Value>> convert(const std::vector<Value>& lines, usize i)
    {
        usize end = i;
        while (end < lines.size() && as_check(lines[end]))
            ++end;
        // (the most checks first: a library's, then the compiler's of it)
        for (usize e = end; e > i; --e) {
            std::vector<Check> checks;
            for (usize k = i; k < e; ++k)
                checks.push_back(*as_check(lines[k]));
            for (usize j = e; j < lines.size(); ++j) {
                poll();
                const Value line = lines[j];
                const Value now = now_of(line);
                if (!now.nil()) {
                    std::vector<Value> cands;
                    candidates(now, cands);
                    for (const Value res : cands)
                        if (const auto m = of(checks, res))
                            if (auto r = call(lines, e, j, checks, res, *m))
                                return r;
                }
                if (e < end || !transparent(line))
                    break;
                bool changes = false;
                for (const Check& c : checks)
                    changes = changes || simplify::affects(line, c.cond);
                if (changes)
                    break;
            }
        }
        return std::nullopt;
    }

    // python _call: the site recorded (its checks abstracted, verified), the
    // lines from e on with the call where the result is used
    std::optional<std::vector<Value>> call(const std::vector<Value>& lines, usize e, usize j,
                                           const std::vector<Check>& checks, Value res, const Match& m)
    {
        Site s;
        s.op = m.op;
        s.a = m.a;
        s.b = params_of(m.op) == 2 ? m.b : NIL;
        Abstract ab(res, m);
        Concrete back(s.a, s.b);
        const Value result = result_of(m.op);
        if (!same_value(back(result), res))
            return std::nullopt;
        for (const Check& c : checks) {
            const Value cond = ab(c.cond);
            if (!only_params(cond) || !same_value(back(cond), c.cond))
                return std::nullopt;
            s.key.push_back(KeyCheck{cond, c.fail.kind, c.fail.panic, c.fail.reason});
            s.fails.push_back(c.fail);
        }
        const u32 id = u32(sites.size());
        sites.push_back(std::move(s));
        // the call (its site's number until the table is made)
        SmallVec<Value, 3> ops;
        ops.push_back(Value::small(id));
        ops.push_back(m.a);
        if (params_of(m.op) == 2)
            ops.push_back(m.b);
        const Value call = mk(Op::SAFEMATH, ops.span());
        std::vector<Value> out(lines.begin() + isize(e), lines.begin() + isize(j));
        uses(lines, j, res, call, out);
        return out;
    }

    // python _uses: the lines from j on with the call in place of the result,
    // until one changes what it reads - in that one, where it's read before
    // (a write's value, an if's condition); not in a loop that changes it
    static void uses(const std::vector<Value>& lines, usize j, Value res, Value call, std::vector<Value>& out)
    {
        Memo<Value, Value> memo;
        auto replace = [&](Value v) { return replace_in(v, res, call, memo); };
        for (usize k = j; k < lines.size(); ++k) {
            poll();
            const Value line = lines[k];
            const bool changes = simplify::affects(line, res);
            if (changes && (line.is(Op::WHILE) || line.is(Op::LOOP_PATH))) {
                out.insert(out.end(), lines.begin() + isize(k), lines.end());
                return;
            }
            if (changes && (line.is(Op::IF, 3) || line.is(Op::MERGED_IF, 3))) {
                const Value ops[] = {replace(line[0]), line[1], line[2]};
                const Value nl = mk_like(line, ops);
                cx().pcs.inherit(nl, line);
                out.push_back(nl);
                out.insert(out.end(), lines.begin() + isize(k) + 1, lines.end());
                return;
            }
            out.push_back(replace(line));
            if (changes) {
                out.insert(out.end(), lines.begin() + isize(k) + 1, lines.end());
                return;
            }
        }
    }

    static Value replace_in(Value v, Value old, Value with, Memo<Value, Value>& memo)
    {
        check_stack();
        if (v == old)
            return with;
        if (!v.is_expr() && !v.is_list())
            return v;
        if (const Value* r = memo.find(v))
            return *r;
        SmallVec<Value, 8> args;
        bool changed = false;
        for (const Value a : v.children()) {
            const Value na = replace_in(a, old, with, memo);
            changed |= na != a;
            args.push_back(na);
        }
        Value r = v;
        if (changed) {
            r = mk_like(v, args.span());
            cx().pcs.inherit(r, v);
        }
        memo.put(v, r);
        return r;
    }
};

// ---- the table -------------------------------------------------------------------------

// The sites' functions (python rewrite's keys, names, varying): fn_of[site].
void make_table(const std::vector<Site>& sites, Table& table, std::vector<u32>& fn_of,
                std::vector<std::vector<Value>>& site_data)
{
    // the distinct functions, in the order they're found
    struct Key {
        Arith op;
        const std::vector<KeyCheck>* checks;
        std::vector<u32> sites;
    };
    std::vector<Key> keys;
    std::vector<u32> key_of(sites.size());
    for (u32 s = 0; s < sites.size(); ++s) {
        u32 k = 0;
        for (; k < keys.size(); ++k)
            if (keys[k].op == sites[s].op && *keys[k].checks == sites[s].key)
                break;
        if (k == keys.size())
            keys.push_back(Key{sites[s].op, &sites[s].key, {}});
        keys[k].sites.push_back(s);
        key_of[s] = k;
    }
    // the block's order: by op, then as found; numbered per op
    std::vector<u32> fn_of_key(keys.size());
    for (const Arith op : {Arith::Add, Arith::Sub, Arith::Mul, Arith::Div, Arith::Mod, Arith::Inc, Arith::Dec}) {
        u32 n = 0;
        for (u32 k = 0; k < keys.size(); ++k) {
            if (keys[k].op != op)
                continue;
            const Key& key = keys[k];
            const Site& first = sites[key.sites[0]];
            Table::Fn fn;
            fn.op = op;
            fn.number = ++n;
            fn.params = params_of(op);
            fn.result = result_of(op);
            for (usize c = 0; c < key.checks->size(); ++c) {
                const KeyCheck& kc = (*key.checks)[c];
                Table::Check ch;
                ch.cond = kc.cond;
                ch.kind = kc.kind;
                ch.panic = kc.panic;
                // a message parameter where the sites revert with other data
                bool varying = false;
                if (kc.kind == FailKind::Error || kc.kind == FailKind::Panic)
                    for (const u32 s : key.sites)
                        varying = varying || sites[s].fails[c].data != first.fails[c].data;
                if (varying)
                    ch.message = fn.messages++;
                else
                    ch.fail = first.fails[c].line;
                fn.checks.push_back(ch);
            }
            fn_of_key[k] = u32(table.fns.size());
            table.fns.push_back(std::move(fn));
        }
    }
    fn_of.resize(sites.size());
    site_data.assign(sites.size(), {});
    for (u32 s = 0; s < sites.size(); ++s) {
        fn_of[s] = fn_of_key[key_of[s]];
        const Table::Fn& fn = table.fns[fn_of[s]];
        for (usize c = 0; c < fn.checks.size(); ++c)
            if (fn.checks[c].message)
                site_data[s].push_back(sites[s].fails[c].data);
    }
}

// the sites' calls as the table's: SAFEMATH(site, a, b) -> SAFEMATH(n, a, b, d...)
class Finish {
public:
    Finish(const std::vector<u32>& fn_of, const std::vector<std::vector<Value>>& data) : fn_of_(fn_of), data_(data) {}
    Value operator()(Value v)
    {
        check_stack();
        if (!v.is_expr() && !v.is_list())
            return v;
        if (!has_safemath(v))
            return v;
        if (const Value* r = memo_.find(v))
            return *r;
        SmallVec<Value, 8> args;
        bool changed = false;
        for (const Value a : v.children()) {
            const Value na = (*this)(a);
            changed |= na != a;
            args.push_back(na);
        }
        Value r = v;
        if (v.is(Op::SAFEMATH)) {
            const u32 site = u32(args[0].small_val());
            SmallVec<Value, 6> ops;
            ops.push_back(Value::small(fn_of_[site]));
            for (usize k = 1; k < args.size(); ++k)
                ops.push_back(args[k]);
            for (const Value d : data_[site])
                ops.push_back(d);
            r = mk(Op::SAFEMATH, ops.span());
        } else if (changed) {
            r = mk_like(v, args.span());
            cx().pcs.inherit(r, v);
        }
        memo_.put(v, r);
        return r;
    }

private:
    bool has_safemath(Value v)
    {
        check_stack();
        if (v.is(Op::SAFEMATH))
            return true;
        if (const u8* m = seen_.find(v))
            return *m == 2;
        bool r = false;
        for (const Value c : v.children())
            if ((c.is_expr() || c.is_list()) && has_safemath(c)) {
                r = true;
                break;
            }
        seen_.put(v, r ? 2 : 1);
        return r;
    }
    const std::vector<u32>& fn_of_;
    const std::vector<std::vector<Value>>& data_;
    Memo<Value, Value> memo_;
    Memo<Value, u8> seen_;
};

bool mentions_safemath(Value v, Memo<Value, u8>& memo)
{
    check_stack();
    if (v.is(Op::SAFEMATH))
        return true;
    if (!v.is_expr() && !v.is_list())
        return false;
    if (const u8* m = memo.find(v))
        return *m == 2;
    bool r = false;
    for (const Value c : v.children())
        if (mentions_safemath(c, memo)) {
            r = true;
            break;
        }
    memo.put(v, r ? 2 : 1);
    return r;
}

}  // namespace

std::shared_ptr<const SafeMathTable> rewrite(std::span<FunctionInfo> functions, std::span<FunctionInfo> internals,
                                             const ContractShared&)
{
    Rewriter rw;
    // the asts rewritten aside (the sites' numbers in their calls)
    std::vector<std::pair<FunctionInfo*, Value>> done;
    Memo<Value, u8> seen;
    for (const std::span<FunctionInfo> fs : {functions, internals})
        for (FunctionInfo& f : fs) {
            poll();
            if (f.problem || !f.trace.is_trace() || mentions_safemath(f.trace, seen))
                continue;
            const Value r = rw.ast(f.trace);
            if (r != f.trace)
                done.emplace_back(&f, r);
        }
    if (rw.sites.empty())
        return nullptr;
    auto table = std::make_shared<SafeMathTable>();
    std::vector<u32> fn_of;
    std::vector<std::vector<Value>> data;
    make_table(rw.sites, *table, fn_of, data);
    Finish finish(fn_of, data);
    std::vector<Value> asts;
    asts.reserve(done.size());
    for (const auto& [f, t] : done)
        asts.push_back(finish(t));
    // (nothing can fail past here)
    for (usize k = 0; k < done.size(); ++k)
        done[k].first->trace = asts[k];
    return table;
}

}  // namespace pan::safemath
