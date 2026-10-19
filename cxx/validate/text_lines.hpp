// The kinds of the logical lines, the alphabet of the parser's block machine
// (text_parser.rl imports it: explicit values).
#pragma once

#include <cstdint>

namespace validate::text
{
enum LineKind : std::uint8_t
{
    LK_NONE = 0,
    LK_INDENT = 1,        ///< the lines after go deeper
    LK_DEDENT = 2,        ///< back to the indentation of an enclosing block
    LK_CONST = 3,         ///< const name = data
    LK_DEF_STORAGE = 4,   ///< def storage:
    LK_STOR_ITEM = 5,     ///< name is type at storage N
    LK_DEF_SAFEMATH = 6,  ///< def SafeMath:
    LK_SM_DEF = 7,        ///< def add(a, b): (in def SafeMath:)
    LK_DEF_FUNC = 8,      ///< def f(...):
    LK_DEF_INTERNAL = 9,  ///< def internal_0x1a2(...): # recursive...
    LK_IF = 10,
    LK_ELSE = 11,
    LK_WHILE = 12,
    LK_SIMPLE = 13,       ///< a statement of one line
    LK_CALL = 14,         ///< call x.f(...) with:
    LK_FUNCT = 15,        ///< funct x (of a call)
    LK_VALUE = 16,        ///< value x wei
    LK_GAS = 17,          ///< gas x
    LK_ARGS = 18,         ///< args x, y
    LK_MEMRET = 19,       ///< return memory, revert with memory
    LK_FROM = 20,         ///< from x
    LK_LEN = 21,          ///< len x
    LK_TO = 22,           ///< to x
    LK_CREATE = 23,       ///< create contract with x wei, create2 ...
    LK_SALT = 24,         ///< salt: x
    LK_CODE = 25,         ///< code: data
    LK_COUNT = 26
};
}  // namespace validate::text
