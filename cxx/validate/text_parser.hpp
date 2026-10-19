// The parser of the decompiled text: its tokens (text_lexer.hpp) into a
// Program (text_ast.hpp). Ragel machines (AGENTS.md rule 2), one per
// function, over the tokens: a logical line's statement, an expression (an
// operator-precedence machine: explicit stacks of operands and operators),
// a signature (fcall/fret for the tuple types), then the blocks, from the
// lines' indentation (fcall/fret for each block, an explicit stack).
//
// The grammar is written down in text_grammar.md (the scratchpad's report).
#pragma once

#include "validate/text_ast.hpp"

#include <optional>
#include <span>
#include <string_view>

namespace validate::text
{
/// The program of a decompiled text. A line that can't be parsed is left
/// out and said in Program::errors (the rest is parsed).
Program parse(std::string_view text);

/// keccak-256 of a signature: its first 4 bytes, a function's selector.
std::uint32_t selector_of(std::string_view signature);

/// A param's type from its text (`uint256`, `array`, `(uint256,bytes)[]`),
/// read as a signature's; nullopt when it isn't one.
std::optional<PType> parse_type(std::string_view type);

/// What the text doesn't print of a param of an unknown function, of the
/// fallback: where it is in calldata - and, for a param the text doesn't
/// type (a _paramN of _fallback(?)), its type.
struct ParamPlace
{
    std::uint32_t offset = 4;   ///< the calldata offset of its first head word
    std::optional<PType> type;  ///< none: a word (or the type the text prints)
};

/// The side information of the params of the function of a selector
/// (nullopt: the fallback) whose places the text doesn't say -
/// `unknown1234abcd(uint256 _param1, array _param2)`, `_fallback(?)`'s
/// `_param1`...: the words of calldata it reads, named _param1, _param2...
/// in their order, not at consecutive places. places[i] is the i-th
/// param's. It comes from the asm's JSON today (`params: {"4": ["uint256",
/// "_param1"], "324": ["array", "_param2"]}`), from the decompiler's own
/// data later (a param's name id -> its offset, its type). Without it, the
/// i-th param is at 4 + 32 i (Function::placed tells which). False when
/// there's no such function, or not as many places as params.
bool place_params(Program& program, std::optional<std::uint32_t> selector, std::span<const ParamPlace> places);
}  // namespace validate::text
