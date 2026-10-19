// The structural total order of values: deterministic, independent of
// addresses, contexts, threads and runs (python sorted by str: here a
// C++-specific order on the structure).
//
//   NIL < ints (numeric, small and big mixed) < False < True < None
//   < Leaf (op, n) < Name (kind, id) < Bytes (length, then bytes)
//   < Expr (op, size, operands left to right) < List (kind, size, items)
#pragma once

#include "core/value.hpp"

namespace pan {

// -1, 0, 1
int compare(Value a, Value b);

struct StructuralLess {
    bool operator()(Value a, Value b) const { return compare(a, b) < 0; }
};

}  // namespace pan
