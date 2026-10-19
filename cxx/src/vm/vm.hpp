// The symbolic VM (python vm.py, stack.py, loader.py's discovery; asm vm.s,
// vmmem.s, vmnode.s, vmrec.s, stack.s, funcs.s, entry.s): the raw trace of a
// function by symbolic execution of the bytecode, the contract's functions by
// a run of the dispatcher alone, and the recursive internal functions found
// on the way (decompiled apart, in waves: lot 12).
//
// The raw trace (ir.md section 4, executable by lot 11's trace machine):
//  - lines: SETVAR(Name(TMP|LOOP|PRECOMPILE, n), e), SETMEM(RANGE(p, n), v)
//    (v: the n bytes written - a word's low n bytes, MEM(RANGE(...)) or
//    CALLDATA_BYTES / CODE_BYTES / EXTCODE_BYTES / RETURNDATA_BYTES of n
//    bytes; a codecopy of known code: an int (n <= 32) or a BYTES node
//    (n > 32)), STORE(256, 0, slot, e), TSTORE, LOG0+k(data, topics...),
//    CALL/CALLCODE(id, gas, addr, value, sel, params),
//    DELEGATECALL/STATICCALL(id, gas, addr, sel, params), CREATE(id, value,
//    code), CREATE2(id, value, code, salt), PRECOMPILED(id, Name(PRECOMPILE,
//    addr << 24 | k), addr, input), INTERNAL(entry, [args], [Name(TMP, k)...]);
//  - control: IF(cond, then, else) with both branches; LABEL(Name(LOOP_ID,
//    k), {SETVAR...}) at a loop's head (the lines after it are the loop's
//    body) and GOTO(Name(LOOP_ID, k), {SETVAR...}) back to it (setvars
//    simultaneous); a branch that ends without halting goes on after its IF
//    (the continuation of merged paths);
//  - halting: STOP, RETURN(MEM(RANGE(p, n))), REVERT(MEM(...) | None),
//    INVALID(InvalidReason, pc), SELFDESTRUCT(addr), LEAVE([values]) (an
//    internal function's end), UNDEFINED(UndefinedReason, pc) (the VM gave
//    up there: the run is inconclusive).
//  - numbered calls: each call line's first operand is its id (1, 2... per
//    function); its results are Leaf(CALL_SUCCESS, id), Leaf(RETURNDATASIZE,
//    id), RETURNDATA_BYTES(id, off, len), Leaf(CREATE_ADDRESS, id) - never
//    "the last call". Leaf(RETURNDATASIZE, 0) is the return data size before
//    any call of the run: 0.
//  - --verbose: ASM(pc, op, imm or None, [stack]) before each instruction.
//
// Values: everything is made on cx(); a FunctionInfo given to run_function
// must be on it (imported by the caller).
#pragma once

#include <optional>
#include <vector>

#include "core/base.hpp"
#include "core/budget.hpp"
#include "core/contract.hpp"
#include "core/value.hpp"

namespace pan::vm {

// INVALID(reason, pc): why a path halts exceptionally (the printer's words:
// python's ("invalid", "jump"), ("invalid", "jumdest", pc)...)
enum class InvalidReason : u32 {
    OPCODE = 1,           // INVALID (0xfe) or an undefined instruction
    ASSERT_FAIL = 2,      // (old solc's assert: not made by this VM)
    JUMP = 3,             // a jump to a place that isn't a JUMPDEST
    JUMPDEST = 4,         // a jump past the code
    STACK_UNDERFLOW = 5,  // fewer words than the instruction takes
    RETURNDATACOPY = 6,   // a copy past the end of the return data
};

// UNDEFINED(reason, pc): the VM gave up on the path there
enum class UndefinedReason : u32 {
    UNFINISHED = 1,     // a cap or the VM's time limit (python: "decompilation didn't finish")
    COMPUTED_JUMP = 2,  // a jump to an address computed at runtime
    AMBIGUOUS_CALL = 3, // return data read where the last call depends on the path (merged paths)
};

// A recursive internal function (python VM.internal: entry -> (n, m, frame)):
// a function called again in its own call - its calls are INTERNAL lines and
// its body is decompiled apart (FunctionInfo::Kind::Internal, entry_pc =
// entry, params[k] = Name(PARAM, k), k < nargs, the arguments in push order).
struct InternalEntry {
    u32 entry = 0;     // its first instruction (a JUMPDEST)
    u32 nargs = 0;     // n: the words of arguments, above its return address
    u32 nresults = 0;  // m: the words of results where it returns
    u32 frame = 0;     // the words of stack a call of itself takes
    bool operator==(const InternalEntry&) const = default;
};

struct VmOptions {
    bool verbose = false;  // ASM lines (the CLI's --verbose / --explain)
    // the recursive internal functions known (found by the earlier waves; for
    // an internal function's own run, its entry is among them): a call of one
    // is an INTERNAL line
    const std::vector<InternalEntry>* known_internals = nullptr;
    // the VM's own limits (python's STEP_TIMEOUT, MAX_NODE_COUNT): past them
    // the paths left are UNDEFINED(UNFINISHED) and complete is false - the
    // job's watchdog (FUNC_TIMEOUT) and memory limit are the caller's.
    // 0: scaled_timeout(limits::VM_TIMEOUT_NS) / limits::MAX_NODE_COUNT
    i64 timeout_ns = 0;
    u32 max_nodes = 0;
};

struct VmResult {
    Value trace;                                 // the raw TRACE (the body; entry lines apart)
    std::vector<CallSite> calls;                 // the call ids of the trace, in id order
    std::vector<LoopInfo> loops;                 // the LOOP_IDs of the trace, in id order
    std::vector<InternalEntry> found_internals;  // recursive functions found (python vm.found)
    bool complete = true;                        // false: UNDEFINED(UNFINISHED) leaves
    u32 nodes = 0;                               // the nodes explored
};

// The contract's functions: the VM on the dispatcher alone (python
// Loader.run: just_fdests, MAX_FDESTS_NODE_COUNT, LOADER_TIMEOUT). One
// FunctionInfo per selector (Kind::Selector, in the order the dispatcher
// tests them), then the fallback (Kind::Fallback: where the dispatcher goes
// when no selector matches, entry_pc 0 when that's all of the dispatcher).
// Each has entry_pc (the jump target) and its EntryCondition:
//  - selector;
//  - entry_lines: the dispatcher's lines on the path to it, executable, in
//    path order: SETMEMs and, for each check whose other branch halts,
//    IF(cond, {}, other) (or IF(cond, other, {}) when the path takes the
//    false branch) - python's apply_entry, flattened;
//  - checks: a LIST of the conditions that hold at entry (the checks'; for
//    a fallback that is all of the dispatcher, also that no selector
//    matched): facts for the VM, already enforced by entry_lines and the
//    dispatch - not to be evaluated again;
//  - nonpayable: false (lot 8 decides it from the body).
// The VM's entry state (the dispatcher's stack, what's known of memory) is
// kept in EntryCondition::vm_state (lot 5's own encoding, opaque to the
// others: imported with the rest; NIL for an internal function).
// Errors: only the Budget's (MemoryLimit, Timeout); a dispatcher the VM
// can't read gives the fallback alone.
std::vector<FunctionInfo> discover(const ContractShared& contract, Budget& budget);

// The raw trace of a function (selector, fallback or internal) from its
// entry_pc, with the dispatcher's state (discover) or, for an internal
// function, its params above a return address. Errors: the Budget's
// (MemoryLimit, Timeout, DepthLimit); Unsupported when the code map is
// missing.
VmResult run_function(const ContractShared& contract, const FunctionInfo& fn, const VmOptions& opts);

}  // namespace pan::vm
