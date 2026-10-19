// Hex text into bytes: the first thing done to bytecode that comes as text
// (a file, standard input, the command line, a node's answer, a python
// str), so that nothing after it ever sees hex. And the other way for
// messages: bytes from outside escaped into printable text.
#pragma once

#include <cstddef>
#include <cstdint>
#include <expected>
#include <string>
#include <string_view>
#include <vector>

namespace pan::hex {

// Why a text isn't hex: the offset of the first byte that can't be there,
// or (odd) the text ends in the middle of a byte.
struct DecodeError {
    std::size_t offset = 0;
    bool odd = false;
};

// The bytes of a hex text: digits of either case, blanks (space, tab, CR,
// LF) anywhere - between the two digits of a byte too, as the asm's
// hex_decode -, and a 0x or 0X prefix after the leading blanks. An empty
// text (or a bare prefix) is no bytes.
std::expected<std::vector<std::uint8_t>, DecodeError> decode(std::string_view text);

// The first `max` bytes of a text from outside (a node's answer, an
// argument echoed back) as printable ASCII: every other byte, and the
// backslash, as \xNN - so that it can't forge lines nor drive a terminal,
// and a megabyte of it doesn't become the message.
std::string escape(std::string_view bytes, std::size_t max = std::string_view::npos);

}  // namespace pan::hex
