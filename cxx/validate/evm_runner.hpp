// The EVM side of the comparison: a contract's runtime bytecode run by evmone
// (baseline interpreter, revision Osaka) for one call, or a sequence of
// calls, against a State, through an evmc::Host that answers from a Session
// (session.hpp) and records the Effects. External calls are never executed:
// their results come from the World.
//
// Gas: the call gets `RunOptions::gas` (the budget that bounds the loops and
// the memory; out of it, the end is `exhausted`), GAS gives fixed_gas, the
// external calls use none and return all they're given.
#pragma once

#include "effects.hpp"
#include "session.hpp"
#include "world.hpp"

#include <memory>
#include <span>
#include <vector>

namespace validate
{
struct RunOptions
{
    /// The gas of the call: its budget of steps and memory (100M: ~7 MB of
    /// memory, ~0.1 s of the longest loops).
    std::int64_t gas = 100'000'000;
    /// Count the instructions each call executes (RunCost; an evmone
    /// tracer: slower).
    bool count_instructions = false;
};

/// What a call used.
struct RunCost
{
    std::int64_t gas = 0;            ///< of RunOptions::gas (all of it when the call ended invalid)
    std::uint64_t instructions = 0;  ///< executed (RunOptions::count_instructions, else 0)
};

/// A runtime bytecode ready to run (analyzed once). Not thread-safe: one
/// per thread.
class EvmRunner
{
public:
    explicit EvmRunner(Bytes code, RunOptions options = {});
    ~EvmRunner();
    EvmRunner(EvmRunner&&) noexcept;
    EvmRunner& operator=(EvmRunner&&) noexcept;

    const Bytes& code() const noexcept;
    RunOptions& options() noexcept;
    /// What the last call run used.
    const RunCost& cost() const noexcept;

    /// Runs the session's call and finishes the session (the State must
    /// hold the same code).
    Effects run(Session& session);
    /// One call against a State.
    Effects run(State& state, const CallContext& call);
    /// A sequence of calls, each one starting from what the previous ones
    /// left in the State.
    std::vector<Effects> run(State& state, std::span<const CallContext> calls);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
}  // namespace validate
