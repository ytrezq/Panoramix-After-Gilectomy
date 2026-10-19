// The trace machine (lot 11, src/exec/machine.hpp): every kind of line and
// expression on hand-made traces, against hand-computed effects.
#include <doctest/doctest.h>

#include <optional>
#include <string>
#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "core/dump.hpp"
#include "core/evmint.hpp"
#include "exec/machine.hpp"

using namespace pan;
using namespace pan::exec;

namespace doctest {
template <>
struct StringMaker<Word256> {
    static String convert(const Word256& w) {
        static constexpr char kHex[] = "0123456789abcdef";
        std::string s = "0x";
        u8 b[32];
        w.to_be(b);
        for (u8 c : b) {
            s += kHex[c >> 4];
            s += kHex[c & 15];
        }
        return s.c_str();
    }
};
}  // namespace doctest

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

using Bytes = std::vector<u8>;

Word256 W(u64 v) { return Word256::of(v); }

Bytes word_bytes(const Word256& w) {
    Bytes b(32);
    w.to_be(b.data());
    return b;
}

Bytes cat(std::initializer_list<Bytes> parts) {
    Bytes out;
    for (const Bytes& p : parts) out.insert(out.end(), p.begin(), p.end());
    return out;
}

Bytes calldata(u32 selector, std::initializer_list<u64> words = {}) {
    Bytes b{u8(selector >> 24), u8(selector >> 16), u8(selector >> 8), u8(selector)};
    for (u64 w : words) {
        Bytes x = word_bytes(W(w));
        b.insert(b.end(), x.begin(), x.end());
    }
    return b;
}

Bytes hex(std::string_view s) {
    Bytes out;
    auto nib = [](char c) -> u8 { return c <= '9' ? u8(c - '0') : u8((c | 0x20) - 'a' + 10); };
    for (usize i = 0; i + 1 < s.size(); i += 2) out.push_back(u8(nib(s[i]) << 4 | nib(s[i + 1])));
    return out;
}

FunctionInfo selector_fn(u32 selector, std::string_view trace, std::vector<ParamInfo> params = {}) {
    FunctionInfo f;
    f.kind = FunctionInfo::Kind::Selector;
    f.selector = selector;
    f.entry.selector = selector;
    f.params = std::move(params);
    f.trace = V(trace);
    return f;
}

FunctionInfo fallback_fn(std::string_view trace) {
    FunctionInfo f;
    f.kind = FunctionInfo::Kind::Fallback;
    f.trace = V(trace);
    return f;
}

FunctionInfo internal_fn(u32 entry, std::string_view trace) {
    FunctionInfo f;
    f.kind = FunctionInfo::Kind::Internal;
    f.entry_pc = entry;
    f.trace = V(trace);
    return f;
}

// one trace run as a selector function's body
Outcome run_trace(std::string_view trace, SimpleHost& host, std::vector<ParamInfo> params = {},
                  MachineLimits limits = {}) {
    std::vector<FunctionInfo> fns{selector_fn(0x11223344, trace, std::move(params))};
    Program p;
    p.functions = fns;
    Machine m(p, limits);
    return m.run(host, fns[0]);
}

Outcome run_trace(std::string_view trace) {
    SimpleHost host;
    return run_trace(trace, host);
}

Bytes returned(std::string_view trace) {
    const Outcome o = run_trace(trace);
    CHECK_MESSAGE(o.status == Status::Return, status_name(o.status), " ", o.note);
    return o.data;
}

Word256 returned_word(std::string_view trace) {
    const Bytes b = returned(trace);
    REQUIRE(b.size() == 32);
    return Word256::from_be(b);
}

}  // namespace

TEST_CASE("exec: keccak256") {
    // keccak256("") and keccak256("abc")
    CHECK(word_bytes(keccak256({})) == hex("c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"));
    const Bytes abc{'a', 'b', 'c'};
    CHECK(word_bytes(keccak256(abc)) == hex("4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"));
    // at the block's boundary (136 bytes) and past it (vectors of eth_hash)
    CHECK(word_bytes(keccak256(Bytes(135, 'a'))) ==
          hex("34367dc248bbd832f4e3e69dfaac2f92638bd0bbd18f2912ba4ef454919cf446"));
    CHECK(word_bytes(keccak256(Bytes(136, 'a'))) ==
          hex("a6c4d403279fe3e0af03729caada8374b5ca54d8065329a3ebcaeb4b60aa386e"));
    CHECK(word_bytes(keccak256(Bytes(200, 'a'))) ==
          hex("96ea54061def936c4be90b518992fdc6f12f535068a256229aca54267b4d084d"));
}

TEST_CASE("exec: words and the pure operations") {
    Fixture fx;
    CHECK(returned_word("{(return (add 1 2))}") == W(3));
    CHECK(returned_word("{(return (add 1 -2))}") == pan::sub(Word256{}, W(1)));
    CHECK(returned_word("{(return (mul 3 4 5))}") == W(60));
    CHECK(returned_word("{(return (div 7 0))}") == W(0));
    CHECK(returned_word("{(return (sized 32 (mask_shl 8 8 -8 0x1234)))}") == W(0x12));
    CHECK(returned_word("{(return (sized 32 (mask_shl 256 0 (mask_shl 8 0 0 3) 1)))}") == W(8));  // 1 << 3, shl an expression
    CHECK(returned_word("{(return (bool 7))}") == W(1));
    CHECK(returned_word("{(return (le 3 3))}") == W(1));
    CHECK(returned_word("{(return (sge -1 0))}") == W(0));
    CHECK(returned_word("{(return (max 3 9 4))}") == W(9));
    CHECK(returned_word("{(return (min 3 9 4))}") == W(3));
    CHECK(returned_word("{(return (iszero 0))}") == W(1));
    CHECK(returned_word("{(return (byte 31 0x1234))}") == W(0x34));
    CHECK(returned_word("{(return (shl 4 1))}") == W(16));
    CHECK(returned_word("{(return True)}") == W(1));
    CHECK(returned_word("{(return (mask 8 8 0x1234))}") == W(0x12));
    // LAND / LOR: python's and/or, short-circuited (tmp9 is never set)
    CHECK(returned_word("{(return (land 0 tmp9))}") == W(0));
    CHECK(returned_word("{(return (land 5 7))}") == W(7));
    CHECK(returned_word("{(return (lor 5 tmp9))}") == W(5));
    CHECK(returned_word("{(return (lor 0 7))}") == W(7));
    CHECK(returned_word("{(return (fand 1 2 3))}") == W(1));
    CHECK(returned_word("{(return (for 0 0))}") == W(0));
    // sha3 of a word: keccak of its 32 bytes
    CHECK(returned_word("{(return (sha3 11))}") == keccak256(word_bytes(W(11))));
    CHECK(returned_word("{(return (sha3 (sized 3 0x616263)))}") == keccak256(Bytes{'a', 'b', 'c'}));
}

TEST_CASE("exec: the context, calldata and params") {
    Fixture fx;
    SimpleHost host;
    host.call_env.caller = W(0xca11e5);
    host.call_env.callvalue = W(7);
    host.call_env.address = W(0xc0de);
    host.balances[W(0xc0de)] = W(1000);
    host.calldata = calldata(0x11223344, {0x55, 0x66});
    host.code = {0x60, 0x00, 0x00};

    auto word = [&](std::string_view trace, std::vector<ParamInfo> params = {}) {
        const Outcome o = run_trace(trace, host, std::move(params));
        REQUIRE_MESSAGE(o.status == Status::Return, status_name(o.status), " ", o.note);
        return Word256::from_be(o.data);
    };
    CHECK(word("{(return caller)}") == W(0xca11e5));
    CHECK(word("{(return callvalue)}") == W(7));
    CHECK(word("{(return calldatasize)}") == W(68));
    CHECK(word("{(return codesize)}") == W(3));
    CHECK(word("{(return selfbalance)}") == W(1000));
    CHECK(word("{(return (balance 0xc0de))}") == W(1000));
    CHECK(word("{(return (calldataload 4))}") == W(0x55));
    CHECK(word("{(return (calldataload 36))}") == W(0x66));
    CHECK(word("{(return (calldataload 68))}") == W(0));
    CHECK(word("{(return (calldataload 0x10000000000000000))}") == W(0));
    // the selector word
    CHECK(word("{(return (mask_shl 32 224 -224 (calldataload 0)))}") == W(0x11223344));
    // params: the raw word at their offset
    const auto at = [](u32 offset) {
        ParamInfo p;
        p.calldata_offset = offset;
        return p;
    };
    CHECK(word("{(return param1)}", {at(4), at(36)}) == W(0x66));
    // a byte range of the calldata, zero padded
    const Outcome o = run_trace("{(return (calldata_bytes 60 12))}", host);
    CHECK(o.data == Bytes{0, 0, 0, 0, 0, 0, 0, 0x66, 0, 0, 0, 0});
    const Outcome code = run_trace("{(return (code_bytes 1 4))}", host);
    CHECK(code.data == Bytes{0x00, 0x00, 0, 0});
    // a param without its ParamInfo: the stage's bug
    CHECK(run_trace("{(return param3)}", host).status == Status::Bug);
}

TEST_CASE("exec: byte strings: widths, sized, data, arr") {
    Fixture fx;
    // a word: 32 bytes
    CHECK(returned("{(return 5)}") == word_bytes(W(5)));
    // a mask is as wide as it is written: address(x) is 20 bytes
    CHECK(returned("{(return (data (mask_shl 160 0 0 -1) (sized 1 7)))}") == cat({Bytes(20, 0xff), Bytes{7}}));
    CHECK(returned("{(return (data (mask_shl 8 248 -248 0x1100000000000000000000000000000000000000000000000000000000000000)))}") ==
          Bytes{0x11});
    // sized: the low n bytes, zeroes before when it has fewer
    CHECK(returned("{(return (sized 2 0x112233))}") == Bytes{0x22, 0x33});
    CHECK(returned("{(return (sized 34 1))}") == cat({Bytes(33, 0), Bytes{1}}));
    // sized of bytes of another length: resized (zeroes before, or the last n)
    CHECK(returned("{(setmem (range 0 32) 0x01020304) (return (sized 2 (mem (range 28 4))))}") == Bytes{3, 4});
    CHECK(returned("{(setmem (range 0 32) 0x01020304) (return (sized 6 (mem (range 28 4))))}") ==
          Bytes{0, 0, 1, 2, 3, 4});
    // a sized value as a word: its low n bytes
    CHECK(returned_word("{(return (add 0 (sized 1 0x1234)))}") == W(0x34));
    // an arr in a data: its offset, then its length and its content padded
    CHECK(returned("{(return (data (arr 3 (sized 3 0x616263))))}") ==
          cat({word_bytes(W(32)), word_bytes(W(3)), Bytes{'a', 'b', 'c'}, Bytes(29, 0)}));
    // heads first, tails after: (uint 7, bytes "ab", uint 9)
    CHECK(returned("{(return (data 7 (arr 2 (sized 2 0x6162)) 9))}") ==
          cat({word_bytes(W(7)), word_bytes(W(96)), word_bytes(W(9)), word_bytes(W(2)), Bytes{'a', 'b'}, Bytes(30, 0)}));
    // an arr's offset counts from the start of its data (python runtrace.evb):
    // after a 4-byte prefix, 36
    const Outcome err = run_trace("{(revert (data (sized 4 0x08c379a0) (arr 1 (sized 1 0x78))))}");
    CHECK(err.status == Status::Revert);
    CHECK(err.data == cat({Bytes{0x08, 0xc3, 0x79, 0xa0}, word_bytes(W(36)), word_bytes(W(1)), Bytes{'x'}, Bytes(31, 0)}));
    // a bare arr: a data of it
    CHECK(returned("{(return (arr 0))}") == cat({word_bytes(W(32)), word_bytes(W(0))}));
    // a constant of more than 256 bits: its bytes
    CHECK(returned("{(return 0x0102030405060708091011121314151617181920212223242526272829303132333435)}") ==
          hex("0102030405060708091011121314151617181920212223242526272829303132333435"));
    // a BYTES node (a codecopy of known code): its bytes
    CHECK(returned("{(return b\"abc\")}") == Bytes{'a', 'b', 'c'});
    // None: nothing
    const Outcome r = run_trace("{(revert None)}");
    CHECK(r.status == Status::Revert);
    CHECK(r.data.empty());
}

TEST_CASE("exec: masks of byte strings wider than a word") {
    Fixture fx;
    const Word256 A = pan::sub(Word256{}, W(0x1234));  // the first 32 bytes
    const Word256 B = W(0xabcdef);                      // the next 32
    auto word = [&](std::string_view e) {
        std::string t = "{(setmem (range 0 32) (sub 0 0x1234)) (setmem (range 32 32) 0xabcdef) (return (sized 32 ";
        t += e;
        t += "))}";
        return returned_word(t);
    };
    // the high word, the low word, a field across both, at another place
    CHECK(word("(mask_shl 256 256 -256 (mem (range 0 64)))") == A);
    CHECK(word("(mask_shl 256 0 0 (mem (range 0 64)))") == B);
    CHECK(word("(mask_shl 64 224 -192 (mem (range 0 64)))") ==
          pan::shl(W(32), pan::bor(pan::shl(W(32), pan::band(A, W(0xffffffff))), pan::shr(W(224), B))));
    CHECK(word("(mask_shl 8 504 -504 (mem (range 0 64)))") == W(0xff));
    // past the string: nothing; a shift out of the word: nothing
    CHECK(word("(mask_shl 8 512 -512 (mem (range 0 64)))") == W(0));
    CHECK(word("(mask_shl 8 256 0 (mem (range 0 64)))") == W(0));
    // the print form
    // (bits 248..263 of the 512: B's top byte 0x00 below A's low byte 0xcc)
    CHECK(word("(mask 16 248 (mem (range 0 64)))") == W(0xcc00));
    CHECK(word("(mask 16 256 (mem (range 0 64)))") == W(0xedcc));
    // 32 bytes or fewer: a word, as eval_op has it
    CHECK(word("(mask_shl 8 0 0 (mem (range 0 1)))") == W(0xff));
}

TEST_CASE("exec: byte elements without SIZED are counted") {
    Fixture fx;
    Outcome o = run_trace("{(return (data (mask_shl 160 0 0 caller) (sized 1 7) 5))}");
    CHECK(o.status == Status::Return);
    CHECK(o.unsized == 2);
    CHECK(dump(o.unsized_element) == "(mask_shl 160 0 0 caller)");
    CHECK(dump(o.unsized_line) == "(return (data (mask_shl 160 0 0 caller) (sized 1 7) 5))");
    // a long constant: unsized alone, sized in a SIZED or a SETMEM (its low n bytes)
    o = run_trace("{(return 0x0102030405060708091011121314151617181920212223242526272829303132333435)}");
    CHECK(o.unsized == 1);
    o = run_trace("{(setmem (range 0 2) 0x0102030405060708091011121314151617181920212223242526272829303132333435)"
                  " (return (sized 3 0x0102030405060708091011121314151617181920212223242526272829303132333435))}");
    CHECK(o.unsized == 0);
    CHECK(o.data == Bytes{0x33, 0x34, 0x35});
    o = run_trace("{(setmem (range 0 2) 0x0102030405060708091011121314151617181920212223242526272829303132333435)"
                  " (return (mem (range 0 2)))}");
    CHECK(o.data == Bytes{0x34, 0x35});
    // explicit widths, a word in a SETMEM (the range is its width), bytes: none
    o = run_trace("{(setmem (range 0 32) 5) (log1 (data (sized 32 1) (mem (range 0 3)) b\"ab\") 7)"
                  " (return (sized 32 (sha3 (sized 32 11))))}");
    CHECK(o.status == Status::Return);
    CHECK(o.unsized == 0);
    CHECK(o.unsized_element.nil());
}

TEST_CASE("exec: memory") {
    Fixture fx;
    CHECK(returned("{(setmem (range 64 32) 128) (return (mem (range 64 32)))}") == word_bytes(W(128)));
    // a word's low n bytes (mstore8)
    CHECK(returned("{(setmem (range 0 1) 0x1234) (return (mem (range 0 2)))}") == Bytes{0x34, 0});
    // zero extended, msize word rounded over every access
    CHECK(returned_word("{(setmem (range 0 1) 1) (return msize)}") == W(32));
    CHECK(returned_word("{(setvar tmp1 (mem (range 100 1))) (return msize)}") == W(128));
    CHECK(returned("{(return (mem (range 1000 3)))}") == Bytes{0, 0, 0});
    // a word read of the memory
    CHECK(returned_word("{(setmem (range 0 32) 0xabcd) (return (add 0 (mem (range 30 2))))}") == W(0xabcd));
    // copies: calldata, memory, a bytes node of n bytes
    CHECK(returned("{(setmem (range 0 3) b\"xyz\") (return (mem (range 0 3)))}") == Bytes{'x', 'y', 'z'});
    CHECK(returned("{(setmem (range 0 4) (mem (range 28 4))) (return (mem (range 0 4)))}") == Bytes{0, 0, 0, 0});
    // a write of more than 32 bytes of a word: zeroes, then the word
    CHECK(returned("{(setmem (range 0 33) 5) (return (mem (range 0 33)))}") == cat({Bytes(32, 0), Bytes{5}}));
    // bytes of another size than the range: the stage's bug
    CHECK(run_trace("{(setmem (range 0 4) b\"xyz\")}").status == Status::Bug);
    // past the memory limit: exhausted
    SimpleHost host;
    MachineLimits small;
    small.memory_max = 1024;
    CHECK(run_trace("{(setmem (range 2000 32) 1)}", host, {}, small).status == Status::Exhausted);
    CHECK(run_trace("{(return (mem (range 0x10000000000000000 32)))}", host).status == Status::Exhausted);
}

TEST_CASE("exec: variables, the memo of expressions") {
    Fixture fx;
    CHECK(returned_word("{(setvar tmp1 4) (setvar tmp2 (mul tmp1 tmp1)) (return tmp2)}") == W(16));
    // the same expression after its variable changed
    CHECK(returned_word("{(setvar tmp1 1) (setvar tmp2 (add tmp1 1)) (setvar tmp1 5) (setvar tmp2 (add tmp1 1)) "
                        "(return tmp2)}") == W(6));
    // the same read of the memory after a write
    CHECK(returned_word("{(setvar tmp1 (mem (range 0 32))) (setmem (range 0 32) 9) (setvar tmp2 (mem (range 0 32))) "
                        "(return (add tmp1 tmp2))}") == W(9));
    // a variable never set: the stage's bug, with the line
    const Outcome o = run_trace("{(setvar tmp1 1) (return tmp2)}");
    CHECK(o.status == Status::Bug);
    CHECK(o.note.find("tmp2") != std::string::npos);
    CHECK(dump(o.line) == "(return tmp2)");
    CHECK(returned_word("{(setvar _msize 3) (setvar prec_1_0 4) (return (add _msize prec_1_0))}") == W(7));
}

TEST_CASE("exec: if, halts") {
    Fixture fx;
    CHECK(returned_word("{(if (lt 1 2) {(return 1)} {(return 2)})}") == W(1));
    CHECK(returned_word("{(if (gt 1 2) {(return 1)} {(return 2)})}") == W(2));
    // a branch that doesn't halt goes on after its if
    CHECK(returned_word("{(setvar tmp1 0) (if 1 {(setvar tmp1 5)} {}) (return tmp1)}") == W(5));
    CHECK(returned_word("{(merged_if 0 {(return 1)} {(return 2)})}") == W(2));
    CHECK(run_trace("{(setvar tmp1 1)}").status == Status::Stop);
    CHECK(run_trace("{(stop)}").status == Status::Stop);
    const Outcome inv = run_trace("{(invalid 3 77)}");
    CHECK(inv.status == Status::Invalid);
    CHECK(inv.reason == 3);
    CHECK(run_trace("{(undefined 1 99)}").status == Status::Undefined);
    // require(cond[, data]) and assert
    CHECK(returned_word("{(require 1) (return 3)}") == W(3));
    const Outcome req = run_trace("{(require 0) (return 3)}");
    CHECK(req.status == Status::Revert);
    CHECK(req.data.empty());
    const Outcome req2 = run_trace("{(require 0 (sized 2 0x4142)) (return 3)}");
    CHECK(req2.status == Status::Revert);
    CHECK(req2.data == Bytes{0x41, 0x42});
    CHECK(run_trace("{(assert 0)}").status == Status::Invalid);
    CHECK(run_trace("{(asm 1 96 5 []) (return 1)}").status == Status::Return);
    // not a line
    CHECK(run_trace("{(add 1 2)}").status == Status::Bug);
}

TEST_CASE("exec: loops: while, continue, break, label/goto") {
    Fixture fx;
    // sum of 0..9
    CHECK(returned_word("{(setvar tmp1 0)"
                        " (while (lt loop1 10) {(setvar tmp1 (add tmp1 loop1)) (continue loopid1 {(setvar loop1 (add loop1 1))})}"
                        "  loopid1 {(setvar loop1 0)})"
                        " (return tmp1)}") == W(45));
    // a loop variable read after the loop: its last value
    CHECK(returned_word("{(while (lt loop1 7) {(continue loopid1 {(setvar loop1 (add loop1 1))})} loopid1 {(setvar loop1 0)})"
                        " (return loop1)}") == W(7));
    // a body that ends without continue leaves the loop
    CHECK(returned_word("{(setvar tmp1 0) (while 1 {(setvar tmp1 (add tmp1 1))} loopid1 {}) (return tmp1)}") == W(1));
    // setvars all at once: a swap (fibonacci)
    CHECK(returned_word("{(while (lt loop3 10)"
                        "  {(continue loopid1 {(setvar loop1 loop2) (setvar loop2 (add loop1 loop2)) (setvar loop3 (add loop3 1))})}"
                        "  loopid1 {(setvar loop1 0) (setvar loop2 1) (setvar loop3 0)})"
                        " (return loop1)}") == W(55));
    // break, and a continue of the outer loop from the inner one
    CHECK(returned_word("{(while 1 {(if (eq loop1 4) {(break loopid1)} {}) (continue loopid1 {(setvar loop1 (add loop1 1))})}"
                        "  loopid1 {(setvar loop1 0)}) (return loop1)}") == W(4));
    CHECK(returned_word("{(setvar tmp1 0)"
                        " (while (lt loop1 3)"
                        "  {(while 1 {(setvar tmp1 (add tmp1 1)) (continue loopid1 {(setvar loop1 (add loop1 1))})} loopid2 {})}"
                        "  loopid1 {(setvar loop1 0)})"
                        " (return tmp1)}") == W(3));
    // raw: label / goto
    CHECK(returned_word("{(label loopid1 {(setvar loop1 0)})"
                        " (if (lt loop1 5) {(goto loopid1 {(setvar loop1 (add loop1 1))})} {(return loop1)})}") == W(5));
    // nested labels
    CHECK(returned_word("{(setvar tmp1 0) (label loopid1 {(setvar loop1 0)})"
                        " (if (lt loop1 3)"
                        "   {(label loopid2 {(setvar loop2 0)})"
                        "    (if (lt loop2 2) {(setvar tmp1 (add tmp1 1)) (goto loopid2 {(setvar loop2 (add loop2 1))})}"
                        "                     {(goto loopid1 {(setvar loop1 (add loop1 1))})})}"
                        "   {(return tmp1)})}") == W(6));
    // a goto without its label, a continue out of its loop: bugs
    CHECK(run_trace("{(goto loopid9 {})}").status == Status::Bug);
    CHECK(run_trace("{(continue loopid9 {})}").status == Status::Bug);
    // an endless loop: exhausted
    SimpleHost host;
    MachineLimits l;
    l.steps = 1000;
    const Outcome o = run_trace("{(while 1 {(continue loopid1 {})} loopid1 {})}", host, {}, l);
    CHECK(o.status == Status::Exhausted);
    CHECK(o.steps > 1000);
}

TEST_CASE("exec: storage before the P forms") {
    Fixture fx;
    SimpleHost host;
    host.storage[W(5)] = W(0x1122);
    // reads: the size bits at off; a negative off moves them left
    auto word = [&](std::string_view trace) {
        const Outcome o = run_trace(trace, host);
        REQUIRE_MESSAGE(o.status == Status::Return, status_name(o.status), " ", o.note);
        return Word256::from_be(o.data);
    };
    CHECK(word("{(return (storage 256 0 5))}") == W(0x1122));
    CHECK(word("{(return (sized 32 (storage 8 8 5)))}") == W(0x11));
    CHECK(word("{(return (sized 32 (storage 8 -8 5)))}") == W(0x2200));
    // unsized, as wide as written: STORAGE(8, ...) is one byte
    CHECK(run_trace("{(return (storage 8 8 5))}", host).data == Bytes{0x11});
    // a whole write, a write of a field (read-modify-write)
    host.effects.clear();
    CHECK(run_trace("{(store 256 0 7 42) (store 8 8 5 0xff)}", host).status == Status::Stop);
    CHECK(host.storage[W(7)] == W(42));
    CHECK(host.storage[W(5)] == W(0xff22));
    REQUIRE(host.effects.size() == 2);
    CHECK(std::get<SimpleHost::Sstore>(host.effects[1]).value == W(0xff22));
    // a field write of a value wider than the field: its low bits only
    CHECK(run_trace("{(store 4 0 5 0x1234)}", host).status == Status::Stop);
    CHECK(host.storage[W(5)] == W(0xff24));
    // solidity's bytes: a short one (length 3: 2 * 3 in the low byte)
    host.storage[W(9)] = pan::bor(pan::shl(W(232), W(0x616263)), W(6));
    CHECK(word("{(return (length 9))}") == W(3));
    CHECK(word("{(return (storage 256 0 (length 9)))}") == W(3));
    Outcome o = run_trace("{(return (data (arr (storage 256 0 (length 9)) (sbytes 9))))}", host);
    CHECK(o.data == cat({word_bytes(W(32)), word_bytes(W(3)), Bytes{'a', 'b', 'c'}, Bytes(29, 0)}));
    // a long one: length 40, 2 * 40 + 1 at the slot, the words from keccak(slot)
    host.storage[W(10)] = W(81);
    const Word256 base = keccak256(word_bytes(W(10)));
    host.storage[base] = Word256::from_be(Bytes(32, 'x'));
    host.storage[pan::add(base, W(1))] = Word256::from_be(cat({Bytes(8, 'y'), Bytes(24, 0)}));
    CHECK(word("{(return (length 10))}") == W(40));
    o = run_trace("{(return (sbytes 10))}", host);
    CHECK(o.data == cat({Bytes(32, 'x'), Bytes(8, 'y')}));
    // a short encoding with more than a word's length (no solc makes it: a
    // random world's word): the word, then zeroes
    host.storage[W(11)] = pan::bor(pan::shl(W(248), W(0x61)), W(200));
    o = run_trace("{(return (sbytes 11))}", host);
    REQUIRE(o.data.size() == 100);
    CHECK(o.data[0] == 0x61);
    CHECK(o.data[31] == 200);
    CHECK(o.data[99] == 0);
    // the P forms need lot 9's layout
    CHECK(run_trace("{(return (st 256 (sr 5) 256))}", host).status == Status::Unsupported);
}

TEST_CASE("exec: transient storage, logs, selfdestruct") {
    Fixture fx;
    SimpleHost host;
    CHECK(run_trace("{(tstore 1 2) (log2 (sized 2 0xbeef) 0xdd 5) (log0 None) (return (tload 1))}", host).status ==
          Status::Return);
    REQUIRE(host.effects.size() == 3);
    CHECK(std::get<SimpleHost::Tstore>(host.effects[0]) == SimpleHost::Tstore{W(1), W(2)});
    const auto& log = std::get<SimpleHost::Log>(host.effects[1]);
    CHECK(log.topics == std::vector<Word256>{W(0xdd), W(5)});
    CHECK(log.data == Bytes{0xbe, 0xef});
    CHECK(std::get<SimpleHost::Log>(host.effects[2]).data.empty());
    host.effects.clear();
    const Outcome o = run_trace("{(selfdestruct caller) (return 1)}", host);
    CHECK(o.status == Status::Stop);
    REQUIRE(host.effects.size() == 1);
    CHECK(std::holds_alternative<SimpleHost::SelfDestruct>(host.effects[0]));
}

TEST_CASE("exec: numbered calls and their records") {
    Fixture fx;
    SimpleHost host;
    host.call_answer = CallResult{true, hex("00000000000000000000000000000000000000000000000000000000000000aa0102")};
    const Outcome o = run_trace(
        "{(call 1 gas 0xdead 5 (sized 4 0xa9059cbb) (data 1 2))"
        " (setmem (range 0 (min 64 (returndatasize 1))) (returndata_bytes 1 0 (min 64 (returndatasize 1))))"
        " (return (data (call_success 1) (returndatasize 1) (mem (range 0 64)) (returndata_bytes 1 32 4)))}",
        host);
    REQUIRE_MESSAGE(o.status == Status::Return, o.note);
    REQUIRE(host.effects.size() == 1);
    const auto& c = std::get<SimpleHost::Call>(host.effects[0]);
    CHECK(c.kind == CallKind::Call);
    CHECK(c.target == W(0xdead));
    CHECK(c.value == W(5));
    CHECK(c.input == cat({Bytes{0xa9, 0x05, 0x9c, 0xbb}, word_bytes(W(1)), word_bytes(W(2))}));
    // the return data zero padded past its end (34 bytes)
    CHECK(o.data == cat({word_bytes(W(1)), word_bytes(W(34)), word_bytes(W(0xaa)), Bytes{1, 2}, Bytes(30, 0),
                         Bytes{1, 2, 0, 0}}));
    // no call yet: returndatasize 0; a record never written: the stage's bug
    CHECK(returned_word("{(return (returndatasize 0))}") == W(0));
    CHECK(run_trace("{(return (call_success 2))}").status == Status::Bug);
    // staticcall / delegatecall: no value; a failed call
    host.effects.clear();
    host.call_answer = CallResult{false, {}};
    const Outcome s = run_trace("{(staticcall 1 gas 0xbeef None (sized 1 9)) (delegatecall 2 gas 0xbeef None None)"
                                " (return (add (call_success 1) (call_success 2)))}",
                                host);
    CHECK(Word256::from_be(s.data) == W(0));
    REQUIRE(host.effects.size() == 2);
    CHECK(std::get<SimpleHost::Call>(host.effects[0]).kind == CallKind::StaticCall);
    CHECK(std::get<SimpleHost::Call>(host.effects[0]).input == Bytes{9});
    CHECK(std::get<SimpleHost::Call>(host.effects[1]).kind == CallKind::DelegateCall);
    // a call in a loop: its record is the last run's
    host.effects.clear();
    host.call_answer = CallResult{true, Bytes(5, 1)};
    const Outcome loop = run_trace("{(while (lt loop1 3) {(call 1 gas loop1 0 None None) (continue loopid1 {(setvar loop1 (add loop1 1))})}"
                                   " loopid1 {(setvar loop1 0)}) (return (returndatasize 1))}",
                                   host);
    CHECK(Word256::from_be(loop.data) == W(5));
    CHECK(host.effects.size() == 3);
}

TEST_CASE("exec: creations, precompiles") {
    Fixture fx;
    SimpleHost host;
    Outcome o = run_trace("{(create 1 0 (sized 2 0x6000)) (create2 2 7 (sized 1 0) 99)"
                          " (return (data (create_address 1) (create_address 2) (returndatasize 2)))}",
                          host);
    REQUIRE(o.status == Status::Return);
    CHECK(o.data == cat({word_bytes(W(0)), word_bytes(W(0)), word_bytes(W(0))}));
    REQUIRE(host.effects.size() == 2);
    CHECK(std::get<SimpleHost::Create>(host.effects[1]).salt == W(99));
    CHECK(std::get<SimpleHost::Create>(host.effects[1]).value == W(7));
    // a precompile: a staticcall of its address; its name the output's first word
    host.effects.clear();
    host.call_answer = CallResult{true, word_bytes(W(0x5151))};
    o = run_trace("{(precompiled 1 prec_2_0 2 (sized 3 0x616263)) (return (add prec_2_0 (call_success 1)))}", host);
    CHECK(Word256::from_be(o.data) == W(0x5152));
    REQUIRE(host.effects.size() == 1);
    CHECK(std::get<SimpleHost::Call>(host.effects[0]).kind == CallKind::StaticCall);
    CHECK(std::get<SimpleHost::Call>(host.effects[0]).target == W(2));
}

TEST_CASE("exec: internal functions") {
    Fixture fx;
    std::vector<FunctionInfo> internals{
        internal_fn(100, "{(leave [(add param0 param1)])}"),
        // factorial, recursive
        internal_fn(200, "{(if (iszero param0) {(leave [1])} {(internal 200 [(add param0 -1)] [tmp1]) (leave [(mul param0 tmp1)])})}"),
        // its own variables: tmp1 here is not the caller's
        internal_fn(300, "{(setvar tmp1 77) (leave [tmp1 param0])}"),
        // a halt in an internal function ends the call
        internal_fn(400, "{(revert None)}"),
    };
    std::vector<FunctionInfo> fns{
        selector_fn(1, "{(internal 100 [3 4] [tmp7]) (return tmp7)}"),
        selector_fn(2, "{(internal 200 [5] [tmp1]) (return tmp1)}"),
        selector_fn(3, "{(setvar tmp1 5) (internal 300 [9] [tmp2 tmp3]) (return (data tmp1 tmp2 tmp3))}"),
        selector_fn(4, "{(internal 400 [] []) (return 1)}"),
        selector_fn(5, "{(internal 999 [] []) (return 1)}"),
        selector_fn(6, "{(internal 100 [3 4] [tmp1 tmp2]) (return 1)}"),
        selector_fn(7, "{(leave [])}"),
    };
    Program p;
    p.functions = fns;
    p.internals = internals;
    Machine m(p);
    SimpleHost host;
    auto call = [&](u32 sel) {
        host.calldata = calldata(sel);
        return m.call(host);
    };
    CHECK(Word256::from_be(call(1).data) == W(7));
    CHECK(Word256::from_be(call(2).data) == W(120));
    CHECK(call(3).data == cat({word_bytes(W(5)), word_bytes(W(77)), word_bytes(W(9))}));
    CHECK(call(4).status == Status::Revert);
    CHECK(call(5).status == Status::Unsupported);  // not given
    CHECK(call(6).status == Status::Bug);          // 2 results, 1 value
    CHECK(call(7).status == Status::Bug);          // a leave out of an internal function
    // too deep
    MachineLimits l;
    l.depth_max = 3;
    m.set_limits(l);
    CHECK(call(2).status == Status::Exhausted);
}

TEST_CASE("exec: dispatch, entry lines, nonpayable") {
    Fixture fx;
    std::vector<FunctionInfo> fns{
        selector_fn(0xaabbccdd, "{(return 1)}"),
        selector_fn(0x00000000, "{(return 0)}"),
        selector_fn(0x11223344, "{(return (mem (range 64 32)))}"),
        fallback_fn("{(return 2)}"),
    };
    // the dispatcher's lines on the path: a setmem, a check whose other branch halts
    fns[2].entry.entry_lines = V("{(setmem (range 64 32) 128) (if (lt calldatasize 36) {(revert None)} {})}");
    fns[0].entry.nonpayable = true;
    fns[1].entry.nonpayable = true;
    fns[1].entry.value_fails = V("(invalid 1 5)");
    Program p;
    p.functions = fns;
    Machine m(p);
    SimpleHost host;
    auto call = [&](Bytes cd, u64 value = 0) {
        host.calldata = std::move(cd);
        host.call_env.callvalue = W(value);
        return m.call(host);
    };
    Outcome o = call(calldata(0xaabbccdd));
    CHECK(Word256::from_be(o.data) == W(1));
    CHECK(o.function == std::optional<usize>(0));
    o = call(calldata(0x11223344, {1}));
    CHECK(o.data == word_bytes(W(128)));
    CHECK(call(calldata(0x11223344)).status == Status::Revert);  // the entry check
    CHECK(Word256::from_be(call(calldata(0x99999999)).data) == W(2));
    CHECK(Word256::from_be(call(Bytes{}).data) == W(2));      // short calldata: the fallback
    CHECK(Word256::from_be(call(Bytes{0, 0, 0}).data) == W(2));
    CHECK(Word256::from_be(call(Bytes{0, 0, 0, 0}).data) == W(0));
    // nonpayable: with a value, its value-fails line (none: a revert of no data)
    CHECK(call(calldata(0xaabbccdd), 5).status == Status::Revert);
    CHECK(call(Bytes{0, 0, 0, 0}, 5).status == Status::Invalid);
    CHECK(Word256::from_be(call(calldata(0x11223344, {1}), 5).data) == W(128));  // payable
    // no fallback: unsupported
    std::vector<FunctionInfo> one{selector_fn(1, "{(stop)}")};
    Program q;
    q.functions = one;
    Machine n(q);
    host.calldata = calldata(2);
    CHECK(n.call(host).status == Status::Unsupported);
    // a function that failed to decompile
    one[0].problem = 0;
    host.calldata = calldata(1);
    CHECK(n.call(host).status == Status::Unsupported);
}

TEST_CASE("exec: limits on byte strings") {
    Fixture fx;
    SimpleHost host;
    MachineLimits l;
    l.bytes_max = 1000;
    CHECK(run_trace("{(return (calldata_bytes 0 2000))}", host, {}, l).status == Status::Exhausted);
    CHECK(run_trace("{(return (sized 0x10000000000000000 1))}", host, {}, l).status == Status::Exhausted);
    l.bytes_max = limits::RT_BYTES_MAX;
    l.work_max = 4096;
    CHECK(run_trace("{(while 1 {(setvar tmp1 (sha3 (calldata_bytes 0 100))) (continue loopid1 {})} loopid1 {})}", host,
                    {}, l)
              .status == Status::Exhausted);
    // a word read of more than 32 bytes: the stage's bug
    CHECK(run_trace("{(return (add 1 (mem (range 0 33))))}").status == Status::Bug);
    // a field of a byte string that isn't whole bytes: unsupported
    CHECK(run_trace("{(return (data (mask_shl 1 0 0 1)))}").status == Status::Unsupported);
}

// python runtrace's case (tests/test_runtrace.py): solc's getter of a bytes
// of the storage, and storage.bytes_tail's `return Array(len=b.length,
// data=b[all])` - the same bytes for short and long contents (lot 9's check)
TEST_CASE("exec: python runtrace's bytes getter and its tail") {
    Fixture fx;
    const char* getter =
        "{(setvar tmp1 (storage 256 0 5))"
        " (if (iszero (and tmp1 1)) {(setvar tmp2 (div (and tmp1 255) 2))} {(setvar tmp2 (div (add tmp1 -1) 2))})"
        " (setmem (range 128 32) 32)"
        " (setmem (range 160 32) tmp2)"
        " (if (gt tmp2 31)"
        "  {(while (lt (mul 32 loop1) tmp2)"
        "    {(setmem (range (add 192 (mul 32 loop1)) 32) (storage 256 0 (add (sha3 5) loop1)))"
        "     (continue loopid1 {(setvar loop1 (add loop1 1))})}"
        "    loopid1 {(setvar loop1 0)})}"
        "  {(setmem (range 192 32) (and tmp1 (not 255)))})"
        " (return (mem (range 128 (add 64 (mul 32 (div (add tmp2 31) 32))))))}";
    const char* tail = "{(return (data (arr (storage 256 0 (length 5)) (sbytes 5))))}";
    for (usize len : {0, 1, 2, 30, 31, 32, 33, 63, 64, 65, 100, 300}) {
        Bytes content(len);
        for (usize i = 0; i < len; ++i) content[i] = u8(1 + (i * 7) % 255);
        SimpleHost host;
        // storage.bytes_tail's words of the bytes at slot 5
        Bytes padded = content;
        padded.resize((len + 31) / 32 * 32, 0);
        if (len < 32) {
            Bytes w = padded;
            w.resize(32, 0);
            host.storage[W(5)] = pan::bor(Word256::from_be(w), W(2 * len));
        } else {
            host.storage[W(5)] = W(2 * len + 1);
            const Word256 base = keccak256(word_bytes(W(5)));
            for (usize i = 0; i * 32 < padded.size(); ++i)
                host.storage[pan::add(base, W(i))] =
                    Word256::from_be(std::span<const u8>(padded.data() + 32 * i, 32));
        }
        const Bytes expected = cat({word_bytes(W(32)), word_bytes(W(len)), padded});
        const Outcome g = run_trace(getter, host);
        const Outcome t = run_trace(tail, host);
        INFO("length ", len, ": ", g.note, t.note);
        CHECK(g.status == Status::Return);
        CHECK(t.status == Status::Return);
        CHECK(g.data == expected);
        CHECK(t.data == expected);
    }
}

TEST_CASE("exec: machine reuse") {
    Fixture fx;
    std::vector<FunctionInfo> fns{
        selector_fn(1, "{(setmem (range 0 32) (add (mem (range 0 32)) 1)) (setvar tmp1 (add (calldataload 4) 1))"
                       " (return (data (mem (range 0 32)) tmp1))}"),
    };
    Program p;
    p.functions = fns;
    Machine m(p);
    SimpleHost host;
    for (u64 i = 0; i < 3; ++i) {
        host.calldata = calldata(1, {i});
        const Outcome o = m.call(host);
        CHECK(o.data == cat({word_bytes(W(1)), word_bytes(W(i + 1))}));  // fresh memory each run
    }
}
