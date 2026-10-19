// The parsers of the validation, Ragel machines (AGENTS.md rule 2; scan.rl):
// hex text, numbers, the function selectors of a bytecode, evmrun's options.
#pragma once

#include "world.hpp"

#include <cstdint>
#include <optional>
#include <string_view>
#include <vector>

namespace validate
{
/// ASCII hex (an optional 0x, spaces around) to bytes; nullopt when it is
/// not hex (an odd number of digits, another character).
std::optional<Bytes> parse_hex(std::string_view text);

/// A number: decimal, or hex after 0x; nullopt when it is not one or
/// doesn't fit 256 bits.
std::optional<Word> parse_number(std::string_view text);

/// The selectors a runtime bytecode's dispatcher compares the calldata with
/// (solc's DUP1 PUSH4 s EQ PUSH dest JUMPI and its variants, vyper's), in
/// code order, each once.
std::vector<std::uint32_t> find_selectors(BytesView code);

/// evmrun's options (validate/evmrun.cpp).
enum class EvmrunOption : std::uint8_t
{
    none,  ///< not an option
    seed,
    empty,
    random,
    per_selector,
    gas,
    caller,
    value,
    selectors,
    quiet,
    corpus,
    each,
    compare,
    sigdb,      ///< the signature database of the typed arguments
    untyped,    ///< no typed arguments
    malformed,  ///< the percent of the typed calls malformed
    count,      ///< count the instructions executed
    help,
};
EvmrunOption evmrun_option(std::string_view arg);
}  // namespace validate
