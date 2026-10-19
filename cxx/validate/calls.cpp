// The calls of the validation: their calldata, callers and values.
#include "calls.hpp"

#include <algorithm>

namespace validate
{
namespace
{
// the kinds of the generator's pseudo-random values (the world's are < 0x80)
enum Kind : std::uint8_t
{
    k_word = 0x80,
    k_shape,
    k_sender,
    k_fallback,
};

Bytes key_of(std::initializer_list<Word> words)
{
    Bytes key;
    key.reserve(32 * words.size());
    for (const auto& w : words)
        append_word(key, w);
    return key;
}

void append_selector(Bytes& out, std::uint32_t selector)
{
    for (int i = 3; i >= 0; --i)
        out.push_back(static_cast<std::uint8_t>(selector >> (8 * i)));
}
}  // namespace

CallGenerator::CallGenerator(const SeededWorld& world, BytesView code, CallConfig config)
  : world_{&world}, config_{config}, selectors_{find_selectors(code)}
{
    if (config_.probe)
    {
        auto probed = probe_selectors(code, world);
        for (const auto s : probed.selectors)
            if (std::ranges::find(selectors_, s) == selectors_.end())
                selectors_.push_back(s);
        for (const auto& a : probed.callers)
            if (std::ranges::find(world.actors(), a) == world.actors().end())
                privileged_.push_back(a);
    }
}

Word CallGenerator::calldata_word(std::uint32_t selector, unsigned variant, unsigned index,
    unsigned words) const
{
    const auto r = world_->hash(k_word, key_of({selector, variant, index}));
    const auto pick = static_cast<unsigned>(r % 100);
    const Word rest = r >> 8;
    if (pick < 20)
        return 0;
    if (pick < 30)
        return 1;
    if (pick < 45)
        return 2 + rest % 62;
    if (pick < 65)
    {
        const auto actors = world_->actors();
        if (rest % 10 < 6 && !actors.empty())
            return actors[static_cast<std::size_t>((rest >> 8) % actors.size())];
        return to_address(rest >> 16);
    }
    if (pick < 75)
        return Word{32} * (1 + rest % std::max(words, 1u));  // an ABI offset into the calldata
    if (pick < 83)
        return ~Word{0};
    if (pick < 90)
        return r;
    if (pick < 95)
        return Word{0} - (1 + rest % 100);  // a small negative int
    return Word{1} << static_cast<unsigned>(rest % 256);
}

Bytes CallGenerator::arguments(std::uint32_t selector, unsigned variant) const
{
    if (variant == 0)
        return {};
    const auto r = world_->hash(k_shape, key_of({selector, variant}));
    unsigned words = 0;
    switch (variant)
    {
    case 1:
        words = 1;
        break;
    case 2:
        words = 2 + static_cast<unsigned>(r % 2);
        break;
    case 3:
        words = 4 + static_cast<unsigned>(r % 5);
        break;
    default:
        words = static_cast<unsigned>(r % 13);
        break;
    }
    const auto shape = static_cast<unsigned>((r >> 8) % 8);
    if (shape == 0)
        words += 16;  // long
    Bytes out;
    out.reserve(32 * words);
    for (unsigned i = 0; i < words; ++i)
        append_word(out, calldata_word(selector, variant, i, words));
    if (shape == 1 && !out.empty())
        out.resize(out.size() - 1 - static_cast<std::size_t>((r >> 16) % 31));  // short
    return out;
}

CallContext CallGenerator::context_for(std::uint32_t key, unsigned variant, Bytes calldata) const
{
    const auto r = world_->hash(k_sender, key_of({key, variant}));
    CallContext c;
    const auto actors = world_->actors();
    if (!actors.empty())
    {
        // the first actor most of the time, sometimes an owner the code
        // checks the caller against
        const auto pick = static_cast<unsigned>(r % 20);
        if (pick < 12)
            c.caller = actors[0];
        else if (pick < 17 || privileged_.empty())
            c.caller = actors[static_cast<std::size_t>((r >> 8) % actors.size())];
        else
            c.caller = privileged_[static_cast<std::size_t>((r >> 8) % privileged_.size())];
    }
    c.origin = c.caller;
    if ((r >> 16) % 100 < config_.value_percent)
        c.value = (r >> 24) % 2 == 0 ? Word{1'000'000'000'000'000'000ULL} : 1 + (r >> 32) % 1000;
    c.gas_price = world_->block().base_fee + 1'000'000'000;
    c.calldata = std::move(calldata);
    return c;
}

PlannedCall CallGenerator::call(std::uint32_t selector, unsigned variant) const
{
    Bytes calldata;
    if (encoder_)
    {
        if (auto encoded = encoder_(selector, variant, *world_))
            calldata = std::move(*encoded);
    }
    if (calldata.empty())
    {
        append_selector(calldata, selector);
        const auto args = arguments(selector, variant);
        calldata.insert(calldata.end(), args.begin(), args.end());
    }
    return {context_for(selector, variant, std::move(calldata)), selector, variant};
}

PlannedCall CallGenerator::fallback(unsigned variant) const
{
    const auto r = world_->hash(k_fallback, key_of({variant}));
    Bytes calldata;
    if (variant == 1)
    {
        const auto b = to_bytes(r);
        calldata.assign(b.begin(), b.begin() + 1 + static_cast<std::ptrdiff_t>(r % 3));
    }
    else if (variant >= 2)
    {
        // a selector of none of the functions
        auto sel = static_cast<std::uint32_t>(r >> 32);
        while (std::ranges::find(selectors_, sel) != selectors_.end())
            ++sel;
        append_selector(calldata, sel);
        const auto args = arguments(sel, 1 + variant % 4);
        calldata.insert(calldata.end(), args.begin(), args.end());
    }
    return {context_for(0xffffffff, variant, std::move(calldata)), std::nullopt, variant};
}

std::vector<PlannedCall> CallGenerator::calls() const
{
    std::vector<PlannedCall> out;
    out.reserve(selectors_.size() * config_.per_selector + config_.fallbacks);
    for (const auto s : selectors_)
        for (unsigned v = 0; v < config_.per_selector; ++v)
            out.push_back(call(s, v));
    // more calls of the fallback when there's no dispatcher to read
    const auto fallbacks = selectors_.empty() ? config_.fallbacks + config_.per_selector : config_.fallbacks;
    for (unsigned v = 0; v < fallbacks; ++v)
        out.push_back(fallback(v));
    return out;
}
}  // namespace validate
