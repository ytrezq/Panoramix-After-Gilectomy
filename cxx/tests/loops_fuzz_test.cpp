// Lot 6: make_whiles on random raw traces - loops of the VM's shapes (the
// exit test at the head or at the end, a merged continuation, checks on the
// way, an exit by a check whose branch ends the run, breaks with merge
// variables, nested loops, lines rotated), the result run against the input
// in lot 11's trace machine on several worlds: the same outcome, the same
// effects. Deterministic (a fixed seed); PANORAMIX_LOOPS_FUZZ=N for more.
#include <doctest/doctest.h>

#include <algorithm>
#include <cstdlib>
#include <utility>
#include <optional>
#include <string>
#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/evmint.hpp"
#include "exec/machine.hpp"
#include "algebra/ranges.hpp"
#include "core/order.hpp"
#include "loops/loops.hpp"

using namespace pan;
namespace L = pan::loops;

namespace {

struct Fixture {
    Budget budget{Budget::Limits{}};
    std::unique_ptr<Context> ctx;
    std::optional<ContextScope> scope;
    Fixture() {
        init();
        budget.attach_thread();
        ctx = Context::create(budget);
        scope.emplace(*ctx);
    }
    ~Fixture() {
        scope.reset();
        ctx.reset();
        budget.detach_thread();
    }
};

u64 mix(u64 x) {
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdull;
    x ^= x >> 33;
    x *= 0xc4ceb9fe1a85ec53ull;
    x ^= x >> 33;
    return x;
}

struct World final : exec::SimpleHost {
    explicit World(u64 seed) {
        calldata.resize(4 + 32 * 4);
        for (usize i = 0; i < calldata.size(); ++i) {
            u64 r = mix(seed * 7919 + i);
            calldata[i] = ((i - 4) % 32 < 31) ? 0 : u8(r % 8);
        }
    }
};

// a small PRNG
struct Rng {
    u64 s;
    u32 next(u32 n) {
        s = mix(s + 0x9e3779b97f4a7c15ull);
        return u32(s % n);
    }
    bool coin(u32 in = 2) { return next(in) == 0; }
};

Value sm(i64 x) { return Value::small(x); }
Value sized32(Value v) { return mk(Op::SIZED, sm(32), v); }

// Random raw traces, their loops as lot 5's VM makes them.
class Gen {
public:
    explicit Gen(u64 seed) : r_{seed} {}

    Value trace() {
        lines_.clear();
        std::vector<Value> out;
        out.push_back(mk(Op::SETVAR, tmp(), cdword(0)));
        block(out, 0, 2);
        out.push_back(ret());
        return mk_trace(std::span<const Value>(out.data(), out.size()));
    }

private:
    struct Loop {
        Value id;
        std::vector<Value> vars;  // vars[0]: the counter
        i64 bound;
    };

    Value tmp() { return Value::name(NameKind::TMP, ++ntmp_); }
    Value cdword(int k) { return mk(Op::CALLDATALOAD, sm(4 + 32 * k)); }
    Value memword(i64 at) { return mk(Op::MEM, mk(Op::RANGE, sm(at), sm(32))); }
    Value ret() { return mk(Op::RETURN, mk(Op::MEM, mk(Op::RANGE, sm(0), sm(256)))); }

    // an expression of what's around: the loops' variables, calldata, memory
    Value expr() {
        Value terms[4];
        int n = 0;
        if (!loops_.empty() && r_.coin()) {
            const Loop& l = loops_[r_.next(u32(loops_.size()))];
            terms[n++] = l.vars[r_.next(u32(l.vars.size()))];
        }
        if (r_.coin(3)) terms[n++] = cdword(int(r_.next(4)));
        if (r_.coin(3)) terms[n++] = memword(32 * r_.next(8));
        if (n == 0) return sm(r_.next(9));
        Value e = terms[0];
        for (int i = 1; i < n; ++i) e = mk(Op::ADD, e, terms[i]);
        if (r_.coin(3)) e = mk(Op::MUL, sm(1 + r_.next(3)), e);
        return e;
    }
    Value setmem() { return mk(Op::SETMEM, mk(Op::RANGE, sm(32 * r_.next(8)), sm(32)), sized32(expr())); }
    Value halt() {
        switch (r_.next(4)) {
            case 0: return mk(Op::REVERT, None);
            case 1: return ret();
            case 2: return mk(Op::STOP);
            default: return mk(Op::REVERT, mk(Op::MEM, mk(Op::RANGE, sm(0), sm(64))));
        }
    }
    // a check: IF(c, [ ... halt], [])
    Value check() {
        std::vector<Value> b;
        if (r_.coin()) b.push_back(setmem());
        b.push_back(halt());
        Value c = mk(Op::EQ, expr(), sm(r_.next(6)));
        return mk(Op::IF, c, mk_trace(std::span<const Value>(b.data(), b.size())), mk_trace({}));
    }
    // a line of a block
    void line(std::vector<Value>& out) {
        switch (r_.next(6)) {
            case 0: out.push_back(mk(Op::SETVAR, tmp(), expr())); break;
            case 1: out.push_back(mk(Op::STORE, sm(256), sm(0), sm(r_.next(4)), expr())); break;
            case 2: out.push_back(check()); break;
            case 3: out.push_back(mk(Op::LOG1, mk(Op::MEM, mk(Op::RANGE, sm(0), sm(64))), expr())); break;
            default: out.push_back(setmem()); break;
        }
    }
    // the GOTO of a loop: its counter + 1, the others moved
    Value go(const Loop& l) {
        std::vector<Value> sv;
        for (usize i = 0; i < l.vars.size(); ++i) {
            Value v = l.vars[i];
            Value next = i == 0 ? mk(Op::ADD, sm(1), v) : (r_.coin() ? mk(Op::ADD, sm(32), v) : expr());
            sv.push_back(mk(Op::SETVAR, v, next));
        }
        return mk(Op::GOTO, l.id, mk_trace(std::span<const Value>(sv.data(), sv.size())));
    }
    // the condition to go on: the counter below the bound
    Value goes_on(const Loop& l) { return mk(Op::LT, l.vars[0], sm(l.bound)); }

    // lines into out; a loop maybe (its region the rest of out's trace)
    void block(std::vector<Value>& out, int depth, int max_depth) {
        const u32 n = r_.next(3);
        for (u32 i = 0; i < n; ++i) line(out);
        if (depth < max_depth && (depth == 0 || r_.coin())) loop(out, depth, max_depth);
    }

    // a loop: its LABEL then its region (the rest of out)
    void loop(std::vector<Value>& out, int depth, int max_depth) {
        Loop l;
        l.id = Value::name(NameKind::LOOP_ID, ++nloop_);
        l.bound = 1 + r_.next(4);
        const u32 nv = 1 + r_.next(2);
        std::vector<Value> sv;
        for (u32 i = 0; i < nv; ++i) {
            Value v = Value::name(NameKind::LOOP, (nloop_ << 12) | (i + 1));
            l.vars.push_back(v);
            sv.push_back(mk(Op::SETVAR, v, i == 0 ? sm(0) : expr()));
        }
        out.push_back(mk(Op::LABEL, l.id, mk_trace(std::span<const Value>(sv.data(), sv.size()))));
        loops_.push_back(l);
        // the lines before the exit test (rotated, maybe)
        const u32 np = r_.next(3);
        for (u32 i = 0; i < np; ++i) line(out);
        std::vector<Value> body;
        auto make_body = [&](bool with_goto) {
            body.clear();
            const u32 nb = r_.next(3);
            for (u32 i = 0; i < nb; ++i) line(body);
            if (depth + 1 < max_depth && r_.coin(3)) {
                // a nested loop in the body, then (in its region) our goto
                std::vector<Value> inner;
                loop_into(inner, depth + 1, max_depth, with_goto ? &l : nullptr);
                body.insert(body.end(), inner.begin(), inner.end());
                return;
            }
            // a break, maybe: IF(c, [merge setvar], [... goto])
            if (with_goto && r_.coin(4)) {
                Value t = Value::name(NameKind::TMP, 900 + nloop_);
                std::vector<Value> rest{go(l)};
                body.push_back(mk(Op::IF, mk(Op::EQ, l.vars[0], sm(r_.next(3))),
                                  mk_trace({mk(Op::SETVAR, t, expr())}),
                                  mk_trace(std::span<const Value>(rest.data(), rest.size()))));
                breakvar_ = t;
                return;
            }
            if (with_goto) body.push_back(go(l));
        };
        breakvar_ = Value();
        switch (r_.next(5)) {
            case 0: {  // the test at the head, the exit branch the rest (no merge)
                make_body(true);
                std::vector<Value> ex;
                line(ex);
                ex.push_back(halt());
                out.push_back(mk(Op::IF, goes_on(l), mk_trace(std::span<const Value>(body.data(), body.size())),
                                 mk_trace(std::span<const Value>(ex.data(), ex.size()))));
                break;
            }
            case 1: {  // the test at the head, a merged continuation
                make_body(true);
                Value t = breakvar_;
                std::vector<Value> ex;
                if (!t.nil()) ex.push_back(mk(Op::SETVAR, t, l.vars[r_.next(u32(l.vars.size()))]));
                out.push_back(mk(Op::IF, goes_on(l), mk_trace(std::span<const Value>(body.data(), body.size())),
                                 mk_trace(std::span<const Value>(ex.data(), ex.size()))));
                if (!t.nil()) out.push_back(mk(Op::SETMEM, mk(Op::RANGE, sm(224), sm(32)), sized32(t)));
                line(out);
                break;
            }
            case 2: {  // the exit a check whose branch ends the run
                std::vector<Value> ex;
                line(ex);
                ex.push_back(halt());
                out.push_back(mk(Op::IF, mk(Op::GE, l.vars[0], sm(l.bound)),
                                 mk_trace(std::span<const Value>(ex.data(), ex.size())), mk_trace({})));
                make_body(true);
                if (!breakvar_.nil()) {
                    // (a break here would fall off the region: give it an end)
                    body.push_back(mk(Op::STOP));
                }
                out.insert(out.end(), body.begin(), body.end());
                break;
            }
            case 3: {  // the test at the end (vyper), a merged continuation
                make_body(false);
                out.insert(out.end(), body.begin(), body.end());
                out.push_back(mk(Op::IF, goes_on(l), mk_trace({go(l)}), mk_trace({})));
                line(out);
                break;
            }
            default: {  // the test at the end, a halt when it fails
                make_body(false);
                out.insert(out.end(), body.begin(), body.end());
                out.push_back(mk(Op::IF, goes_on(l), mk_trace({go(l)}), mk_trace({halt()})));
                break;
            }
        }
        loops_.pop_back();
    }

    // a nested loop in a block of its own; the outer's goto (if any) where
    // the inner one is left
    void loop_into(std::vector<Value>& out, int depth, int max_depth, const Loop* outer) {
        Loop l;
        l.id = Value::name(NameKind::LOOP_ID, ++nloop_);
        l.bound = 1 + r_.next(3);
        Value v = Value::name(NameKind::LOOP, (nloop_ << 12) | 1);
        l.vars.push_back(v);
        out.push_back(mk(Op::LABEL, l.id, mk_trace({mk(Op::SETVAR, v, sm(0))})));
        loops_.push_back(l);
        std::vector<Value> b;
        line(b);
        b.push_back(go(l));
        std::vector<Value> ex;
        if (outer) ex.push_back(go(*outer));
        out.push_back(mk(Op::IF, goes_on(l), mk_trace(std::span<const Value>(b.data(), b.size())),
                         mk_trace(std::span<const Value>(ex.data(), ex.size()))));
        loops_.pop_back();
        (void)depth;
        (void)max_depth;
    }

    Rng r_;
    std::vector<Loop> loops_;
    std::vector<Value> lines_;
    Value breakvar_;
    u32 ntmp_ = 0, nloop_ = 0;
};

std::string show(const exec::Outcome& o) {
    std::string s = exec::status_name(o.status);
    s += " data " + std::to_string(o.data.size());
    if (!o.note.empty()) s += " (" + o.note + ")";
    return s;
}

// the same runs (an exhausted one: not compared); counts the conclusive ones
bool same_runs(Value t, Value u, int n, int& conclusive, bool quiet = false) {
    FunctionInfo fn;
    fn.kind = FunctionInfo::Kind::Selector;
    exec::Program p;
    exec::Machine m(p);
    exec::MachineLimits lim;
    lim.steps = 20000;
    m.set_limits(lim);
    for (int s = 0; s < n; ++s) {
        World w1{u64(s)}, w2{u64(s)};
        exec::Outcome a = m.run(w1, fn, t);
        exec::Outcome b = m.run(w2, fn, u);
        if (b.status == exec::Status::Bug) {
            if (!quiet) MESSAGE("bug: " << show(b));
            return false;
        }
        if (a.status == exec::Status::Bug) continue;  // (the generator's: a variable read unset)
        if (a.status == exec::Status::Exhausted || b.status == exec::Status::Exhausted) continue;
        ++conclusive;
        if (a.status != b.status || a.data != b.data || w1.effects != w2.effects) {
            if (!quiet) MESSAGE("world " << s << ": " << show(a) << " vs " << show(b));
            return false;
        }
    }
    return true;
}

}  // namespace

TEST_CASE("loops: make_whiles on random raw traces, checked by execution") {
    Fixture f;
    const char* env = std::getenv("PANORAMIX_LOOPS_FUZZ");
    const int count = env ? std::atoi(env) : 400;
    L::whiles_stats() = {};
    int conclusive = 0, failed = 0;
    for (int i = 0; i < count && failed < 3; ++i) {
        Gen g(u64(i) * 1000003u + 17);
        Value t = g.trace();
        std::vector<LoopInfo> loops;
        Value u;
        try {
            u = L::make_whiles(t, loops);
        } catch (const Unsupported& e) {
            FAIL_CHECK("Unsupported: " << e.what() << "\n" << dump_trace(t));
            ++failed;
            continue;
        }
        if (!same_runs(t, u, 8, conclusive)) {
            ++failed;
            FAIL_CHECK("trace " << i << ":\n" << dump_trace(t) << "\n->\n" << dump_trace(u));
        }
    }
    const L::WhilesStats& s = L::whiles_stats();
    MESSAGE("loops " << s.labels << ": exit test " << s.exit_test << " (rotated " << s.rotated << " renamed "
                     << s.renamed << " after " << s.exit_after << " check " << s.check_exit << "), while True "
                     << s.while_true << ", no loop " << s.no_loop << "; conclusive runs " << conclusive);
    CHECK(failed == 0);
    CHECK(conclusive > count);
    CHECK(s.exit_test > 0);
    CHECK(s.while_true > 0);
    CHECK(s.rotated > 0);
    CHECK(s.check_exit > 0);
}

namespace {

// the trace's variables installed in the algebra (as lot 7's simplify_trace does)
struct Vars {
    explicit Vars(Value trace) {
        std::vector<std::pair<Value, Value>> pairs;
        std::vector<Value> todo{trace};
        while (!todo.empty()) {
            Value v = todo.back();
            todo.pop_back();
            if (!(v.is_list() || v.is_expr())) continue;
            if (v.is(Op::SETVAR, 2)) {
                std::pair<Value, Value> p{v[0], v[1]};
                if (std::find(pairs.begin(), pairs.end(), p) == pairs.end()) pairs.push_back(p);
                continue;
            }
            if (v.is_expr() && !has(v.op(), LINE)) continue;
            for (Value x : v.children()) todo.push_back(x);
        }
        std::sort(pairs.begin(), pairs.end(), [](const auto& a, const auto& b) {
            int c = compare(a.first, b.first);
            return c != 0 ? c < 0 : compare(a.second, b.second) < 0;
        });
        alg::set_variables(pairs, {});
    }
    ~Vars() { alg::clear_variables(); }
};

// a random copy / fill loop of python's loop_to_setmem shape
Value copy_loop(Rng& r) {
    const Value i = Value::name(NameKind::LOOP, 4097);
    const Value id = Value::name(NameKind::LOOP_ID, 1);
    const bool up = r.coin();
    const bool unit = r.coin();  // the counter steps by 1 (the address by 32 times it) or by 32
    // the bound: up to 5 iterations
    const i64 trips = r.next(6);
    const Value n = mk(Op::SETVAR, Value::name(NameKind::TMP, 1),
                       mk(Op::MASK_SHL, sm(3), sm(0), sm(0), mk(Op::CALLDATALOAD, sm(4))));
    const Value tn = Value::name(NameKind::TMP, 1);
    (void)trips;
    Value start, cond, step;
    const i64 scale = unit ? 1 : 32;
    if (up) {
        start = sm(0);
        cond = mk(Op::LT, i, unit ? tn : mk(Op::MUL, sm(32), tn));
        step = mk(Op::ADD, sm(scale), i);
    } else {
        start = unit ? tn : mk(Op::MUL, sm(32), tn);
        cond = mk(Op::GT, i, sm(0));
        step = mk(Op::ADD, sm(-scale), i);
    }
    auto addr = [&](i64 base) {
        Value moved = unit ? mk(Op::MUL, sm(32), i) : i;
        return mk(Op::ADD, sm(base), moved);
    };
    const i64 dst = 32 * i64(r.next(12)) + (r.coin(4) ? 7 : 0);
    Value v;
    switch (r.next(4)) {
        case 0: v = sm(0); break;
        case 1: v = mk(Op::CALLDATALOAD, addr(4 + 32 * i64(r.next(3)))); break;
        default: {
            const i64 src = 32 * i64(r.next(12)) + (r.coin(4) ? 3 : 0);
            v = mk(Op::MEM, mk(Op::RANGE, addr(src), sm(32)));
            break;
        }
    }
    const Value body = mk_trace({mk(Op::SETMEM, mk(Op::RANGE, addr(dst), sm(32)), v),
                                 mk(Op::CONTINUE, id, mk_trace({mk(Op::SETVAR, i, step)}))});
    const Value w = mk(Op::WHILE, cond, body, id, mk_trace({mk(Op::SETVAR, i, start)}));
    return mk_trace({n, mk(Op::SETMEM, mk(Op::RANGE, sm(0), sm(1024)), mk(Op::CALLDATA_BYTES, sm(4), sm(1024))), w,
                     mk(Op::RETURN, mk(Op::DATA, mk(Op::MEM, mk(Op::RANGE, sm(0), sm(1024))), sized32(i)))});
}

}  // namespace

TEST_CASE("loops: loop_to_setmem on random copy loops, checked by execution") {
    Fixture f;
    const char* env = std::getenv("PANORAMIX_LOOPS_FUZZ");
    const int count = env ? std::atoi(env) : 400;
    int rewritten = 0, conclusive = 0, failed = 0, dubious_rewritten = 0, dubious_differ = 0;
    for (int k = 0; k < count && failed < 3; ++k) {
        Rng r{u64(k) * 7777 + 5};
        Value t = copy_loop(r);
        Value u, d;
        {
            Vars vars(t);
            u = L::loops_to_setmems(t);
            L::RewriteOptions o;
            o.dubious = true;
            d = L::loops_to_setmems(t, o);
        }
        if (u != t) ++rewritten;
        if (!same_runs(t, u, 8, conclusive)) {
            ++failed;
            FAIL_CHECK("copy loop " << k << ":\n" << dump_trace(t) << "\n->\n" << dump_trace(u));
        }
        if (d != u) {
            ++dubious_rewritten;
            int c2 = 0;
            if (!same_runs(t, d, 8, c2, true)) ++dubious_differ;
        }
    }
    MESSAGE("copy loops " << count << ": rewritten " << rewritten << ", conclusive runs " << conclusive
                          << "; python's (dubious) rewrites beyond them " << dubious_rewritten << ", of which differ "
                          << dubious_differ);
    CHECK(failed == 0);
    CHECK(rewritten > count / 4);
    // python's copy rewrite without the overlap rule: not sound (kept behind `dubious`)
    CHECK(dubious_differ > 0);
}
