// The operations of the IR: Op (an EVM instruction is its byte, the
// decompiler's own operations are 0x100..0x1ff), their properties (OpInfo,
// the property bits, the content flags) and the EVM decoder's tables - all
// generated from spec/evm.def and spec/ops.def (tools/gen_ops.py).
// Code dispatches with switch on Op; names are for dumps and printing only.
#pragma once

#include "core/base.hpp"
#include "core/ops_gen.hpp"

namespace pan {

namespace detail {
inline constexpr OpInfo kUndefinedOp{nullptr, 0, 0, false, Sort::None, 0, 0u, 0, false};
}

// O(1), any u16: past the table, an undefined entry
[[nodiscard]] constexpr const OpInfo& info(Op op) noexcept {
  const u32 i = u32(op);
  return i < kOpCount ? kOpInfo[i] : detail::kUndefinedOp;
}

[[nodiscard]] inline bool has(Op op, u32 prop) noexcept { return (info(op).props & prop) != 0; }

// for dumps and the printer only; "unknown" for an undefined op
[[nodiscard]] inline const char* op_name(Op op) noexcept {
  const OpInfo& i = info(op);
  return i.defined ? i.name : "unknown";
}

}  // namespace pan
