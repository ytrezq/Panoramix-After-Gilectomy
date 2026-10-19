// The calls the validation makes: the function selectors of a contract (found
// in its dispatcher, scan.rl) and pseudo-random calldata for each, the
// fallback's calls, the callers and the values - all a function of the
// world's seed, so that both sides run the same calls.
//
// The arguments are random words (no types): values that exercise branches
// (0, 1, small, max, addresses - the actors' -, ABI offsets and lengths),
// short and long calldata. A hook (CallGenerator::Encoder) lets typed
// arguments (from the signature database) replace them.
#pragma once

#include "scan.hpp"
#include "world.hpp"

#include <cstdint>
#include <functional>
#include <optional>
#include <vector>

namespace validate
{
/// One call to make, and why.
struct PlannedCall
{
    CallContext context;
    std::optional<std::uint32_t> selector;  ///< none: a fallback's call
    unsigned variant = 0;                   ///< which of the selector's calls
};

struct CallConfig
{
    unsigned per_selector = 4;  ///< calls per selector (variant 0: no arguments)
    unsigned fallbacks = 3;     ///< empty calldata, a short one, an unknown selector
    unsigned value_percent = 10;  ///< of the calls with a value (1 ether, or a small one)
};

class CallGenerator
{
public:
    /// The calldata of a selector's call (its variant), nullopt to keep the
    /// random words: the hook for typed arguments.
    using Encoder = std::function<std::optional<Bytes>(std::uint32_t selector, unsigned variant,
        const SeededWorld& world)>;

    CallGenerator(const SeededWorld& world, BytesView code, CallConfig config = {});

    const std::vector<std::uint32_t>& selectors() const noexcept { return selectors_; }
    void set_encoder(Encoder encoder) { encoder_ = std::move(encoder); }

    /// The calls of a sequence: every selector's variants, then the fallback's.
    std::vector<PlannedCall> calls() const;
    /// One call of a selector.
    PlannedCall call(std::uint32_t selector, unsigned variant) const;
    /// One call of the fallback (variant 0: no calldata, 1: 1-3 bytes, else:
    /// a selector of none of the functions, with words).
    PlannedCall fallback(unsigned variant) const;
    /// The random words after a selector (variant 0: none).
    Bytes arguments(std::uint32_t selector, unsigned variant) const;

private:
    CallContext context_for(std::uint32_t key, unsigned variant, Bytes calldata) const;
    Word calldata_word(std::uint32_t selector, unsigned variant, unsigned index, unsigned words) const;

    const SeededWorld* world_;
    CallConfig config_;
    std::vector<std::uint32_t> selectors_;
    Encoder encoder_;
};
}  // namespace validate
