// The data several stages share beside the traces: what the final trace
// doesn't say and the execution needs (ir.md section 4.6) - the dispatcher's
// conditions for each function, where its parameters sit in the calldata,
// the call sites and loops a trace's ids refer to. The stages' own results
// (the storage layout: lot 9; the SafeMath table: lot 8; the contract's
// result: lot 12) are declared in their headers.
#pragma once

#include <optional>
#include <span>
#include <vector>

#include "core/base.hpp"
#include "core/value.hpp"

namespace pan {

struct CodeMap;  // the decoder's bitmaps (lot 1)
namespace sigdb {
class Database;  // src/sigdb.hpp
}

enum class Lang : u8 { Unknown, Solidity, Vyper };

// the contract's read-only data, shared by the parallel jobs
struct ContractShared {
    std::span<const u8> code;
    const CodeMap* map = nullptr;        // lot 1
    const sigdb::Database* db = nullptr;  // may be null
    Lang lang = Lang::Unknown;
    bool free_memory_pointer = true;  // solidity's fmp idiom (mem[64]) assumed
};

enum class AbiKind : u8 { Word, Uint, Int, Address, Bool, BytesN, Bytes, String, Array, Tuple, Unknown };

// Name(PARAM, k) -> FunctionInfo::params[k]
struct ParamInfo {
    u32 calldata_offset = 0;
    AbiKind kind = AbiKind::Word;
    u16 bits = 256;  // uintN/intN/bytesN: N (bits); others 256
    bool dynamic = false;
    std::optional<u32> abi_index;  // its position in the known signature
};

// the dispatcher's path to the function (kept beside its trace)
struct EntryCondition {
    std::optional<u32> selector;  // none: the fallback, an internal function
    Value checks;                 // a LIST of bool exprs that held on the dispatcher's path
    bool nonpayable = false;      // `if callvalue: revert` before the body
    Value entry_lines;            // a TRACE: the dispatcher's lines before the body (setmems)
};

// a call line's id -> what it was (CALL_SUCCESS / RETURNDATA_BYTES(id, ...) refer to it)
struct CallSite {
    u32 id = 0;
    Op kind = Op::NONE;  // CALL, CALLCODE, DELEGATECALL, STATICCALL, CREATE, CREATE2, PRECOMPILED
    u32 pc = 0;
};

// Name(LOOP_ID, id) -> the loop
struct LoopInfo {
    u32 id = 0;
    u32 head_pc = 0;
};

struct FunctionInfo {
    enum class Kind : u8 { Selector, Fallback, Internal };
    Kind kind = Kind::Selector;
    u32 selector = 0;  // Kind::Selector
    u32 entry_pc = 0;  // where its body starts (an internal function: its entry)
    EntryCondition entry;
    std::vector<ParamInfo> params;
    std::vector<CallSite> calls;
    std::vector<LoopInfo> loops;
    bool payable = false, read_only = false, is_const = false, getter = false, name_known = false;
    std::optional<u32> problem;  // the index of its error message, if it failed
    Value trace;                 // the current stage's trace (a TRACE list)
};

}  // namespace pan
