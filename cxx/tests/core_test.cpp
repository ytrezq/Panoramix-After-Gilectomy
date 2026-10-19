// The core: values, nodes, contexts, hash-consing, imports, compaction, the
// order, the integers, the dump and its parser, the budget, the jobs.
#include <doctest/doctest.h>
#include <gmpxx.h>

#include <atomic>
#include <thread>
#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "core/dump.hpp"
#include "core/evmint.hpp"
#include "core/intops.hpp"
#include "core/jobs.hpp"
#include "core/order.hpp"
#include "core/platform.hpp"
#include "core/smallvec.hpp"
#include "core/value.hpp"
#include "core/watchdog.hpp"

using namespace pan;

namespace {

// a context of its own for a test, on the calling thread
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

Value big(const char* hex) {
    mpz_class z(hex, 16);
    return mk_int_mpz(z.get_mpz_t());
}

}  // namespace

TEST_CASE("core: immediates") {
    CHECK(Value(true).is_true());
    CHECK(Value(false).is_false());
    CHECK(Value(true).is_bool());
    CHECK(!Value(true).is_false());
    CHECK(Value::none().is_none());
    CHECK(Value().nil());
    CHECK(Value(true) != Value(false));
    CHECK(Value(true).tag() == Tag::Bool);
    CHECK(Value::none().tag() == Tag::None);
    CHECK(Value().tag() == Tag::Nil);

    Value caller = Value::leaf(Op::CALLER);
    CHECK(caller.is_leaf());
    CHECK(caller.op() == Op::CALLER);
    CHECK(caller.leaf_n() == 0);
    CHECK(caller.tag() == Tag::Leaf);
    Value ok3 = Value::leaf(Op::CALL_SUCCESS, 3);
    CHECK(ok3.op() == Op::CALL_SUCCESS);
    CHECK(ok3.leaf_n() == 3);
    CHECK(ok3 != Value::leaf(Op::CALL_SUCCESS, 4));
    CHECK(ok3.has_flags(F_STATE));

    Value t3 = Value::name(NameKind::TMP, 3);
    CHECK(t3.is_name());
    CHECK(t3.is_name(NameKind::TMP));
    CHECK(!t3.is_name(NameKind::LOOP));
    CHECK(t3.name_id() == 3);
    CHECK(t3.op() == Op::NONE);
    CHECK(t3.has_flags(F_VAR));
    CHECK(Value::name(NameKind::PARAM, 0).has_flags(F_CALLDATA));
    CHECK(Value::name(NameKind::FUNC, 0xa9059cbbu).name_id() == 0xa9059cbbu);
    CHECK(!Value::name(NameKind::FUNC, 1).has_flags(F_VAR));
}

TEST_CASE("core: ints") {
    Fixture f;
    CHECK(mk_int(5) == Value::small(5));
    CHECK(mk_int(-5).small_val() == -5);
    CHECK(mk_int(SMALL_MAX).is_small());
    CHECK(mk_int(SMALL_MIN).is_small());
    Value b = mk_int(SMALL_MAX + 1);
    CHECK(b.is_big());
    CHECK(b == mk_int(SMALL_MAX + 1));  // hash-consed
    CHECK(b.as_i64() == SMALL_MAX + 1);
    CHECK(mk_uint(~u64(0)).is_big());
    CHECK(!mk_uint(~u64(0)).as_i64());
    CHECK(big("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff") ==
          big("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"));
    const u8 be[] = {0x12, 0x34};
    CHECK(mk_int_be(be) == mk_int(0x1234));
    u8 w[32] = {};
    w[0] = 0x80;
    CHECK(int_tstbit(mk_int_be(w), 255));

    CHECK(int_add(mk_int(SMALL_MAX), mk_int(1)) == mk_int(SMALL_MAX + 1));
    CHECK(int_sub(mk_int(SMALL_MAX + 1), mk_int(1)) == mk_int(SMALL_MAX));
    CHECK(int_mul(mk_int(1) , mk_int(-7)) == mk_int(-7));
    CHECK(int_cmp(mk_int(-1), b) == -1);
    CHECK(int_cmp(b, mk_int(-1)) == 1);
    CHECK(int_cmp(int_neg(b), mk_int(0)) == -1);
    CHECK(int_sign(int_neg(b)) == -1);
}

TEST_CASE("core: nodes are hash-consed") {
    Fixture f;
    Value x = Value::leaf(Op::CALLER);
    Value a = mk(Op::ADD, mk_int(1), x);
    Value b = mk(Op::ADD, mk_int(1), x);
    CHECK(a == b);
    CHECK(a.is_expr());
    CHECK(a.op() == Op::ADD);
    CHECK(a.size() == 2);
    CHECK(a[0] == mk_int(1));
    CHECK(a[1] == x);
    CHECK(a.is(Op::ADD, 2));
    CHECK(!a.is(Op::ADD, 3));
    CHECK(mk(Op::ADD, x, mk_int(1)) != a);  // no normalization in the core
    CHECK(a.hash() == b.hash());
    CHECK(mk(Op::CALLER) == x);  // a leaf op without operands: its leaf

    Value l = mk_list({a, b, x});
    CHECK(l.is_list());
    CHECK(!l.is_trace());
    CHECK(l == mk_list({a, b, x}));
    Value t = mk_trace({mk(Op::STOP)});
    CHECK(t.is_trace());
    CHECK(t != mk_list({mk(Op::STOP)}));

    const u8 s[] = {'h', 'i'};
    Value by = mk_bytes(s);
    CHECK(by.is_bytes());
    CHECK(by.size() == 2);
    CHECK(by.bytes()[1] == 'i');
    CHECK(by == mk_bytes(s));

    CHECK(mk_like(a, a.args()) == a);
    const Value args2[] = {mk_int(2), x};
    CHECK(mk_like(a, args2) == mk(Op::ADD, mk_int(2), x));
    CHECK_THROWS_AS(mk(Op::ISZERO, a, b), InternalError);
    CHECK_THROWS_AS(mk(Op::ISZERO), InternalError);
}

TEST_CASE("core: content flags") {
    Fixture f;
    Value r = mk(Op::RANGE, mk_int(64), mk_int(32));
    Value m = mk(Op::MEM, r);
    CHECK(m.has_flags(F_MEM));
    CHECK(!r.has_flags(F_MEM));
    Value e = mk(Op::ADD, m, mk_int(1));
    CHECK(e.has_flags(F_MEM));
    CHECK(!e.has_flags(F_STORAGE));
    Value s = mk(Op::SLOAD, mk_int(0));
    (void)s;
    Value cd = mk(Op::CALLDATALOAD, mk_int(4));
    CHECK(cd.has_flags(F_CALLDATA));
    Value v = mk(Op::ADD, Value::name(NameKind::TMP, 1), mk_int(1));
    CHECK(v.has_flags(F_VAR));
    CHECK(!mk(Op::ADD, mk_int(2), mk_int(1)).flags());
}

TEST_CASE("core: contexts, the global layer, imports and compaction") {
    init();
    Budget b1{Budget::Limits{}};
    b1.attach_thread();
    auto c1 = Context::create(b1);
    auto c2 = Context::create(b1);
    Value v1, w1, max1;
    {
        ContextScope s(*c1);
        v1 = mk(Op::ADD, mk_int(1), Value::leaf(Op::CALLER));
        w1 = mk_list({v1, mk(Op::MUL, v1, v1)});
        max1 = big("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
    }
    {
        ContextScope s(*c2);
        // 2^256 - 1 is a global constant: the same pointer on every context
        CHECK(big("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff") == max1);
        Value v2 = mk(Op::ADD, mk_int(1), Value::leaf(Op::CALLER));
        CHECK(v2 != v1);  // another context, another node
        CHECK(compare(v2, v1) == 0);
        CHECK(v2.hash() == v1.hash());
        Importer imp;
        Value w2 = imp(w1);
        CHECK(w2[0] == v2);  // imported into c2: its canonical node
        CHECK(w2 == mk_list({v2, mk(Op::MUL, v2, v2)}));
        CHECK(imp.lookup(v1) == v2);
    }
    {
        ContextScope s(*c1);
        Value line = mk(Op::SSTORE, mk_int(0), v1);
        c1->pcs.note(line, 42);
        std::vector<Value> roots{w1, line};
        usize before = c1->arena.total();
        c1->compact(roots);
        CHECK(compare(roots[0], w1) == 0);
        CHECK(roots[0] == mk_list({mk(Op::ADD, mk_int(1), Value::leaf(Op::CALLER)),
                                    mk(Op::MUL, roots[0][0], roots[0][0])}));
        CHECK(c1->pcs.pc_of(roots[1]) == 42u);
        CHECK(c1->arena.total() <= before);
    }
    c1.reset();
    c2.reset();
    b1.detach_thread();
}

TEST_CASE("core: the structural order") {
    Fixture f;
    Value x = Value::leaf(Op::CALLER);
    std::vector<Value> v{mk(Op::ADD, mk_int(1), x), Value::none(), mk_int(3), Value(true),
                         big("10000000000000000000000000"), Value::name(NameKind::TMP, 2), mk_int(-4),
                         Value(false), x, mk_list({mk_int(1)}), Value::name(NameKind::TMP, 1)};
    std::sort(v.begin(), v.end(), StructuralLess{});
    CHECK(v[0] == mk_int(-4));
    CHECK(v[1] == mk_int(3));
    CHECK(v[2].is_big());
    CHECK(v[3] == Value(false));
    CHECK(v[4] == Value(true));
    CHECK(v[5].is_none());
    CHECK(v[6] == x);
    CHECK(v[7] == Value::name(NameKind::TMP, 1));
    CHECK(v[8] == Value::name(NameKind::TMP, 2));
    CHECK(v[9].is_expr());
    CHECK(v[10].is_list());
    CHECK(compare(mk(Op::ADD, mk_int(1), x), mk(Op::ADD, mk_int(2), x)) < 0);
}

TEST_CASE("core: dump and parse_sexpr") {
    Fixture f;
    const char* cases[] = {
        "(add 1 (mask_shl 160 0 0 caller))",
        "(call_success 3)",
        "[1 -2 True False None tmp3 param0 _msize]",
        "(iszero (calldataload 4))",
        "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "b\"hi\\n\"",
    };
    for (const char* c : cases) {
        CAPTURE(c);
        Value v = V(c);
        CHECK(dump(v) == c);
        CHECK(V(dump(v)) == v);
    }
    CHECK(V("(add 1 2)") == mk(Op::ADD, mk_int(1), mk_int(2)));
    CHECK_THROWS_AS(V("(add 1"), InvalidInput);
    CHECK_THROWS_AS(V("(no_such_op 1)"), InvalidInput);
}

TEST_CASE("core: EvmInt and Word256") {
    Fixture f;
    EvmInt a = EvmInt::pow2(256) - 1;
    CHECK(a.value() == big("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"));
    CHECK(EvmInt(a.value()) == a);
    CHECK(floordiv(EvmInt(-7), EvmInt(2)) == -4);
    CHECK(pymod(EvmInt(-7), EvmInt(2)) == 1);
    CHECK((EvmInt(-1) & EvmInt(0xff)) == 0xff);
    Word256 m = Word256::from_value(mk_int(-1));
    CHECK(m.to_value() == a.value());
    Word256 one = Word256::of(1);
    CHECK(add(m, one).is_zero());
    CHECK(div(one, Word256::of(0)).is_zero());
    CHECK(shl(Word256::of(255), one).to_value() == EvmInt::pow2(255).value());
    CHECK(clz(Word256::of(0)).as_u64() == 256u);
    CHECK(sdiv(m, Word256::of(2)).is_zero());  // -1 / 2 = 0 (truncated)
    CHECK_THROWS_AS(EvmInt::pow2(u64(1) << 30), SizeLimit);
}

TEST_CASE("core: the budget") {
    init();
    {
        Budget b{Budget::Limits{.memory = usize(8) << 20}};
        b.attach_thread();
        auto c = Context::create(b);
        ContextScope s(*c);
        // past 8 MiB of nodes: MemoryLimit, the context still usable after
        CHECK_THROWS_AS(
            [] {
                for (i64 i = 0;; i++) mk(Op::ADD, mk_int(i), mk_int(i + 1));
            }(),
            MemoryLimit);
        CHECK(mk(Op::ADD, mk_int(1), mk_int(2)).is_expr());
        b.detach_thread();
    }
    {
        Budget b{Budget::Limits{}};
        b.attach_thread();
        struct Deep {
            PAN_NOINLINE static int go(int n) {
                check_stack();
                volatile char pad[512];
                pad[0] = char(n);
                int r = n > 1000000000 ? 0 : go(n + 1);
                return r + pad[0];  // read after the call: a real recursion
            }
        };
        CHECK_THROWS_AS(Deep::go(0), DepthLimit);
        b.expire();
        CHECK_THROWS_AS(poll(), Timeout);
        bool caught_as_error = false;
        try {
            poll();
        } catch (const Error&) {
            caught_as_error = true;
        } catch (const Abort&) {
        }
        CHECK(!caught_as_error);
        b.detach_thread();
    }
    CHECK_NOTHROW(poll());  // no budget: no limit
}

TEST_CASE("core: parallel_for is deterministic") {
    for (usize threads : {usize(1), usize(2), usize(4)}) {
        std::vector<u64> out(100);
        parallel_for(out.size(), threads, [&](usize i) {
            init();
            Budget b{Budget::Limits{}};
            b.attach_thread();
            auto c = Context::create(b);
            {
                ContextScope s(*c);
                Value v = mk_int(i64(i));
                for (int k = 0; k < 50; k++) v = mk(Op::ADD, v, mk_int(k));
                out[i] = v.hash();
            }
            c.reset();
            b.detach_thread();
        });
        Fixture f;
        for (usize i = 0; i < out.size(); i++) {
            Value v = mk_int(i64(i));
            for (int k = 0; k < 50; k++) v = mk(Op::ADD, v, mk_int(k));
            CHECK(out[i] == v.hash());  // content hashes: the same in every context
        }
    }
}

TEST_CASE("core: the watchdog expires a budget") {
    Budget b{Budget::Limits{}};
    b.attach_thread();
    {
        Watchdog::Watch w(b, platform::monotonic_ns() + 20'000'000);
        auto start = platform::monotonic_ns();
        bool timed_out = false;
        while (platform::monotonic_ns() - start < 2'000'000'000) {
            try {
                poll();
            } catch (const Timeout&) {
                timed_out = true;
                break;
            }
            std::this_thread::yield();
        }
        CHECK(timed_out);
    }
    b.detach_thread();
}

TEST_CASE("core: SmallVec grows from its own elements") {
    SmallVec<u64, 2> v;
    v.push_back(7);
    v.push_back(8);
    for (int i = 0; i < 100; i++) v.push_back(v.back());  // the argument is in the buffer grow frees
    CHECK(v.size() == 102);
    CHECK(v.back() == 8);
    SmallVec<u64, 2> w;
    w.push_back(1);
    w.push_back(2);
    for (int i = 0; i < 6; i++) w.append(w.span());  // the source is the vector itself
    CHECK(w.size() == 128);
    CHECK(w[127] == 2);
    for (int i = 0; i < 10; i++) w.insert_front(w.back());
    CHECK(w[0] == 2);
    CHECK(w.size() == 138);
}
