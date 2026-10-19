// Lot 5 (the symbolic VM): hand-made bytecode -> raw traces.
#include <doctest/doctest.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "core/dump.hpp"
#include "evm/decoder.hpp"
#include "vm/vm.hpp"

using namespace pan;

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

std::vector<u8> unhex(std::string_view s) {
    std::vector<u8> out;
    auto nib = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    };
    int hi = -1;
    for (char c : s) {
        int v = nib(c);
        if (v < 0) continue;
        if (hi < 0) {
            hi = v;
        } else {
            out.push_back(u8(hi << 4 | v));
            hi = -1;
        }
    }
    return out;
}

// a contract of its own code (fmp off unless asked)
struct Code {
    std::vector<u8> bytes;
    CodeMap map;
    ContractShared shared;
    explicit Code(std::string_view hex, bool fmp = false) : bytes(unhex(hex)), map(analyse(bytes)) {
        shared.code = bytes;
        shared.map = &map;
        shared.free_memory_pointer = fmp;
    }
};

// the raw trace of the code from pc 0 (an entry not known)
vm::VmResult run_at(const Code& c, u32 pc = 0, const vm::VmOptions& o = {}) {
    FunctionInfo f;
    f.kind = FunctionInfo::Kind::Fallback;
    f.entry_pc = pc;
    return vm::run_function(c.shared, f, o);
}

}  // namespace

TEST_CASE("vm: straight line") {
    Fixture fx;
    // PUSH1 1 PUSH1 2 ADD PUSH1 0 MSTORE PUSH1 32 PUSH1 0 RETURN
    Code c("600160020160005260206000f3");
    auto r = run_at(c);
    INFO(dump_trace(r.trace));
    CHECK(r.complete);
    CHECK(r.trace == V("{(setmem (range 0 32) (sized 32 3)) (return (mem (range 0 32)))}"));
}

TEST_CASE("vm: if") {
    Fixture fx;
    // PUSH1 0 CALLDATALOAD PUSH1 11 JUMPI PUSH1 0 PUSH1 0 REVERT JUMPDEST STOP
    Code c("600035600b5760006000fd5b00");
    auto r = run_at(c);
    INFO(dump_trace(r.trace));
    CHECK(r.trace == V("{(if (calldataload 0) {(stop)} {(revert None)})}"));
}

TEST_CASE("vm: loop") {
    Fixture fx;
    // i = 0; head: if !(10 > i) goto exit; i += 1; goto head; exit: stop
    Code c("60005b80600a11156011576001016002565b00");
    auto r = run_at(c);
    MESSAGE(dump_trace(r.trace));
    CHECK(r.complete);
    CHECK(r.loops.size() == 1);
}

TEST_CASE("vm: call") {
    Fixture fx;
    // CALL(gas, caller, 0, 0, 0, 0, 32); POP; mem[0] = returndatasize; return mem[0..32]
    Code c("60206000600060006000335af1503d60005260206000f3");
    auto r = run_at(c);
    MESSAGE(dump_trace(r.trace));
    CHECK(r.calls.size() == 1);
}

TEST_CASE("vm: recursive internal function") {
    Fixture fx;
    // main: fact(calldataload(0)) returning to 8, mem[0] = result, return it
    // fact (17): [ret, n] -> n == 0 ? 1 : n * fact(n - 1)
    Code c("60086000356011565b60005260206000f35b80156026578060019003602290601156"
           "5b0290565b5060019056");
    auto r = run_at(c);
    MESSAGE(dump_trace(r.trace));
    REQUIRE(r.found_internals.size() == 1);
    CHECK(r.found_internals[0] == vm::InternalEntry{17, 1, 1, 2});
    CHECK(r.trace == V("{(internal 17 [(calldataload 0)] [tmp1]) (setmem (range 0 32) (sized 32 tmp1))"
                       " (return (mem (range 0 32)))}"));

    // the function apart: its own calls are INTERNAL lines, its end LEAVE
    FunctionInfo f;
    f.kind = FunctionInfo::Kind::Internal;
    f.entry_pc = 17;
    f.params.resize(1);
    vm::VmOptions o;
    o.known_internals = &r.found_internals;
    auto ri = vm::run_function(c.shared, f, o);
    MESSAGE(dump_trace(ri.trace));
    CHECK(ri.complete);
}

TEST_CASE("vm: discovery") {
    Fixture fx;
    // solc-like: fmp; calldatasize < 4 -> fallback; selector 0x12345678 ->
    // 43 (returns 1), 0xaabbccdd -> 54 (non-payable: invalid when value);
    // fallback (38) reverts
    Code c("6080604052600436106026576000356" "0e01c806312345678146 02b5780" "63aabbccdd14603657"
           "5b600080fd5b600160005260206000f35b3415603d57fe5b00",
           true);
    Budget b{Budget::Limits{}};
    auto fns = vm::discover(c.shared, b);
    REQUIRE(fns.size() == 3);
    CHECK(fns[0].kind == FunctionInfo::Kind::Selector);
    CHECK(fns[0].selector == 0x12345678);
    CHECK(fns[0].entry_pc == 43);
    CHECK(fns[1].selector == 0xaabbccdd);
    CHECK(fns[1].entry_pc == 54);
    CHECK(fns[2].kind == FunctionInfo::Kind::Fallback);
    CHECK(fns[2].entry_pc == 38);
    for (const auto& f : fns) {
        MESSAGE(dump(f.entry.entry_lines), " ", dump(f.entry.checks), " ", dump(f.entry.vm_state));
        auto r = vm::run_function(c.shared, f, {});
        MESSAGE(dump_trace(r.trace));
        CHECK(r.complete);
    }
    CHECK(fns[0].entry.entry_lines == V("{(setmem (range 64 32) (sized 32 128))}"));
}

TEST_CASE("vm: merge of branches") {
    Fixture fx;
    // v = calldataload(0) ? 2 : 1; mem[0] = v; then a jump to the return
    // (python merges only where the block doesn't just end the execution)
    Code c("600035600b576001600e565b60025b6000526015565b60206000f3");
    auto r = run_at(c);
    INFO(dump_trace(r.trace));
    CHECK(r.trace == V("{(if (calldataload 0) {(setvar tmp1 2)} {(setvar tmp1 1)})"
                       " (setmem (range 0 32) (sized 32 tmp1)) (return (mem (range 0 32)))}"));

    // the block at the meeting point only returns: no merge
    Code d("600035600b576001600e565b60025b60005260206000f3");
    auto rd = run_at(d);
    INFO(dump_trace(rd.trace));
    CHECK(rd.trace == V("{(if (calldataload 0) {(setmem (range 0 32) (sized 32 2)) (return (mem (range 0 32)))}"
                        " {(setmem (range 0 32) (sized 32 1)) (return (mem (range 0 32)))})}"));
}

TEST_CASE("vm: snapshot of storage reads") {
    Fixture fx;
    // x = sload(0); sstore(0, 5); sstore(1, x): x is read before the first store
    // PUSH1 0 SLOAD PUSH1 5 PUSH1 0 SSTORE PUSH1 1 SSTORE STOP
    Code c("6000546005600055600155 00");
    auto r = run_at(c);
    INFO(dump_trace(r.trace));
    CHECK(r.trace == V("{(setvar tmp1 (storage 256 0 0)) (store 256 0 0 5) (store 256 0 1 tmp1) (stop)}"));
}

TEST_CASE("vm: verbose") {
    Fixture fx;
    Code c("6001600201600052 60206000f3");
    vm::VmOptions o;
    o.verbose = true;
    auto r = run_at(c, 0, o);
    INFO(dump_trace(r.trace));
    REQUIRE(r.trace.size() > 2);
    CHECK(r.trace[0] == V("(asm 0 96 1 [])"));
    CHECK(r.trace[1] == V("(asm 2 96 2 [1])"));
}

TEST_CASE("vm: stack underflow, invalid jumps, unknown opcode") {
    Fixture fx;
    CHECK(run_at(Code("01")).trace == V("{(invalid 5 0)}"));
    CHECK(run_at(Code("600556")).trace == V("{(invalid 4 5)}"));            // past the code
    CHECK(run_at(Code("6004565b00")).trace == V("{(invalid 3 4)}"));        // not a jumpdest
    CHECK(run_at(Code("0c")).trace == V("{(invalid 1 0)}"));
    CHECK(run_at(Code("6000")).trace == V("{(stop)}"));                     // falls off the end
    CHECK(run_at(Code("61ff")).trace == V("{(stop)}"));                     // a cut push
    CHECK(run_at(Code("600035 56")).trace == V("{(undefined 2 3)}"));       // computed jump
}

TEST_CASE("vm: code switch") {
    Fixture fx;
    // Vyper's table dispatch: codecopy(0, 30 + (cd[0] % 2) * 2, 2), then a
    // jump to mload(0) >> 240: 24 (STOP) or 26 (INVALID)
    Code c("6002" "6002" "600035" "06" "6002" "02" "601e" "01" "6000" "39" "600051" "60f01c" "56"
           "5b00" "5bfe" "0000" "0018" "001a");
    Budget b{Budget::Limits{}};
    auto fns = vm::discover(c.shared, b);
    REQUIRE(fns.size() == 1);
    auto r = vm::run_function(c.shared, fns[0], {});
    INFO(dump_trace(r.trace));
    CHECK(r.complete);
    CHECK(r.trace == V("{(if (eq (mod (calldataload 0) 2) 0)"
                       " {(setmem (range 0 2) (sized 2 24)) (stop)}"
                       " {(setmem (range 0 2) (sized 2 26)) (invalid 1 27)})}"));
}
