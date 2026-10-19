// The outputs (lot 10; python folder.py, prettify.py, contract.py,
// decompiler.py's printing, function.py's print / serialize; asm folder.s,
// prettify.s, pretty_line.s, pretty_mem.s, contract.s, explain.s, data.s):
// the only place where program values become text (AGENTS.md rule 1).
//
//  1. The ast of a function (python Contract.make_ast): its entry checks and
//     body, lot 7's short_circuits, the folder (the paths of the trace
//     folded back into ifs: shared prefixes and suffixes once, if-without-
//     else where a branch ends, REQUIRE / ASSERT where one only reverts or
//     is invalid, merged ifs' common lines hoisted by lot 7's effect
//     summaries), python's display rewrites. The ast stays executable
//     (ir.md section 4; lot 11's trace machine runs it: M3): REQUIRE(cond[,
//     data]), ASSERT(cond), LAND / LOR, MASK, BREAK are ops of the IR.
//  2. The text (python's display style, as the asm prints it - its outputs
//     on the corpus): expressions by python's precedences (prec of the
//     operators, parentheses only where needed), lines (pretty_line,
//     pprint_logic), memory data (pretty_memory: strings, ABI arrays,
//     Bytes(n, v), selectors), names made from the integer ids at print
//     time (_N, idx s t u..., the ABI's params, _paramN, storage names,
//     collision suffixes), numbers (decimal / hex, 10**k * m, n * 3600),
//     colors (a policy: none or the terminal's), everything from outside
//     (the contract's strings, the signature database's names) escaped:
//     C0, DEL, C1 and the bidi controls as \xNN / \uNNNN. The printer never
//     makes a Value (it can read the contract's context from any thread).
//  3. The contract's text (python decompiler.py): the header, `I failed
//     with these:`, the consts, `def storage:`, `def SafeMath:`, the getters,
//     the regular functions by priority, the recursive internal functions;
//     --repr, --returns; --verbose's ASM lines as comments.
//  4. JSON (rule 7: the format is ours): python's decompilation.json's keys,
//     each trace as a shallow table of its distinct nodes (below).
//  5. --explain: the text of a trace after a stage (python's explain), of
//     the function's traits (explain_text); the driver (lot 12) calls them.
//
// What lots 8 and 9 add (FunctionInfo's traits and params, the storage
// layout, the SafeMath table) is printed when it is there: lot 9's forms
// (ST, SET, SALL over SV SI SL SBL SF SR) by the layout's names - a getter's,
// else stor<slot> - with `def storage:`; lot 8's SAFEMATH calls with `def
// SafeMath:`, Name(PARAM, k) by the name of its head word. Without them the
// storage reads as the asm prints it when its storage analysis fails
// (STORAGE(size, off, slot) as stor[slot], casts and fields), the calldata
// as cd[k].
#pragma once

#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "core/base.hpp"
#include "core/budget.hpp"
#include "core/contract.hpp"
#include "core/value.hpp"

namespace pan::sigdb {
class Database;  // src/sigdb.hpp
}
namespace pan::driver {
struct ContractResult;  // driver/pipeline.hpp (lot 12)
}
namespace pan {
struct StorageLayout;  // storage/storage.hpp (lot 9)
struct SafeMathTable;  // analysis/safemath.hpp (lot 8)
}  // namespace pan

namespace pan::output {

// ---- 1. the ast --------------------------------------------------------------------

struct AstOptions {
    bool fold = true;            // the folder (false: the trace's own ifs, the rewrites only)
    bool short_circuits = true;  // lot 7's short_circuits first (python make_ast)
    bool entry_checks = true;    // the entry's checks (EntryCondition::entry_lines' IFs) before the body
    // the fold's own context's memory (the asm's FOLD_LIMIT): past it, the
    // trace is left unfolded (the rest of make_ast still applies)
    usize fold_limit = limits::FOLD_LIMIT;
    // the fold's deadline (monotonic; 0: none): Timeout past it
    i64 deadline_ns = 0;
};

// The folder alone (python folder.fold) on cx(): a trace (IF / WHILE ...)
// folded. Equivalent to it (the same effects on every input: ir.md 4); the
// trace itself when the fold can't (an Error inside: python's "folder
// failed", the trace unfolded).
Value fold(Value trace);

// The ast of a function (python make_ast) on cx(): fn's entry checks and
// trace through short_circuits, fold (on a context of its own of
// opts.fold_limit bytes, the result imported back), the display rewrites.
// fn.trace NIL: NIL. Errors: the Budget's (MemoryLimit, Timeout).
Value make_ast(const FunctionInfo& fn, const AstOptions& opts = {});

struct AstStageOptions {
    usize threads = 1;     // the functions made at once (the results are the same at any count)
    i64 deadline_ns = 0;   // the post-processing's deadline (monotonic; 0: none): Timeout past it
    AstOptions ast;
    const ContractShared* shared = nullptr;  // the contexts' (may be null)
};

// The Folded stage of a contract (lot 12's contract phase): out = in, each
// trace made its ast (make_ast), min(threads, n) at a time, each on a
// context and budget of its own (the caller's budget's memory limit
// bounds what is imported back), on the caller's context (cx()) in the
// end. A function that failed before (problem, or NIL trace) is copied as
// it is; a function whose ast can't be made (an Error) keeps its trace as
// it was. Throws Timeout past the deadline, MemoryLimit of the caller's
// budget.
void ast_stage(std::span<const FunctionInfo> in, std::vector<FunctionInfo>& out, const AstStageOptions& opts = {});

// ---- 2. text ---------------------------------------------------------------------------

struct PrintOptions {
    bool color = true;       // the terminal's color codes (python's C.*)
    bool repr = false;       // python's --repr: the Simplified trace after each function
    bool returns = false;    // python's --returns: its return lines after each function
    usize threads = 1;       // the functions printed at once (the text is the same at any count)
    const sigdb::Database* db = nullptr;  // the names (functions, events, errors); null: none known
    // the post-processing's deadline (monotonic; 0: none): Timeout past it
    i64 deadline_ns = 0;
};

// python's "# No code found for this contract."
std::string no_code_text(bool color);

// The contract's text (python decompiler.py's, without print()'s last
// newline): the header, the problems, the consts (lower-case names first),
// def storage (lot 9's layout), def SafeMath (lot 8's table), the getters,
// "#  Regular functions" and the others by priority (the self-destructing
// first, then by the length of their colored text, stable), "#  Internal
// functions". The functions of r's last stage (Folded when made). Makes no
// Value: safe while other threads read r's context.
std::string print_contract(const driver::ContractResult& r, const PrintOptions& opts);

// One function's text (python Function.print / InternalFunction.print): its
// header (def name(params) payable: # comment) and its body's lines.
// internal: the record of a recursive internal function (its params, frame).
std::string print_function(const driver::ContractResult& r, const FunctionInfo& fn, const PrintOptions& opts);

// What the printer needs of a function beside its trace (names, call
// kinds): the trace's own FunctionInfo, or null for a bare trace; the
// contract's storage layout and SafeMath (ContractResult::storage,
// ::safemath) for the names of their variables and functions, when there.
struct TraceContext {
    const FunctionInfo* fn = nullptr;
    const sigdb::Database* db = nullptr;
    bool color = false;
    const StorageLayout* storage = nullptr;
    const SafeMathTable* safemath = nullptr;
};
// A trace's lines (python pprint_logic), each indented by indent spaces and
// ended by "\n" (python pprint_ast: "  stop" for an empty one).
std::string print_trace(Value trace, const TraceContext& ctx = {}, u32 indent = 2);
// One expression (python prettify(exp, parentheses=False)).
std::string print_exp(Value e, const TraceContext& ctx = {});

// ---- 3. JSON -----------------------------------------------------------------------------

// python's decompilation.json, as JSON text (the python module json.loads
// it; pymod rebuilds python's tuples from the node tables):
//   {"problems": {hash: name}, "stor_defs": [SDEF...], "lang": "solidity",
//    "functions": [{"hash", "name", "color_name", "abi_name", "length": [lines, chars],
//                   "getter": bool, "const": text|null, "payable", "value_fails",
//                   "print": colored text, "params": {"offset": [type, name]},
//                   "trace": TRACE}],
//    "safemath": text, "internal": [{"name", "entry", "params", "results",
//                   "frame", "print", "trace": TRACE}]}
// SDEF (python Storage.header's): ["sdef", name, slot, off, TYPE] - slot a
// number, or {"int": "0x..."} past 2^53; TYPE ["value", width], ["struct",
// slots|null], ["mapping", TYPE], ["array", TYPE, stride], ["fixed", TYPE,
// stride(, length)], ["bytes"]. "safemath": the `def SafeMath:` block's
// lines (colored), joined by "\n" - only when the contract has one.
// TRACE: {"root": id, "nodes": [node...]}, the trace's distinct nodes once
// each, operands before their users (ids: indexes in nodes); a node is
//   ["op", operand...]   an EXPR (op: spec/ops.def's name)
//   ["list", item...] / ["trace", line...]
//   an operand: a number (an int that fits 53 bits), "0x..." (a bigger int:
//   {"int": "0x..."}), {"n": id} (a node), true / false / null (None), {"leaf":
//   "op", "n": k}, {"name": kind, "id": k}, {"bytes": "hex"}.
std::string to_json(const driver::ContractResult& r, const PrintOptions& opts);

// ---- 4. --explain ------------------------------------------------------------------------

// python's explain(title, trace): "\n" + C.green_back + " title: " + C.end
// + "\n\n" + the trace's lines (pprint_trace) + "\n\n" appended to out - as
// python prints them while the function is decompiled: the calldata as
// cd[k] (no param names yet), a storage read as python's tuple ('storage',
// 256, 0, 7) (no storage analysis yet). --verbose's ASM lines print their
// stacks so everywhere (python made them strings in its VM).
void explain_trace(std::string& out, std::string_view title, Value trace, const TraceContext& ctx);
// python's explain_text(title, params): "\n" + C.blue_back + " title: " +
// C.end + "\n\n" + a line " name: value" each + "\n".
void explain_text(std::string& out, std::string_view title,
                  std::span<const std::pair<std::string, std::string>> items, bool color);
// python's "function traits" (Function.analyse's explain_text): the return
// lines (python's str() of them: its IR's tuples), payable, read_only,
// const, getter of fn (lot 8's traits).
void explain_traits(std::string& out, const FunctionInfo& fn, const TraceContext& ctx);

}  // namespace pan::output
