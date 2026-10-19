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
    call,
    trace,
    sigdb,
    unknown,  ///< an option that isn't one of them
};

CheckWord check_word(std::string_view arg) noexcept;

/// A param's side information in a --params file: its calldata offset, the
/// text of its type (empty: not given).
struct SidePlace
{
    std::uint32_t offset = 4;
    std::string_view type;
};

/// The side information of a function (place_params of text_parser.hpp).
struct SideInfo
{
    std::optional<std::uint32_t> selector;  ///< nullopt: the fallback
    std::vector<SidePlace> places;          ///< the params', in their order
};

/// The side information of a contract's functions whose params' places the
/// text doesn't say (an unknown function's, the fallback's: the words of
/// calldata they read, named in their order), the lines of a file
/// "0xSELECTOR OFFSET[:TYPE] ..." ("_fallback OFFSET[:TYPE] ..." for the
/// fallback): text_check --params, made from the asm's --json. The types are
/// views of the text.
std::optional<std::vector<SideInfo>> parse_side_info(std::string_view text);
}  // namespace validate::text
