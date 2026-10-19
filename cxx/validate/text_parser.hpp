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

/// Sets the calldata positions of the params of the function of a selector,
/// of the fallback (nullopt) - what the text doesn't say for an unknown
/// function, for the fallback: their params are the words of calldata they
/// read, named _param1, _param2... in their order. False when there's no
/// such function, or not as many params.
bool place_params(Program& program, std::optional<std::uint32_t> selector, std::span<const std::uint32_t> positions);
}  // namespace validate::text
