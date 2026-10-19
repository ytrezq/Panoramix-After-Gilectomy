// Loop rewrites (python loop_to_setmem, loop_to_setmem_from_storage,
// propagate_storage_in_loops, replace_while_var; asm loops.s).
#include "loops/loops.hpp"

#include "core/budget.hpp"
#include "core/context.hpp"
#include "loops/internal.hpp"

namespace pan::loops {

Value loop_to_setmem(Value while_line, const RewriteOptions& opts) {
    (void)opts;
    return while_line;
}

Value loops_to_setmems(Value trace, const RewriteOptions& opts) {
    (void)opts;
    return trace;
}

Value propagate_storage_in_loops(Value trace) { return trace; }

Value rename_var(Value trace, Value from, Value to) {
    if (from == to) return trace;
    detail::Renamer r;
    r.add(from, to);
    return r(trace);
}

}  // namespace pan::loops
