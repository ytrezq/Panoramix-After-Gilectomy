// The tokens of the decompiled text (the asm's display, see
// docs of validate/text_parser.rl), made by a Ragel scanner (text_lexer.rl,
// AGENTS.md rule 2): the text in logical lines - a line goes on after an
// open bracket and after a trailing comma - each with its indentation.
//
// A word that the text gives a meaning to is its own token: the keywords
// (`if`, `revert`...), the builtins (`caller`, `block.number`, `mem[`...),
// the calls of the builtin functions (`sha3(`, `uint8(`: the word and its
// parenthesis, written together in the text), the comments the headers end
// with. A word the text may also use as a name (`value`, `from`, `data`...)
// is a "soft" keyword: the parser takes it for a name where a name goes.
#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace validate::text
{
enum Tok : std::uint16_t
{
    T_NONE = 0,
    T_EOL = 1,  ///< the end of a logical line

    // comments: the ones of the headers, then any other (ignored)
    T_C_NOT_PAYABLE = 2,          ///< # not payable
    T_C_NOT_PAYABLE_INVALID = 3,  ///< # not payable (invalid)
    T_C_DEFAULT = 4,              ///< # default function
    T_C_NOT_PAYABLE_DEFAULT = 5,  ///< # not payable, default function
    T_C_RECURSIVE = 6,            ///< # recursive, a call takes N of the 1024 words of the stack
    T_C_PRECOMPILED = 7,          ///< # precompiled
    T_C_SOLIDITY08 = 8,           ///< # solidity >= 0.8
    T_C_ABORTED = 9,              ///< # Decompilation aborted, sorry: ...
    T_COMMENT = 10,                ///< any other # ...

    // literals and names
    T_NUM = 11,         ///< 123
    T_HEX = 12,         ///< 0x1f
    T_STR = 13,         ///< 'text' (with its quotes and escapes)
    T_IDENT = 14,       ///< a name
    T_IDENT_CALL = 15,  ///< name( - a signature: def f(, log Transfer(, Error(
    T_IDENT_EQ = 16,    ///< name= - a param of a log: from=caller
    T_LEN_EQ = 17,      ///< len= (of Array(len=...))
    T_DATA_EQ = 18,     ///< data= (of Array(..., data=...))
    T_TYPE = 19,        ///< uint256, int24, address, bool, bytes32, function
    T_BYTES = 20,       ///< bytes, string (a type of a param, of the storage: dynamic)
    T_ARRAY = 21,       ///< array (of the storage; a type the decompiler gives a param)

    // punctuation, operators
    T_LPAREN = 22,
    T_RPAREN = 23,
    T_LBRACK = 24,
    T_RBRACK = 25,
    T_COMMA = 26,
    T_COLON = 27,
    T_DOT = 28,
    T_QMARK = 29,
    T_ELLIPSIS = 30,   ///< ...
    T_ASSIGN = 31,     ///< =
    T_PLUSEQ = 32,     ///< +=
    T_MINUSEQ = 33,    ///< -=
    T_PLUSPLUS = 34,   ///< ++
    T_MINUSMINUS = 35, ///< --
    T_PLUS = 36,
    T_MINUS = 37,
    T_STAR = 38,
    T_SLASH = 39,
    T_PERCENT = 40,
    T_POW = 41,        ///< **
    T_SHL = 42,        ///< <<
    T_SHR = 43,        ///< >>
    T_SAR = 44,        ///< >>′
    T_AMP = 45,        ///< &
    T_PIPE = 46,       ///< |
    T_CARET = 47,      ///< ^
    T_TILDE = 48,      ///< ~
    T_EQ = 49,         ///< ==
    T_NE = 50,         ///< !=
    T_LT = 51,
    T_GT = 52,
    T_LE = 53,
    T_GE = 54,
    T_SLT = 55,        ///< <′
    T_SGT = 56,        ///< >′
    T_SLE = 57,        ///< <=′
    T_SGE = 58,        ///< >=′
    T_SADD = 59,       ///< +′
    T_SMUL = 60,       ///< *′
    T_SDIV = 61,       ///< /′
    T_SMOD = 62,       ///< %′

    // members and subscripts written with their dot or bracket
    T_DOT_LENGTH = 63,  ///< .length
    T_DOT_FIELD = 64,   ///< .field_N
    T_DOT_MEMBER = 65,  ///< .name - a member of a struct param
    T_DOT_CALL = 66,    ///< .name( - the function an external call calls
    T_DOT_MEM_B = 67,   ///< .mem[ - an external call's selector in memory
    T_DOT_DATA_B = 68,  ///< .data[ - ext_code(a).data[...]
    T_ALL = 69,         ///< [all]

    // the keywords of the statements
    T_DEF = 70,
    T_CONST = 71,
    T_IF = 72,
    T_ELSE = 73,
    T_WHILE = 74,
    T_CONTINUE = 75,
    T_BREAK = 76,
    T_REQUIRE = 77,
    T_ASSERT = 78,
    T_REVERT = 79,
    T_RETURN = 80,
    T_STOP = 81,
    T_INVALID = 82,
    T_LOG = 83,
    T_CALL = 84,         ///< call (a statement)
    T_STATIC_CALL = 85,  ///< static call
    T_DELEGATE = 86,
    T_CODECALL = 87,
    T_CREATE = 88,
    T_CREATE2 = 89,
    T_NOT = 90,
    T_AND = 91,
    T_OR = 92,
    T_TRUE = 93,
    T_FALSE = 94,
    T_SAFEMATH = 95,  ///< SafeMath (def SafeMath:)

    // soft keywords: names elsewhere
    T_WITH = 96,
    T_MEMORY = 97,
    T_FROM = 98,
    T_TO = 99,
    T_LEN = 100,
    T_VALUE = 101,
    T_WEI = 102,
    T_GAS = 103,
    T_ARGS = 104,
    T_FUNCT = 105,
    T_INDEXED = 106,
    T_CONTRACT = 107,
    T_CODE = 108,
    T_SALT = 109,
    T_STORAGE = 110,
    T_IS = 111,
    T_AT = 112,
    T_OFFSET = 113,
    T_OF = 114,
    T_MAPPING = 115,
    T_FIXED = 116,
    T_STRUCT = 117,
    T_SLOT = 118,
    T_SLOTS = 119,
    T_PAYABLE = 120,

    // the values the EVM gives
    T_CALLER = 121,
    T_ORIGIN = 122,         ///< tx.origin
    T_GASPRICE = 123,       ///< tx.gasprice
    T_CALLVALUE = 124,      ///< call.value
    T_FUNC_HASH = 125,      ///< call.func_hash
    T_CALLDATASIZE = 126,   ///< calldata.size
    T_RETDATASIZE = 127,    ///< return_data.size
    T_THIS = 128,           ///< this.address
    T_GAS_REMAINING = 129,  ///< gas_remaining
    T_CHAINID = 130,
    T_MSIZE = 131,
    T_NUMBER = 132,         ///< block.number
    T_TIMESTAMP = 133,      ///< block.timestamp
    T_COINBASE = 134,       ///< block.coinbase
    T_DIFFICULTY = 135,     ///< block.difficulty
    T_GASLIMIT = 136,       ///< block.gas_limit
    T_BASEFEE = 137,        ///< block.basefee
    T_BLOBBASEFEE = 138,    ///< block.blobbasefee
    T_CALL_SUCCESS = 139,   ///< ext_call.success, delegate.return_code, callcode.return_code,
                      ///< memcopy.success, ecrecover.result...
    T_CREATE_ADDR = 140,    ///< create.new_address, create2.new_address

    // the builtins written with their bracket
    T_MEM_B = 141,       ///< mem[
    T_CD_B = 142,        ///< cd[
    T_STOR_B = 143,      ///< stor[
    T_TRANSIENT_B = 144, ///< transient[
    T_CALLDATA_B = 145,  ///< call.data[
    T_RETDATA_B = 146,   ///< ext_call.return_data[ (delegate., callcode., staticcall.)
    T_CODEDATA_B = 147,  ///< code.data[

    // the builtin functions written with their parenthesis
    T_MASK_C = 148,        ///< Mask(
    T_BYTES_C = 149,       ///< Bytes(
    T_ARRAY_C = 150,       ///< Array(
    T_CONCAT_C = 151,      ///< concat(
    T_SHA3_C = 152,        ///< sha3(
    T_CEIL32_C = 153,      ///< ceil32(
    T_FLOOR32_C = 154,     ///< floor32(
    T_MIN_C = 155,         ///< min(
    T_MAX_C = 156,         ///< max(
    T_BYTE_C = 157,        ///< byte(
    T_CLZ_C = 158,         ///< clz(
    T_SIGNEXTEND_C = 159,  ///< signextend(
    T_SHIFT_C = 160,       ///< shift(
    T_ADDMOD_C = 161,      ///< addmod(
    T_MULMOD_C = 162,      ///< mulmod(
    T_BOOL_C = 163,        ///< bool(
    T_UINT_C = 164,        ///< uint8( ... uint256(
    T_ADDRESS_C = 165,     ///< address(
    T_INT_C = 166,         ///< int8( ... int256(
    T_BALANCE_C = 167,     ///< eth.balance(
    T_EXTSIZE_C = 168,     ///< ext_code.size(
    T_EXTHASH_C = 169,     ///< ext_code.hash(
    T_EXTCODE_C = 170,     ///< ext_code(
    T_BLOCKHASH_C = 171,   ///< block.hash(
    T_BLOBHASH_C = 172,    ///< blobhash(
    T_SELFDESTRUCT_C = 173,///< selfdestruct(
    T_PANIC_C = 174,       ///< Panic(
    T_SAFEMATH_C = 175,    ///< SafeMath.name(
    T_INTERNAL_C = 176,    ///< internal_0x1a2(
    T_PRECOMPILE_C = 177,  ///< ecrecover(, sha256hash(, ripemd160hash(, identity(, bigModExp(,
                     ///< bn256Add(, bn256ScalarMul(, bn256Pairing(
    T_FALLBACK_C = 178,  ///< _fallback( (def _fallback(?))

    T_COUNT = 179
};

/// A token: its kind and where it is in the text.
struct Token
{
    Tok kind = T_NONE;
    /// What the scanner knows of it: the precompile of a T_PRECOMPILE_C
    /// (its address), the kind of call of a T_CALL_SUCCESS (CallKind + 1, 0
    /// for a precompile), create2 for a T_CREATE_ADDR (1).
    std::uint16_t aux = 0;
    std::uint32_t begin = 0;  ///< byte offsets in the text
    std::uint32_t end = 0;
};

/// A logical line: its tokens [first, last) - the last one a T_EOL - its
/// indentation, the number of its first line in the text (from 1).
struct Line
{
    std::uint32_t first = 0;
    std::uint32_t last = 0;
    std::uint32_t indent = 0;
    std::uint32_t number = 0;
};

struct Lexed
{
    /// The kinds of the tokens, apart: the input of the parser's machines.
    std::vector<std::uint16_t> kinds;
    std::vector<Token> tokens;
    std::vector<Line> lines;
    /// The first error (a character no token starts with, an unbalanced
    /// bracket), empty when there is none; error_line its line.
    std::string error;
    std::uint32_t error_line = 0;
};

/// The tokens of a text.
Lexed lex(std::string_view text);

/// The name of a kind of token (diagnostics, tests).
std::string_view token_name(Tok kind) noexcept;
}  // namespace validate::text
