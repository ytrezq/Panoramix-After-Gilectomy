// The function traits (lot 8; python function.py's Function: make_params,
// validation, make_names, cleanup_masks, analyse; contract.py's
// replace_names; utils/signatures.py's calldata_params / head_words; asm
// function.s, sigs.s): the Analysed stage of a function, in its job after
// lot 7's simplifier - before lot 9's storage forms.
//
// analyse_function(fn, shared), on cx(), fn changed in place:
//  - fn.params: a ParamInfo per word of the head of the calldata a param
//    takes, by calldata offset (python inferred_params): a known function's
//    (the signature database's entry, known: its params' words - each
//    word of a static tuple or array, a dynamic param's offset - abi_index
//    the param's place in the signature), else inferred from the trace's
//    CALLDATALOAD(4 + 32k) (python make_params: masked everywhere to N bits
//    -> uintN / address, only a truth value -> bool, the offset of other
//    reads -> an array, solc >= 0.8's validation `require x == address(x)`
//    -> its type; none at all when a constant offset isn't 4 + 32k). The
//    fallback's are inferred too; an internal function's are left alone.
//  - fn.name_known: the database knows the selector (Entry::known():
//    verified or repaired, both hash to it; an unverified entry is
//    panoramix's own guess, never a name).
//  - fn.entry.nonpayable / value_fails: the body's first line past SETMEM /
//    SETVAR lines is `if callvalue: revert` (REVERT(None) or INVALID) -> it
//    is taken out of the body (the trace machine checks it first:
//    machine.hpp step 4), value_fails = that halting line (Vyper's `if
//    callvalue or calldatasize < 36: revert` keeps the rest of its
//    condition). Or the dispatcher's hoisted check (solc's, when no function
//    is payable): the last check of fn.entry.entry_lines, then removed from
//    them. fn.payable = !nonpayable.
//  - the trace: past a param's validation (`if x != address(x): revert`),
//    its clean form (address(x)) is x (python cleanup_masks: never before
//    the check, solc < 0.5 has none); CALLDATALOAD(4 + 32k) of a param ->
//    Name(PARAM, k) (python replace_names; the machine reads Name(PARAM, k)
//    at params[k].calldata_offset, the raw word).
//  - fn.read_only: no STORE TSTORE SELFDESTRUCT CALL CALLCODE DELEGATECALL
//    CREATE CREATE2 LOGn INTERNAL line anywhere (python's "'call'" in
//    str(trace), by the ops); fn.is_const: read only, one RETURN, nothing
//    read that varies (calldata, state, environment - but ADDRESS and
//    CODESIZE), nonpayable failing on value with REVERT(None) (python
//    const), and - unlike python - one path: the body only SETMEM/SETVAR
//    lines before the RETURN (the entry lines are the dispatcher's), so
//    that no condition on the context (`require this.address == SELF`)
//    hides a revert behind `const`; fn.getter: read only, not a const,
//    one RETURN of a storage read, a struct of consecutive words, or
//    kitties-style (getter_of).
// An internal function is left as it is (python doesn't analyse them).
// Errors: the Budget's (MemoryLimit, Timeout, DepthLimit).
#pragma once

#include <optional>
#include <span>
#include <vector>

#include "core/base.hpp"
#include "core/contract.hpp"
#include "core/value.hpp"

namespace pan::sigdb {
class Entry;  // src/sigdb.hpp
}

namespace pan::traits {

struct Options {
    bool params = true;         // the params (fn.params) and Name(PARAM, k) in the trace
    bool payable = true;        // the callvalue check out of the body / the entry
    bool cleanup_masks = true;  // python cleanup_masks
};

// The Analysed stage of one function (above). Python Function(hash, trace).
void analyse_function(FunctionInfo& fn, const ContractShared& shared, const Options& opts = {});

// The Analysed stage of a contract's functions (tests, stage checks): out =
// in, each analysed; a function that failed before (problem, or no trace)
// copied as it is; one whose analysis fails (an Error) gets no trace and
// problem = 0. Timeout (an Abort) goes through.
void analyse_stage(std::span<const FunctionInfo> in, std::vector<FunctionInfo>& out, const ContractShared& shared,
                   const Options& opts = {});

// ---- what the other lots read of an analysed function --------------------------

// The RETURN lines of a trace, any depth (python find_returns), in the order
// of the lines (an IF's branches, a WHILE's body where they are).
void returns_of(Value trace, std::vector<Value>& out);

// What a getter returns (python Function.getter; lot 9 names the storage
// variables after the getters), read on the trace analyse_function made (its
// STORAGE reads, before lot 9's forms).
struct Getter {
    enum class Kind : u8 {
        Read,     // one storage read: `read` = STORAGE(size, off, slot), `value` the
                  // word returned (the read, a cast of it, BOOL of it...)
        Struct,   // consecutive words of one place: read = the first, STORAGE(256, 0, slot)
        Kitties,  // words at sha3(..., n) of one small n (python ("struct", ("loc", n))): slot = n
    };
    Kind kind = Kind::Read;
    Value read;    // Read, Struct
    Value value;   // the word returned (python word(returns[0][1])); Struct, Kitties: the DATA
    u64 slot = 0;  // Kitties
};
// fn's getter (nullopt when fn.getter is false: not read only, a const,
// several returns, not a storage read)
std::optional<Getter> getter_of(const FunctionInfo& fn);

// What a const returns (python Function.const): the RETURN line's data (its
// DATA, a mask, an int as python unwraps them); NIL when fn isn't a const.
Value const_of(const FunctionInfo& fn);

// The ParamInfo of the head words of a known function's params (python
// calldata_params / head_words): the words of a static tuple or array each
// (a static array of more words than calldata can hold: one), a dynamic
// param's offset; calldata_offset 4 + 32 k, abi_index its param's place.
std::vector<ParamInfo> abi_params(const sigdb::Entry& entry);

}  // namespace pan::traits
