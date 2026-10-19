// The folder and the ast (lot 10, internal): fold.cpp, ast.cpp.
#pragma once

#include "core/value.hpp"

namespace pan::output::detail {

// python's folder.fold on cx(): the trace folded, or itself when it can't
Value fold_trace(Value trace);

}  // namespace pan::output::detail
