// Local change (cxx/third_party/evmone/NOTICE): what GAS pushes when
// EVMONE_FIXED_GAS is defined - the embedder's hook of the thread (the
// validation's Session: a gas left that goes down read by read), else
// EVMONE_FIXED_GAS.
#pragma once

#include <cstdint>

namespace evmone
{
/// read(ctx, counted): the gas left GAS pushes; counted is false for a GAS
/// right before a call (CALL, CALLCODE, DELEGATECALL, STATICCALL), the gas
/// that call takes. Set by the embedder around an execution.
struct FixedGasHook
{
    std::int64_t (*read)(void* ctx, bool counted) noexcept = nullptr;
    void* ctx = nullptr;
};

inline thread_local FixedGasHook fixed_gas_hook{};

inline std::int64_t fixed_gas_read(bool counted) noexcept
{
    const FixedGasHook& h = fixed_gas_hook;
    return h.read != nullptr ? h.read(h.ctx, counted) : std::int64_t{EVMONE_FIXED_GAS};
}
}  // namespace evmone
