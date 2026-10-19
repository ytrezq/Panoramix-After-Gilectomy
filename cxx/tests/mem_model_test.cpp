// The memory model (lot 4, src/mem/memory.hpp): widths, ranges, slices,
// reads assembled from writes, splits - on hand-made values, and checked by
// execution: the trace machine (lot 11) runs the writes then the read as it
// is and as assembled, on random calldata, and the bytes must agree.
#include <doctest/doctest.h>

#include <optional>
#include <string>
#include <vector>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "core/dump.hpp"
#include "core/evmint.hpp"
#include "exec/machine.hpp"
#include "mem/memory.hpp"

using namespace pan;
using namespace pan::mem;

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

Value S(i64 x) { return Value::small(x); }
Value R(i64 start, i64 len) { return make_range(S(start), S(len)); }
std::string D(Value v) { return v.nil() ? std::string("NIL") : dump(v); }
std::string D(std::optional<Value> v) { return v ? dump(*v) : std::string("nullopt"); }
std::string DV(std::span<const Value> vs) {
    std::string s = "[";
    for (Value v : vs) s += (s.size() > 1 ? " " : "") + dump(v);
    return s + "]";
}

// random values for what expressions read, a storage field read as the
// bits of its slot's word
struct StorageEnv final : alg::Env {
    alg::RandomEnv base;
    explicit StorageEnv(u64 seed) : base(seed) {}
    std::optional<Word256> value(Value v, alg::Evaluator& ev) override {
        if (v.is(Op::STORAGE, 3) && v[0].is_small() && v[1].is_small() && !(v[0] == Value::small(256) && v[1] == Value::small(0))) {
            auto slot = base.value(mk(Op::STORAGE, Value::small(256), Value::small(0), v[2]), ev);
            if (!slot) return std::nullopt;
            const i64 off = v[1].small_val();
            return alg::mask_shl_word(v[0].small_val(), off, -off, *slot);
        }
        return base.value(v, ev);
    }
};

// a deterministic generator (splitmix64)
struct Rng {
    u64 s;
    u64 next() {
        u64 z = (s += 0x9e3779b97f4a7c15ull);
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ull;
        z = (z ^ (z >> 27)) * 0x94d049bb133111ebull;
        return z ^ (z >> 31);
    }
    u64 below(u64 n) { return next() % n; }
    bool coin(u64 one_in) { return below(one_in) == 0; }
};

// one trace run as a selector function's body
exec::Outcome run(Value trace, exec::SimpleHost& host) {
    FunctionInfo fn;
    fn.kind = FunctionInfo::Kind::Selector;
    fn.selector = 1;
    fn.entry.selector = 1;
    fn.trace = trace;
    std::vector<FunctionInfo> fns{fn};
    exec::Program p;
    p.functions = fns;
    exec::Machine m(p);
    return m.run(host, fns[0]);
}

exec::SimpleHost random_host(Rng& rng) {
    exec::SimpleHost h;
    h.calldata.resize(4 + 32 * 12);
    for (u8& b : h.calldata) b = u8(rng.next());
    // a few edge words
    for (int k = 0; k < 3; ++k) {
        u64 at = 4 + 32 * rng.below(12);
        u8 fill = rng.coin(2) ? 0xff : 0x00;
        for (u64 i = 0; i < 32; ++i) h.calldata[at + i] = fill;
    }
    h.code.resize(200);
    for (u8& b : h.code) b = u8(rng.next());
    return h;
}

// the bytes a trace ending in RETURN(data) returns
std::optional<std::vector<u8>> returned(Value lines_before, Value data, exec::SimpleHost host) {
    SmallVec<Value, 16> lines;
    for (Value l : lines_before.args()) lines.push_back(l);
    lines.push_back(mk(Op::RETURN, data));
    exec::Outcome o = run(mk_trace(lines.span()), host);
    if (o.status != exec::Status::Return) return std::nullopt;
    return o.data;
}

}  // namespace

TEST_CASE("mem: widths") {
    Fixture fx;
    CHECK(is_bytes(V("(mem (range 64 32))")));
    CHECK(is_bytes(V("(sized 4 caller)")));
    CHECK(is_bytes(None));
    CHECK(!is_bytes(V("caller")));
    CHECK(!is_bytes(V("(add 1 caller)")));

    CHECK(D(width_of(V("(sized 4 caller)"))) == "4");
    CHECK(D(width_of(V("(mem (range 64 (calldataload 4)))"))) == "(calldataload 4)");
    CHECK(D(width_of(V("(data (sized 4 caller) (mem (range 0 28)))"))) == "32");
    CHECK(D(width_of(V("(data (sized 4 caller) (calldata_bytes 4 (calldataload 4)))"))) ==
          "(add 4 (calldataload 4))");
    CHECK(D(width_of(V("(returndata_bytes 1 0 32)"))) == "32");
    CHECK(D(width_of(V("(extcode_bytes caller (range 0 20))"))) == "20");
    CHECK(!width_of(V("caller")));
    CHECK(!width_of(V("(arr 1 (sized 32 caller))")));
    CHECK(!width_of(V("(data (sized 4 caller) (arr 1 (sized 32 caller)))")));
    CHECK(width_u64(V("(sized 20 caller)")) == 20u);

    // sized: as n bytes
    CHECK(D(sized(32, V("caller"))) == "(sized 32 caller)");
    CHECK(D(sized(32, V("(sized 32 caller)"))) == "(sized 32 caller)");
    CHECK(D(sized(20, V("(sized 32 caller)"))) == "(sized 20 caller)");
    CHECK(D(sized(32, V("(sized 20 caller)"))) == "(sized 32 (mask_shl 160 0 0 caller))");
    CHECK(D(sized(4, V("(mem (range 64 32))"))) == "(mem (range 92 4))");
    CHECK(D(sized(34, V("(mem (range 64 32))"))) == "(data (sized 2 0) (mem (range 64 32)))");
    CHECK(D(sized(1, S(0x1234))) == "(sized 1 52)");
    CHECK(D(sized(32, S(-1))) == D(mk(Op::SIZED, S(32), alg::sub(S(0), S(1)))));

    // keep_width
    CHECK(D(keep_width(V("(mem (range 64 32))"), V("caller"))) == "(sized 32 caller)");
    CHECK(D(keep_width(V("(sized 20 caller)"), V("(calldataload 4)"))) == "(sized 20 (calldataload 4))");
    CHECK(D(keep_width(V("(mem (range 64 32))"), V("(mem (range 0 32))"))) == "(mem (range 0 32))");
    CHECK(D(keep_width(V("caller"), V("origin"))) == "caller");
    CHECK(D(keep_widths(V("(return (mem (range 0 32)))"), V("(return caller)"))) == "(return (sized 32 caller))");
    CHECK(D(keep_widths(V("(setmem (range 0 4) (mem (range 64 4)))"), V("(setmem (range 0 4) (mem (range 64 32)))"))) ==
          "(setmem (range 0 4) (mem (range 92 4)))");
    CHECK(D(keep_widths(V("(log1 (mem (range 0 32)) 7)"), V("(log1 (mem (range 0 32)) 8)"))) == "(log1 (mem (range 0 32)) 8)");

    // implicit widths (the printer's)
    CHECK(implicit_width(V("caller")) == 32u);
    CHECK(implicit_width(V("(mask_shl 160 0 0 caller)")) == 20u);
    CHECK(implicit_width(V("(mask_shl 32 0 224 caller)")) == 32u);
    CHECK(implicit_width(V("(storage 8 0 1)")) == 1u);
    CHECK(!implicit_width(V("(mask_shl 1 0 0 caller)")));
    CHECK(!implicit_width(V("(mem (range 0 32))")));

    // byte operands
    auto ops = [](const char* s) {
        auto v = byte_operands(V(s));
        return std::vector<int>(v.begin(), v.end());
    };
    CHECK(ops("(return (mem (range 0 32)))") == std::vector<int>{0});
    CHECK(ops("(sha3 (sized 32 1) (sized 32 2))") == std::vector<int>{0, 1});
    CHECK(ops("(call 1 gas caller 0 None None)") == std::vector<int>{4, 5});
    CHECK(ops("(staticcall 1 gas caller None None)") == std::vector<int>{3, 4});
    CHECK(ops("(arr 2 (sized 32 1) (sized 32 2))") == std::vector<int>{1, 2});
    CHECK(ops("(setmem (range 0 32) (sized 32 1))").empty());
}

TEST_CASE("mem: ranges") {
    Fixture fx;
    // python memloc's asserts
    Value rd = V("(add 256 (mask_shl 246 5 0 (returndata_bytes 1 128 32)))");
    CHECK(overlaps(make_range(rd, S(32)), R(160, 96)) == Tri::False);
    CHECK(overlaps(R(260, 32), R(292, 32)) == Tri::False);
    CHECK(overlaps(R(324, 32), R(292, 32)) == Tri::False);
    CHECK(overlaps(R(292, 32), R(300, 32)) == Tri::True);
    CHECK(overlaps(R(300, 32), R(292, 32)) == Tri::True);
    CHECK(overlaps(R(64, 0), R(60, 32)) == Tri::False);
    CHECK(contains(R(64, 10), R(64, 32)) == Tri::False);
    CHECK(contains(R(64, 32), R(64, 10)) == Tri::True);
    CHECK(contains(R(64, 32), R(64, 32)) == Tri::True);
    CHECK(contains(R(64, 32), make_range(V("tmp1"), S(32))) == Tri::None);
    CHECK(contains(R(64, 32), R(1000, 0)) == Tri::True);
    // (a length that may be 0: contained then)
    CHECK(contains(R(10, 32), make_range(S(100), V("(calldataload 4)"))) != Tri::True);

    // symbolic: a base below 256, and words of memory
    Value b = V("(mask_shl 8 0 0 (calldataload 0))");
    auto Rb = [&](i64 off, i64 len) { return make_range(alg::add(b, S(off)), S(len)); };
    CHECK(overlaps(Rb(0, 32), Rb(32, 32)) == Tri::False);
    CHECK(overlaps(Rb(0, 32), Rb(31, 32)) == Tri::True);
    CHECK(contains(Rb(0, 64), Rb(16, 32)) == Tri::True);
    CHECK(contains(Rb(0, 32), Rb(16, 32)) == Tri::False);
    CHECK(overlaps(Rb(0, 32), R(1000, 32)) == Tri::False);
    CHECK(overlaps(Rb(0, 32), R(100, 32)) == Tri::None);
    // a length not known
    Value n = V("(calldataload 36)");
    CHECK(overlaps(make_range(S(64), n), R(64, 32)) == Tri::None);
    CHECK(overlaps(make_range(S(64), n), R(0, 64)) == Tri::False);
    CHECK(overwrites(R(64, 64), R(80, 16)) == Tri::True);
    CHECK(overwrites(R(64, 64), R(128, 16)) == Tri::False);
    CHECK(overwrites(R(64, 64), R(120, 16)) == Tri::None);
    CHECK(overwrites(R(64, 64), R(120, 0)) == Tri::False);
}

TEST_CASE("mem: survivors") {
    Fixture fx;
    CHECK(DV(survivors(R(64, 32), R(70, 10))) == "[(range 64 6) (range 80 16)]");
    CHECK(DV(survivors(R(64, 32), make_range(S(70), alg::add(V("(mask_shl 8 0 0 caller)"), S(100))))) ==
          "[(range 64 6)]");
    Value x = V("(calldataload 4)");
    CHECK(DV(survivors(make_range(S(64), x), make_range(S(70), alg::add(V("(mask_shl 8 0 0 caller)"), S(100))))) ==
          "[(range 64 (calldataload 4))]");
    CHECK(DV(survivors(R(64, 32), R(0, 200))) == "[]");
    CHECK(DV(survivors(R(64, 32), R(96, 32))) == "[(range 64 32)]");
    CHECK(DV(survivors(R(64, 32), R(64, 1))) == "[(range 65 31)]");
}

TEST_CASE("mem: slices") {
    Fixture fx;
    CHECK(D(slice(V("(mem (range 32 10))"), S(2), S(4))) == "(mem (range 34 2))");
    Value m = V("(sized 4 (mask_shl 32 0 0 (calldataload 0)))");
    CHECK(D(slice(m, S(0), S(4))) == D(m));
    CHECK(D(slice(m, S(2), S(4))) == "(sized 2 (mask_shl 16 0 0 (calldataload 0)))");
    CHECK(D(slice(m, S(0), S(2))) == "(sized 2 (mask_shl 16 16 -16 (calldataload 0)))");
    CHECK(D(slice(V("(sized 32 caller)"), S(12), S(32))) == "(sized 20 (mask_shl 160 0 0 caller))");
    CHECK(D(slice(V("(sized 32 (mask_shl 160 0 0 caller))"), S(0), S(12))) == "(sized 12 0)");
    CHECK(D(slice(V("(sized 40 caller)"), S(4), S(12))) == "(data (sized 4 0) (sized 4 (mask_shl 32 224 -224 caller)))");
    CHECK(D(slice(V("(calldata_bytes 4 (calldataload 4))"), S(32), S(64))).find("calldata_bytes 36") !=
          std::string::npos);
    CHECK(D(slice(V("(data (sized 4 caller) (mem (range 0 28)))"), S(2), S(10))) ==
          "(data (sized 2 (mask_shl 16 0 0 caller)) (mem (range 0 6)))");
    CHECK(D(slice(V("b\"abcdefghijklmnopqrstuvwxyz0123456789\""), S(30), S(36))) ==
          D(sized(6, mk_int_be(std::span<const u8>(reinterpret_cast<const u8*>("456789"), 6)))));
    CHECK(!slice(V("(sall (sv stor0))"), S(0), S(4)));
    // masks of memory reads
    CHECK(D(narrow_mem_mask(V("(mask_shl 160 0 0 (mem (range 64 32)))"))) == "(mem (range 76 20))");
    CHECK(D(narrow_mem_mask(V("(mask_shl 32 224 -224 (mem (range 64 32)))"))) == "(mem (range 64 4))");
    CHECK(D(narrow_mem_mask(V("(mask_shl 8 8 0 (mem (range 64 32)))"))) ==
          D(alg::mask(8, 0, 8, V("(mem (range 94 1))"))));
    CHECK(!narrow_mem_mask(V("(mask_shl 4 0 0 (mem (range 64 32)))")));
    CHECK(!narrow_mem_mask(V("(mask_shl 8 0 0 (mem (range 64 (calldataload 4))))")));
    CHECK(D(resize_bytes(V("(mem (range 64 32))"), S(4))) == "(mem (range 92 4))");
    CHECK(!resize_bytes(V("(sall (sv stor0))"), S(4)));
    CHECK(D(bare_element(V("(sized 20 (mask_shl 160 0 0 caller))"))) == "(mask_shl 160 0 0 caller)");
    CHECK(D(bare_element(V("(sized 32 (mask_shl 160 0 0 caller))"))) == "(sized 32 (mask_shl 160 0 0 caller))");
    CHECK(D(bare_element(V("(sized 32 caller)"))) == "caller");
    // a source whose offset may wrap around 2^256 isn't moved
    CHECK(!slice(V("(calldata_bytes (calldataload 4) 64)"), S(32), S(64)));
}

TEST_CASE("mem: concat and as_word") {
    Fixture fx;
    Value parts1[] = {V("(mem (range 0 4))"), V("(mem (range 4 28))")};
    CHECK(D(concat(parts1)) == "(mem (range 0 32))");
    Value parts2[] = {V("(sized 4 (mask_shl 32 224 -224 caller))"), V("(sized 28 (mask_shl 224 0 0 caller))")};
    CHECK(D(concat(parts2)) == "(sized 32 caller)");
    Value parts3[] = {V("(sized 2 1)"), V("(sized 2 2)"), V("(data)"), V("(sized 0 caller)")};
    CHECK(D(concat(parts3)) == "(sized 4 65538)");
    Value parts4[] = {V("(data (sized 1 1) (mem (range 0 1)))"), V("(mem (range 1 1))")};
    CHECK(D(concat(parts4)) == "(data (sized 1 1) (mem (range 0 2)))");
    Value parts5[] = {V("(sized 12 0)"), V("(sized 20 caller)")};
    CHECK(D(concat(parts5)) == "(sized 32 caller)");
    Value parts6[] = {V("(sized 12 0)"), V("(sized 20 (calldataload 4))")};
    CHECK(D(concat(parts6)) == "(data (sized 12 0) (sized 20 (calldataload 4)))");
    Value parts7[] = {V("(sized 40 0)"), V("(sized 30 0)")};
    CHECK(D(concat(parts7)) == "(sized 70 0)");

    CHECK(D(as_word(V("(sized 32 caller)"))) == "caller");
    CHECK(D(as_word(V("(sized 20 caller)"))) == "(mask_shl 160 0 0 caller)");
    CHECK(D(as_word(V("(calldata_bytes 4 32)"))) == "(calldataload 4)");
    CHECK(D(as_word(V("(calldata_bytes 4 4)"))) == "(mask_shl 32 224 -224 (calldataload 4))");
    CHECK(D(as_word(V("(mem (range 0 32))"))) == "(mem (range 0 32))");
    CHECK(D(as_word(V("(data (sized 4 2835717307) (sized 28 (mask_shl 160 0 0 caller)))"))) ==
          D(alg::bor(alg::mask(32, 0, 224, S(2835717307)), alg::mask(160, 0, 0, V("caller")))));
    CHECK(!as_word(V("(mem (range 0 33))")));
}

TEST_CASE("mem: python splits_mem") {
    Fixture fx;
    // known (66, 32) = a, then a write at (65, 32): its last byte left
    {
        MemState st;
        st.write(R(66, 32), V("tmp1"));
        st.write(R(65, 32), V("tmp2"));
        CHECK(D(st.read(R(97, 1))) == "(sized 1 (mask_shl 8 0 0 tmp1))");
        CHECK(D(st.read(R(65, 32))) == "(sized 32 tmp2)");
        CHECK(D(st.read(R(96, 2))) == "(data (sized 1 (mask_shl 8 0 0 tmp2)) (sized 1 (mask_shl 8 0 0 tmp1)))");
    }
    {
        MemState st;
        st.write(R(64, 32), V("tmp1"));
        st.write(R(65, 30), V("tmp2"));
        CHECK(D(st.read(R(64, 1))) == "(sized 1 (mask_shl 8 248 -248 tmp1))");
        CHECK(D(st.read(R(95, 1))) == "(sized 1 (mask_shl 8 0 0 tmp1))");
        CHECK(D(st.read(R(64, 32))) ==
              "(data (sized 1 (mask_shl 8 248 -248 tmp1)) (sized 30 tmp2) (sized 1 (mask_shl 8 0 0 tmp1)))");
    }
    {
        // a write at a place not known: nothing known after it
        MemState st;
        st.write(R(64, 32), V("tmp1"));
        st.write(make_range(V("tmp9"), S(32)), V("tmp2"));
        CHECK(!st.read(R(64, 32)));
        CHECK(st.pieces().size() == 1);
        CHECK(D(st.read(make_range(V("tmp9"), S(32)))) == "(sized 32 tmp2)");
    }
    {
        // a length not known: what's before it stays
        MemState st;
        st.write(R(64, 32), V("tmp1"));
        st.write(make_range(S(65), V("(calldataload 4)")), V("(calldata_bytes 0 (calldataload 4))"));
        CHECK(D(st.read(R(64, 1))) == "(sized 1 (mask_shl 8 248 -248 tmp1))");
        CHECK(D(st.read(R(64, 2))) == "(data (sized 1 (mask_shl 8 248 -248 tmp1)) (mem (range 65 1)))");
    }
    {
        // a copy whose source is overwritten afterwards
        MemState st;
        st.write(R(0, 32), V("tmp1"));
        st.write(R(64, 32), V("(mem (range 0 32))"));
        st.write(R(0, 32), V("tmp2"));
        CHECK(D(st.read(R(64, 32))) == "(sized 32 tmp1)");
        st.write(R(128, 32), V("(mem (range 200 32))"));
        CHECK(D(st.read(R(128, 32))) == "(mem (range 200 32))");
        st.write(R(210, 1), V("tmp3"));
        CHECK(!st.read(R(128, 32)));
    }
    {
        // fresh memory: zeroes
        MemState st(true);
        st.write(R(64, 32), V("tmp1"));
        CHECK(D(st.read(R(32, 64))) == "(data (sized 32 0) (sized 32 tmp1))");
        st.write(make_range(V("tmp5"), S(32)), V("tmp2"));
        CHECK(!st.read(R(32, 64)));
    }
    {
        // fresh memory: the places written merged, a copy of zeroes
        MemState st(true);
        st.write(R(0, 32), V("tmp1"));
        st.write(R(64, 32), V("tmp2"));
        st.write(R(32, 32), V("(mem (range 200 32))"));
        CHECK(D(st.read(R(32, 32))) == "(sized 32 0)");
        CHECK(D(st.read(R(96, 64))) == "(sized 64 0)");
        CHECK(D(st.read(R(90, 10))) == "(data (sized 6 (mask_shl 48 0 0 tmp2)) (sized 4 0))");
        // where paths meet: written on either, not fresh there
        MemState a(true), b(true);
        a.write(R(0, 32), V("tmp1"));
        b.write(R(32, 32), V("tmp2"));
        a.meet(b);
        CHECK(!a.read(R(0, 64)));
        CHECK(D(a.read(R(64, 32))) == "(sized 32 0)");
        // a write at a place the fresh memory can't place
        a.write(make_range(V("(calldataload 4)"), S(32)), V("tmp3"));
        CHECK(!a.read(R(64, 32)));
    }
    {
        // the facts' and variables' forgetting
        MemState st;
        st.write(R(0, 32), V("(storage 256 0 1)"));
        st.write(R(32, 32), V("tmp4"));
        st.forget_flags(F_STORAGE);
        CHECK(!st.read(R(0, 32)));
        CHECK(st.read(R(32, 32)));
        st.forget_name(V("tmp4"));
        CHECK(!st.read(R(32, 32)));
    }
    {
        // where paths meet
        MemState a, b;
        a.write(R(0, 32), V("tmp1"));
        a.write(R(32, 32), V("tmp2"));
        b.write(R(0, 32), V("tmp1"));
        b.write(R(32, 32), V("tmp3"));
        a.meet(b);
        CHECK(a.read(R(0, 32)));
        CHECK(!a.read(R(32, 32)));
    }
}

// Random writes then a read, run by the machine as they are and with the
// read assembled: the same bytes.
TEST_CASE("mem: fills agree with execution") {
    Fixture fx;
    Rng rng{12345};
    const Value base = V("(mask_shl 8 0 0 (calldataload 4))");  // below 256
    auto addr = [&](i64 off) { return rng.coin(3) ? alg::add(base, S(off)) : S(off); };
    auto word = [&]() -> Value {
        switch (rng.below(7)) {
            case 0: return mk_int(i64(rng.next() >> 2));
            case 1: return alg::mask(160, 0, 0, V("caller"));
            case 2: return alg::mask(i64(8 * (1 + rng.below(32))), i64(8 * rng.below(4)), 0,
                                     mk(Op::CALLDATALOAD, S(i64(4 + 32 * rng.below(12)))));
            case 3: return alg::bor(alg::mask(32, 0, 224, mk_int(i64(rng.next() >> 32))),
                                    alg::mask(160, 0, 0, mk(Op::CALLDATALOAD, S(36))));
            default: return mk(Op::CALLDATALOAD, S(i64(4 + 32 * rng.below(12))));
        }
    };
    int checked = 0, assembled = 0;
    for (int round = 0; round < 400; ++round) {
        exec::SimpleHost host = random_host(rng);
        SmallVec<Value, 16> lines;
        SmallVec<MemWrite, 16> writes;
        MemState st(rng.coin(2));
        const bool fresh = st.fresh();
        const int nw = 1 + int(rng.below(7));
        for (int i = 0; i < nw; ++i) {
            const i64 off = i64(rng.below(160));
            i64 len = rng.coin(4) ? 32 : i64(1 + rng.below(48));
            if (rng.coin(20)) len = 0;
            Value range = make_range(addr(off), S(len));
            Value value;
            switch (rng.below(8)) {
                case 0: value = word(); break;  // a word: its low len bytes
                case 1: value = mk(Op::MEM, make_range(addr(i64(rng.below(160))), S(len))); break;
                case 2: value = mk(Op::CALLDATA_BYTES, S(i64(rng.below(300))), S(len)); break;
                case 3: value = mk(Op::CODE_BYTES, S(i64(rng.below(220))), S(len)); break;
                case 4: {
                    std::vector<u8> bytes(static_cast<usize>(len), u8(0));
                    for (u8& c : bytes) c = u8(rng.next());
                    value = len > 32 ? mk_bytes(bytes) : mk(Op::SIZED, S(len), mk_int_be(bytes));
                    break;
                }
                case 5:
                    if (len >= 2) {
                        i64 k = 1 + i64(rng.below(u64(len - 1)));
                        value = mk(Op::DATA, mk(Op::SIZED, S(k), word()), mk(Op::SIZED, S(len - k), word()));
                        break;
                    }
                    [[fallthrough]];
                default: value = mk(Op::SIZED, S(len), word()); break;
            }
            Value line = mk(Op::SETMEM, range, value);
            lines.push_back(line);
            writes.push_back(as_write(line));
            st.write(range, value);
            // a read after each write
            const i64 roff = i64(rng.below(200));
            const i64 rlen = rng.coin(3) ? 32 : i64(rng.below(64));
            Value rr = make_range(addr(roff), S(rlen));
            std::optional<Value> got = st.read(rr);
            Value prefix = mk_trace(lines.span());
            if (got) {
                ++assembled;
                auto want = returned(prefix, mk(Op::MEM, rr), host);
                auto have = returned(prefix, *got, host);
                INFO("trace: " << dump_trace(prefix) << "\nread: " << D(rr) << "\nfilled: " << D(*got)
                               << "\nfresh: " << fresh);
                REQUIRE(want.has_value());
                REQUIRE(have.has_value());
                CHECK(*want == *have);
                ++checked;
                if (rlen <= 32) {
                    if (auto w = as_word(*got)) {
                        auto ww = returned(prefix, mk(Op::SIZED, S(32), mk(Op::MEM, rr)), host);
                        auto hw = returned(prefix, mk(Op::SIZED, S(32), *w), host);
                        INFO("as a word: " << D(*w));
                        REQUIRE(ww.has_value());
                        REQUIRE(hw.has_value());
                        CHECK(*ww == *hw);
                    }
                }
            }
        }
        // fill: the same as the state's read (no fresh memory)
        if (!fresh) {
            Value rr = make_range(addr(i64(rng.below(200))), S(32));
            auto a = fill(rr, writes.span());
            auto b = st.read(rr);
            CHECK(D(a) == D(b));
        }
    }
    MESSAGE("fills checked by execution: " << checked << " (assembled " << assembled << ")");
    CHECK(checked > 300);
}

TEST_CASE("mem: split_word") {
    Fixture fx;
    auto f = split_word(alg::bor(alg::mask(32, 0, 224, V("tmp1")), alg::mask(160, 0, 0, V("caller"))));
    REQUIRE(f);
    REQUIRE(f->size() == 3);
    CHECK(((*f)[0].off == 0 && (*f)[0].size == 160 && D((*f)[0].value) == "(mask_shl 160 0 0 caller)"));
    CHECK(((*f)[1].off == 160 && (*f)[1].size == 64 && (*f)[1].value == S(0)));
    CHECK(((*f)[2].off == 224 && (*f)[2].size == 32 && D((*f)[2].value) == "(mask_shl 32 0 0 tmp1)"));
    CHECK(!split_word(V("tmp1")));
    CHECK(split_word(V("caller"))->size() == 2);  // (160 bits, then zeroes)
    CHECK(!split_word(alg::bor(V("tmp1"), V("tmp2"))));
    // an address is 160 bits, a read of 4 bytes 32
    auto g = split_word(alg::bor(alg::mask(32, 0, 224, V("tmp1")), V("caller")));
    REQUIRE(g);
    CHECK(((*g)[0].size == 160 && D((*g)[0].value) == "caller"));
    auto h = split_word(alg::bor(alg::mask(32, 0, 224, V("tmp1")), V("(mem (range 64 4))")));
    REQUIRE(h);
    CHECK(((*h)[0].size == 32 && D((*h)[0].value) == "(mem (range 64 4))"));

    // the fields recompose to the word, for any value of what it's made of
    Rng rng{31337};
    int checked = 0;
    for (int round = 0; round < 300; ++round) {
        SmallVec<Value, 6> terms;
        i64 pos = 0;
        while (pos < 256) {
            i64 size = 1 + i64(rng.below(u64(std::min<i64>(80, 256 - pos))));
            Value src = mk(Op::CALLDATALOAD, S(i64(32 * rng.below(6))));
            switch (rng.below(5)) {
                case 0: {
                    const i64 o = i64(rng.below(16));
                    terms.push_back(alg::mask(size, o, pos - o, src));
                    break;
                }
                case 1: terms.push_back(alg::mask(size, 0, pos, alg::to_bool(src))); break;
                case 2: terms.push_back(alg::mask(size, 0, pos, mk_int(i64(rng.next() >> 3)))); break;
                case 3: terms.push_back(alg::mask(size, pos, 0, mk(Op::STORAGE, S(256), S(0), S(1)))); break;
                default: break;
            }
            pos += size + i64(rng.below(24));
        }
        if (terms.empty()) continue;
        Value w = alg::bor(terms.span());
        auto fields = split_word(w);
        if (!fields) continue;
        SmallVec<Value, 8> parts;
        u32 at = 0;
        for (const Field& fl : *fields) {
            CHECK(fl.off == at);
            at += fl.size;
            parts.push_back(alg::mask(fl.size, 0, fl.off, fl.value));
        }
        CHECK(at == 256);
        Value back = alg::bor(parts.span());
        for (u64 seed = 1; seed <= 4; ++seed) {
            StorageEnv env(seed * 7919 + u64(round));
            alg::Evaluator ev(env);
            INFO("word: " << D(w) << "\nrecomposed: " << D(back));
            CHECK(ev(w) == ev(back));
        }
        ++checked;
    }
    CHECK(checked > 150);
}

TEST_CASE("mem: split_setmem agrees with execution") {
    Fixture fx;
    Value line = mk(Op::SETMEM, R(64, 32),
                    mk(Op::SIZED, S(32),
                       alg::bor(alg::mask(32, 0, 224, S(0xa9059cbb)), alg::mask(160, 0, 0, V("(calldataload 4)")))));
    auto parts = split_setmem(line);
    CHECK(parts.size() == 3);
    CHECK(D(parts[0]) == "(setmem (range 76 20) (sized 20 (mask_shl 160 0 0 (calldataload 4))))");
    CHECK(D(parts[1]) == "(setmem (range 68 8) (sized 8 0))");
    CHECK(D(parts[2]) == "(setmem (range 64 4) (sized 4 2835717307))");
    // not an OR: as it is
    CHECK(split_setmem(mk(Op::SETMEM, R(64, 32), V("(sized 32 caller)"))).size() == 1);

    Rng rng{777};
    int checked = 0;
    for (int round = 0; round < 200; ++round) {
        exec::SimpleHost host = random_host(rng);
        SmallVec<Value, 4> terms;
        i64 pos = 0;
        while (pos < 256) {
            i64 size = 1 + i64(rng.below(u64(std::min<i64>(96, 256 - pos))));
            if (!rng.coin(3)) {
                Value src = rng.coin(4) ? V("(mem (range 64 32))") : mk(Op::CALLDATALOAD, S(i64(4 + 32 * rng.below(12))));
                Value t = rng.coin(5) ? alg::to_bool(src) : alg::mask(size, i64(rng.below(8)), pos - 0, src);
                if (rng.coin(5)) t = alg::mask(size, 0, pos, src);
                terms.push_back(t);
            }
            pos += size + i64(rng.below(16));
        }
        if (terms.size() < 2) continue;
        Value v = alg::bor(terms.span());
        const i64 n = rng.coin(3) ? 32 : i64(1 + rng.below(32));
        Value l = mk(Op::SETMEM, R(64, n), mk(Op::SIZED, S(n), v));
        Value pre = mk(Op::SETMEM, R(64, 32), mk(Op::SIZED, S(32), mk(Op::CALLDATALOAD, S(100))));
        auto split = split_setmem(l);
        SmallVec<Value, 8> a{pre, l}, b{pre};
        for (Value x : split) b.push_back(x);
        auto want = returned(mk_trace(a.span()), V("(mem (range 0 160))"), host);
        auto have = returned(mk_trace(b.span()), V("(mem (range 0 160))"), host);
        INFO("line: " << D(l) << "\nsplit: " << DV(split.span()));
        REQUIRE(want.has_value());
        REQUIRE(have.has_value());
        CHECK(*want == *have);
        ++checked;
    }
    CHECK(checked > 100);
}

TEST_CASE("mem: split_store agrees with execution") {
    Fixture fx;
    Value slot = S(3);
    Value stor = mk(Op::STORAGE, S(256), S(0), slot);
    // a field set, the other bits kept
    Value keep = alg::bor(alg::mask(160, 0, 0, V("caller")), alg::mask(96, 160, 0, stor));
    auto parts = split_store(mk(Op::STORE, S(256), S(0), slot, keep));
    CHECK(DV(parts.span()) == "[(store 160 0 3 (mask_shl 160 0 0 caller))]");
    // the slot's bits outside a mask cleared
    auto cleared = split_store(mk(Op::STORE, S(256), S(0), slot, alg::mask(64, 32, 0, stor)));
    CHECK(DV(cleared.span()) == "[(store 32 0 3 0) (store 160 96 3 0)]");

    Rng rng{4242};
    int checked = 0;
    for (int round = 0; round < 200; ++round) {
        exec::SimpleHost host = random_host(rng);
        Word256 init{};
        for (u64& l : init.limb) l = rng.next();
        host.storage[Word256::of(3)] = init;
        SmallVec<Value, 4> terms;
        i64 pos = 0;
        while (pos < 256) {
            i64 size = 1 + i64(rng.below(u64(std::min<i64>(96, 256 - pos))));
            switch (rng.below(4)) {
                case 0: terms.push_back(alg::mask(size, pos, 0, stor)); break;
                case 1: terms.push_back(alg::mask(size, 0, pos, mk(Op::CALLDATALOAD, S(i64(4 + 32 * rng.below(12)))))); break;
                case 2: terms.push_back(alg::mask(size, 0, pos, alg::to_bool(V("(calldataload 36)")))); break;
                default: break;
            }
            pos += size + i64(rng.below(16));
        }
        if (terms.size() < 2) continue;
        Value l = mk(Op::STORE, S(256), S(0), slot, alg::bor(terms.span()));
        auto split = split_store(l);
        exec::SimpleHost h1 = host, h2 = host;
        SmallVec<Value, 1> a{l};
        auto o1 = run(mk_trace(a.span()), h1);
        auto o2 = run(mk_trace(split.span()), h2);
        INFO("line: " << D(l) << "\nsplit: " << DV(split.span()));
        CHECK(o1.status == o2.status);
        CHECK(h1.storage == h2.storage);
        ++checked;
    }
    CHECK(checked > 100);
}

TEST_CASE("mem: byte_field_store") {
    Fixture fx;
    Value slot = V("(sha3 (sized 32 7))");
    Value stor = mk(Op::STORAGE, S(256), S(0), slot);
    Value k = alg::mask(5, 0, 0, V("(calldataload 4)"));  // a byte index below 32
    Value p = alg::exp(S(256), k);
    Value v = alg::mask(8, 0, 0, V("(calldataload 36)"));
    Value val = alg::bor(alg::mul(v, p), alg::band(alg::bnot(alg::mul(S(255), p)), stor));
    Value line = mk(Op::STORE, S(256), S(0), slot, val);
    INFO("line: " << D(line));
    auto r = byte_field_store(line);
    REQUIRE(r);
    CHECK(D(*r) == D(mk(Op::STORE, S(8), alg::mul(S(8), k), slot, v)));

    Rng rng{99};
    for (int round = 0; round < 50; ++round) {
        exec::SimpleHost host = random_host(rng);
        Word256 init{};
        for (u64& l : init.limb) l = rng.next();
        host.storage[exec::keccak256(std::vector<u8>{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7})] = init;
        exec::SimpleHost h1 = host, h2 = host;
        SmallVec<Value, 1> a{line}, b{*r};
        auto o1 = run(mk_trace(a.span()), h1);
        auto o2 = run(mk_trace(b.span()), h2);
        CHECK(o1.status == o2.status);
        CHECK(h1.storage == h2.storage);
    }
}

// The bytes algebra on random bytes expressions, by execution: a slice is
// those bytes, sized / resize_bytes / concat / as_word are what SIZED / DATA
// / the read as a word are.
TEST_CASE("mem: bytes algebra agrees with execution") {
    Fixture fx;
    Rng rng{2024};
    auto word = [&]() -> Value {
        switch (rng.below(5)) {
            case 0: return mk_int(i64(rng.next() >> 2));
            case 1: return alg::mask(160, 0, 0, V("caller"));
            case 2: return alg::mask(i64(8 * (1 + rng.below(32))), i64(8 * rng.below(4)), 0,
                                     mk(Op::CALLDATALOAD, S(i64(4 + 32 * rng.below(12)))));
            default: return mk(Op::CALLDATALOAD, S(i64(4 + 32 * rng.below(12))));
        }
    };
    // a bytes expression of known width
    auto gen = [&](auto&& self, int depth) -> Value {
        const i64 n = 1 + i64(rng.below(rng.coin(4) ? 80 : 33));
        switch (depth > 2 ? rng.below(5) : rng.below(7)) {
            case 0: return mk(Op::SIZED, S(n), word());
            case 1: return mk(Op::MEM, R(i64(rng.below(100)), n));
            case 2: return mk(Op::CALLDATA_BYTES, S(i64(rng.below(400))), S(n));
            case 3: {
                std::vector<u8> bytes(static_cast<usize>(n), u8(0));
                for (u8& c : bytes) c = u8(rng.next());
                return n > 32 ? mk_bytes(bytes) : mk(Op::SIZED, S(n), mk_int_be(bytes));
            }
            case 4: return mk(Op::CODE_BYTES, S(i64(rng.below(220))), S(n));
            case 5: {
                SmallVec<Value, 4> parts;
                const int k = 1 + int(rng.below(3));
                for (int i = 0; i < k; ++i) parts.push_back(self(self, depth + 1));
                return mk(Op::DATA, parts.span());
            }
            default: return mk(Op::SIZED, S(n), self(self, depth + 1));
        }
    };
    // memory with something in it
    const Value pre = mk_trace({mk(Op::SETMEM, R(0, 64), V("(calldata_bytes 4 64)")),
                                mk(Op::SETMEM, R(64, 64), V("(calldata_bytes 100 64)"))});
    int checked = 0, sliced = 0, worded = 0;
    for (int round = 0; round < 600; ++round) {
        exec::SimpleHost host = random_host(rng);
        Value b = gen(gen, 0);
        auto bytes = returned(pre, b, host);
        REQUIRE(bytes.has_value());
        const auto w = width_u64(b);
        REQUIRE(w.has_value());
        CHECK(bytes->size() == *w);
        INFO("b: " << D(b));
        // slices
        for (int k = 0; k < 3; ++k) {
            const i64 lo = i64(rng.below(*w + 1)), hi = lo + i64(rng.below(*w - u64(lo) + 1));
            auto s = slice(b, S(lo), S(hi));
            if (!s) continue;
            ++sliced;
            auto got = returned(pre, *s, host);
            INFO("slice [" << lo << ", " << hi << "): " << D(*s));
            REQUIRE(got.has_value());
            CHECK(*got == std::vector<u8>(bytes->begin() + lo, bytes->begin() + hi));
        }
        // sized / resize_bytes: what SIZED(n, b) is
        const i64 n = i64(rng.below(*w + 40));
        Value raw = mk(Op::SIZED, S(n), b);
        Value norm = sized(n, b);
        auto want = returned(pre, raw, host);
        auto have = returned(pre, norm, host);
        INFO("sized " << n << ": " << D(norm));
        REQUIRE(want.has_value());
        REQUIRE(have.has_value());
        CHECK(*want == *have);
        if (auto r = resize_bytes(b, S(n))) {
            auto hr = returned(pre, *r, host);
            INFO("resize_bytes: " << D(*r));
            REQUIRE(hr.has_value());
            CHECK(*want == *hr);
        }
        // concat of it and another one: DATA of both
        Value c = gen(gen, 1);
        Value both[] = {b, c};
        auto wd = returned(pre, mk(Op::DATA, both[0], both[1]), host);
        auto hd = returned(pre, concat(both), host);
        INFO("concat: " << D(concat(both)));
        REQUIRE(wd.has_value());
        REQUIRE(hd.has_value());
        CHECK(*wd == *hd);
        // as a word
        if (*w <= 32) {
            if (auto x = as_word(b)) {
                ++worded;
                auto ww = returned(pre, mk(Op::SIZED, S(32), b), host);
                auto hw = returned(pre, mk(Op::SIZED, S(32), *x), host);
                INFO("as_word: " << D(*x));
                REQUIRE(ww.has_value());
                REQUIRE(hw.has_value());
                CHECK(*ww == *hw);
            }
        }
        ++checked;
    }
    MESSAGE("bytes algebra checked: " << checked << " (slices " << sliced << ", words " << worded << ")");
    CHECK(sliced > 600);
}
