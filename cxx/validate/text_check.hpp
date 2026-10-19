// text_check's command line (validate/text_check_main.cpp): its words, read
// by a Ragel machine (text_check.rl, AGENTS.md rule 2).
#pragma once

#include <cstdint>
#include <optional>
#include <string_view>
#include <utility>
#include <vector>

namespace validate::text
{
enum class CheckWord : std::uint8_t
{
    none,  ///< not one of them: an argument
    parse,
    run,
    seed,
    empty,
    random,
    per_selector,
    each,
    verbose,
    quiet,
    corpus,
    texts,
    help,
    params,
    unknown,  ///< an option that isn't one of them
};

CheckWord check_word(std::string_view arg) noexcept;

/// The calldata positions of the params of a contract's functions, the
/// lines "0xSELECTOR POS POS ..." of a file (text_check --params: the
/// asm's --json gives them; the text doesn't for an unknown function, whose
/// params are the words of calldata it reads, named in their order).
std::optional<std::vector<std::pair<std::uint32_t, std::vector<std::uint32_t>>>>
parse_param_positions(std::string_view text);
}  // namespace validate::text
