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
    CHECK(r.trace == V("{(setmem (range 0 32) 3) (return (mem (range 0 32)))}"));
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
