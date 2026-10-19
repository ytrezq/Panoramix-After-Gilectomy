// The folder and the ast (lot 10, internal): fold.cpp, ast.cpp.
#pragma once

#include "core/value.hpp"

namespace pan::output::detail {

// python's folder.fold on cx(): the trace folded, or itself when it can't
Value fold_trace(Value trace);

// make_ast's passes (ast_passes.cpp), on cx(), each with its input's effects:
// the entry's checks and the SETMEMs the body may read, then the body
Value with_entry(Value entry_lines, Value trace);
// a call's results read where another call may have been made since: a
// variable set right after the call (python's VM snapshot, `_1 = ...`)
Value snapshot_call_results(Value trace);
// an if whose branches are the same but for their calls' ids: its lines
Value merge_same_branches(Value ast);

}  // namespace pan::output::detail
