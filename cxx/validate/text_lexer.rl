// The scanner of the decompiled text (AGENTS.md rule 2: a Ragel machine):
// its tokens, in logical lines (text_lexer.hpp).
#include "validate/text_lexer.hpp"

#include <array>

namespace validate::text
{
namespace
{
bool opens(Tok kind) noexcept
{
    switch (kind)
    {
    case T_LPAREN:
    case T_LBRACK:
    case T_IDENT_CALL:
    case T_DOT_CALL:
    case T_DOT_MEM_B:
    case T_DOT_DATA_B:
    case T_MEM_B:
    case T_CD_B:
    case T_STOR_B:
    case T_TRANSIENT_B:
    case T_CALLDATA_B:
    case T_RETDATA_B:
    case T_CODEDATA_B:
    case T_MASK_C:
    case T_BYTES_C:
    case T_ARRAY_C:
    case T_CONCAT_C:
    case T_SHA3_C:
    case T_CEIL32_C:
    case T_FLOOR32_C:
    case T_MIN_C:
    case T_MAX_C:
    case T_BYTE_C:
    case T_CLZ_C:
    case T_SIGNEXTEND_C:
    case T_SHIFT_C:
    case T_ADDMOD_C:
    case T_MULMOD_C:
    case T_BOOL_C:
    case T_UINT_C:
    case T_ADDRESS_C:
    case T_INT_C:
    case T_BALANCE_C:
    case T_EXTSIZE_C:
    case T_EXTHASH_C:
    case T_EXTCODE_C:
    case T_BLOCKHASH_C:
    case T_BLOBHASH_C:
    case T_SELFDESTRUCT_C:
    case T_PANIC_C:
    case T_SAFEMATH_C:
    case T_INTERNAL_C:
    case T_PRECOMPILE_C:
    case T_FALLBACK_C:
        return true;
    default:
        return false;
    }
}

/// What the scanner's actions build.
class Builder
{
public:
    explicit Builder(Lexed& out) : out_(out) {}

    void token(Tok kind, const unsigned char* ts, const unsigned char* te, std::uint16_t aux = 0)
    {
        if (!open_)
        {
            line_.first = static_cast<std::uint32_t>(out_.tokens.size());
            line_.indent = indent_;
            line_.number = number_;
            open_ = true;
        }
        out_.kinds.push_back(kind);
        out_.tokens.push_back({kind, aux, static_cast<std::uint32_t>(ts - base_),
            static_cast<std::uint32_t>(te - base_)});
        last_ = kind;
        if (opens(kind))
            ++depth_;
        else if (kind == T_RPAREN || kind == T_RBRACK)
        {
            if (depth_ == 0)
                fail("a closing bracket without its opening one");
            else
                --depth_;
        }
    }

    /// A newline and the indentation after it: the line ends, unless a
    /// bracket is open or it ends with a comma.
    void newline(const unsigned char* ts, const unsigned char* te)
    {
        ++number_;
        indent_ = static_cast<std::uint32_t>(te - ts - 1);
        if (depth_ == 0 && last_ != T_COMMA)
            end_line();
    }

    void end()
    {
        if (depth_ != 0)
            fail("an unclosed bracket");
        end_line();
    }

    void fail(const char* message)
    {
        if (out_.error.empty())
        {
            out_.error = message;
            out_.error_line = number_;
        }
    }

    void set_base(const unsigned char* base) { base_ = base; }

private:
    void end_line()
    {
        if (!open_)
            return;
        const auto at = static_cast<std::uint32_t>(out_.tokens.empty() ? 0 : out_.tokens.back().end);
        out_.kinds.push_back(T_EOL);
        out_.tokens.push_back({T_EOL, 0, at, at});
        line_.last = static_cast<std::uint32_t>(out_.tokens.size());
        out_.lines.push_back(line_);
        open_ = false;
        last_ = T_EOL;
    }

    Lexed& out_;
    const unsigned char* base_ = nullptr;
    Line line_;
    bool open_ = false;
    Tok last_ = T_NONE;
    unsigned depth_ = 0;
    std::uint32_t indent_ = 0;
    std::uint32_t number_ = 1;
};
}  // namespace

%%{
  machine text_lexer;
  alphtype unsigned char;

  action newline { b.newline(ts, te); }

  prime = 0xe2 0x80 0xb2;
  wc = [A-Za-z_0-9];
  word = [A-Za-z_] wc*;
  esc = '\\' [^\n];
  sp = ' '*;
  precompile_word = 'ecrecover' | 'sha256hash' | 'ripemd160hash' | 'identity' | 'bigModExp'
                  | 'bn256Add' | 'bn256ScalarMul' | 'bn256Pairing';

  main := |*
    '\n' ' '* => newline;
    ' '+;
    '\r';

    # the comments of the headers (before any other comment: the first of
    # the longest matches is taken)
    '# not payable' sp => { b.token(T_C_NOT_PAYABLE, ts, te); };
    '# not payable (invalid)' sp => { b.token(T_C_NOT_PAYABLE_INVALID, ts, te); };
    '# default function' sp => { b.token(T_C_DEFAULT, ts, te); };
    '# not payable, default function' sp => { b.token(T_C_NOT_PAYABLE_DEFAULT, ts, te); };
    '# recursive, a call takes ' [0-9]+ ' of the 1024 words of the stack' sp
        => { b.token(T_C_RECURSIVE, ts, te); };
    '# precompiled' sp => { b.token(T_C_PRECOMPILED, ts, te); };
    '# solidity >= 0.8' sp => { b.token(T_C_SOLIDITY08, ts, te); };
    '# Decompilation aborted, sorry: ' [^\n]* => { b.token(T_C_ABORTED, ts, te); };
    '#' [^\n]* => { b.token(T_COMMENT, ts, te); };

    # literals
    [0-9]+ => { b.token(T_NUM, ts, te); };
    '0x' [0-9a-fA-F]+ => { b.token(T_HEX, ts, te); };
    "'" ( [^'\\\n] | esc )* "'" => { b.token(T_STR, ts, te); };

    # punctuation and operators
    '(' => { b.token(T_LPAREN, ts, te); };
    ')' => { b.token(T_RPAREN, ts, te); };
    '[' => { b.token(T_LBRACK, ts, te); };
    ']' => { b.token(T_RBRACK, ts, te); };
    ',' => { b.token(T_COMMA, ts, te); };
    ':' => { b.token(T_COLON, ts, te); };
    '.' => { b.token(T_DOT, ts, te); };
    '?' => { b.token(T_QMARK, ts, te); };
    '...' => { b.token(T_ELLIPSIS, ts, te); };
    '=' => { b.token(T_ASSIGN, ts, te); };
    '+=' => { b.token(T_PLUSEQ, ts, te); };
    '-=' => { b.token(T_MINUSEQ, ts, te); };
    '++' => { b.token(T_PLUSPLUS, ts, te); };
    '--' => { b.token(T_MINUSMINUS, ts, te); };
    '+' => { b.token(T_PLUS, ts, te); };
    '-' => { b.token(T_MINUS, ts, te); };
    '*' => { b.token(T_STAR, ts, te); };
    '/' => { b.token(T_SLASH, ts, te); };
    '%' => { b.token(T_PERCENT, ts, te); };
    '**' => { b.token(T_POW, ts, te); };
    '<<' => { b.token(T_SHL, ts, te); };
    '>>' => { b.token(T_SHR, ts, te); };
    '>>' prime => { b.token(T_SAR, ts, te); };
    '&' => { b.token(T_AMP, ts, te); };
    '|' => { b.token(T_PIPE, ts, te); };
    '^' => { b.token(T_CARET, ts, te); };
    '~' => { b.token(T_TILDE, ts, te); };
    '==' => { b.token(T_EQ, ts, te); };
    '!=' => { b.token(T_NE, ts, te); };
    '<' => { b.token(T_LT, ts, te); };
    '>' => { b.token(T_GT, ts, te); };
    '<=' => { b.token(T_LE, ts, te); };
    '>=' => { b.token(T_GE, ts, te); };
    '<' prime => { b.token(T_SLT, ts, te); };
    '>' prime => { b.token(T_SGT, ts, te); };
    '<=' prime => { b.token(T_SLE, ts, te); };
    '>=' prime => { b.token(T_SGE, ts, te); };
    '+' prime => { b.token(T_SADD, ts, te); };
    '*' prime => { b.token(T_SMUL, ts, te); };
    '/' prime => { b.token(T_SDIV, ts, te); };
    '%' prime => { b.token(T_SMOD, ts, te); };

    # members and subscripts
    '.length' => { b.token(T_DOT_LENGTH, ts, te); };
    '.field_' [0-9]+ => { b.token(T_DOT_FIELD, ts, te); };
    '.mem[' => { b.token(T_DOT_MEM_B, ts, te); };
    '.data[' => { b.token(T_DOT_DATA_B, ts, te); };
    '.' word => { b.token(T_DOT_MEMBER, ts, te); };
    '.' word '(' => { b.token(T_DOT_CALL, ts, te); };
    '[all]' => { b.token(T_ALL, ts, te); };

    # the keywords of the statements
    'def' => { b.token(T_DEF, ts, te); };
    'const' => { b.token(T_CONST, ts, te); };
    'if' => { b.token(T_IF, ts, te); };
    'else' => { b.token(T_ELSE, ts, te); };
    'while' => { b.token(T_WHILE, ts, te); };
    'continue' => { b.token(T_CONTINUE, ts, te); };
    'break' => { b.token(T_BREAK, ts, te); };
    'require' => { b.token(T_REQUIRE, ts, te); };
    'assert' => { b.token(T_ASSERT, ts, te); };
    'revert' => { b.token(T_REVERT, ts, te); };
    'return' => { b.token(T_RETURN, ts, te); };
    'stop' => { b.token(T_STOP, ts, te); };
    'invalid' => { b.token(T_INVALID, ts, te); };
    'log' => { b.token(T_LOG, ts, te); };
    'call' => { b.token(T_CALL, ts, te); };
    'static call' => { b.token(T_STATIC_CALL, ts, te); };
    'delegate' => { b.token(T_DELEGATE, ts, te); };
    'codecall' => { b.token(T_CODECALL, ts, te); };
    'create' => { b.token(T_CREATE, ts, te); };
    'create2' => { b.token(T_CREATE2, ts, te); };
    'not' => { b.token(T_NOT, ts, te); };
    'and' => { b.token(T_AND, ts, te); };
    'or' => { b.token(T_OR, ts, te); };
    'True' => { b.token(T_TRUE, ts, te); };
    'False' => { b.token(T_FALSE, ts, te); };
    'SafeMath' => { b.token(T_SAFEMATH, ts, te); };

    # the soft keywords
    'with' => { b.token(T_WITH, ts, te); };
    'memory' => { b.token(T_MEMORY, ts, te); };
    'from' => { b.token(T_FROM, ts, te); };
    'to' => { b.token(T_TO, ts, te); };
    'len' => { b.token(T_LEN, ts, te); };
    'value' => { b.token(T_VALUE, ts, te); };
    'wei' => { b.token(T_WEI, ts, te); };
    'gas' => { b.token(T_GAS, ts, te); };
    'args' => { b.token(T_ARGS, ts, te); };
    'funct' => { b.token(T_FUNCT, ts, te); };
    'indexed' => { b.token(T_INDEXED, ts, te); };
    'contract' => { b.token(T_CONTRACT, ts, te); };
    'code' => { b.token(T_CODE, ts, te); };
    'salt' => { b.token(T_SALT, ts, te); };
    'storage' => { b.token(T_STORAGE, ts, te); };
    'is' => { b.token(T_IS, ts, te); };
    'at' => { b.token(T_AT, ts, te); };
    'offset' => { b.token(T_OFFSET, ts, te); };
    'of' => { b.token(T_OF, ts, te); };
    'mapping' => { b.token(T_MAPPING, ts, te); };
    'fixed' => { b.token(T_FIXED, ts, te); };
    'struct' => { b.token(T_STRUCT, ts, te); };
    'slot' => { b.token(T_SLOT, ts, te); };
    'slots' => { b.token(T_SLOTS, ts, te); };
    'payable' => { b.token(T_PAYABLE, ts, te); };

    # the types
    'uint' [0-9]* => { b.token(T_TYPE, ts, te); };
    'int' [0-9]* => { b.token(T_TYPE, ts, te); };
    'bytes' [0-9]+ => { b.token(T_TYPE, ts, te); };
    'address' => { b.token(T_TYPE, ts, te); };
    'bool' => { b.token(T_TYPE, ts, te); };
    'string' => { b.token(T_BYTES, ts, te); };
    'function' => { b.token(T_TYPE, ts, te); };
    'bytes' => { b.token(T_BYTES, ts, te); };
    'array' => { b.token(T_ARRAY, ts, te); };

    # the values the EVM gives
    'caller' => { b.token(T_CALLER, ts, te); };
    'tx.origin' => { b.token(T_ORIGIN, ts, te); };
    'tx.gasprice' => { b.token(T_GASPRICE, ts, te); };
    'call.value' => { b.token(T_CALLVALUE, ts, te); };
    'call.func_hash' => { b.token(T_FUNC_HASH, ts, te); };
    'calldata.size' => { b.token(T_CALLDATASIZE, ts, te); };
    'return_data.size' => { b.token(T_RETDATASIZE, ts, te); };
    'this.address' => { b.token(T_THIS, ts, te); };
    'gas_remaining' => { b.token(T_GAS_REMAINING, ts, te); };
    'chainid' => { b.token(T_CHAINID, ts, te); };
    'msize' => { b.token(T_MSIZE, ts, te); };
    'block.number' => { b.token(T_NUMBER, ts, te); };
    'block.timestamp' => { b.token(T_TIMESTAMP, ts, te); };
    'block.coinbase' => { b.token(T_COINBASE, ts, te); };
    'block.difficulty' => { b.token(T_DIFFICULTY, ts, te); };
    'block.gas_limit' => { b.token(T_GASLIMIT, ts, te); };
    'block.basefee' => { b.token(T_BASEFEE, ts, te); };
    'block.blobbasefee' => { b.token(T_BLOBBASEFEE, ts, te); };
    ( 'ext_call.success' | 'delegate.return_code' | 'callcode.return_code' | 'memcopy.success'
    | precompile_word '.result' ) => { b.token(T_CALL_SUCCESS, ts, te); };
    'create.new_address' => { b.token(T_CREATE_ADDR, ts, te, 0); };
    'create2.new_address' => { b.token(T_CREATE_ADDR, ts, te, 1); };

    # the builtins written with their bracket
    'mem[' => { b.token(T_MEM_B, ts, te); };
    'cd[' => { b.token(T_CD_B, ts, te); };
    'stor[' => { b.token(T_STOR_B, ts, te); };
    'transient[' => { b.token(T_TRANSIENT_B, ts, te); };
    'call.data[' => { b.token(T_CALLDATA_B, ts, te); };
    ( 'ext_call' | 'delegate' | 'callcode' | 'staticcall' ) '.return_data['
        => { b.token(T_RETDATA_B, ts, te); };
    'code.data[' => { b.token(T_CODEDATA_B, ts, te); };

    # the builtin functions written with their parenthesis
    'Mask(' => { b.token(T_MASK_C, ts, te); };
    'Bytes(' => { b.token(T_BYTES_C, ts, te); };
    'Array(' => { b.token(T_ARRAY_C, ts, te); };
    'concat(' => { b.token(T_CONCAT_C, ts, te); };
    'sha3(' => { b.token(T_SHA3_C, ts, te); };
    'ceil32(' => { b.token(T_CEIL32_C, ts, te); };
    'floor32(' => { b.token(T_FLOOR32_C, ts, te); };
    'min(' => { b.token(T_MIN_C, ts, te); };
    'max(' => { b.token(T_MAX_C, ts, te); };
    'byte(' => { b.token(T_BYTE_C, ts, te); };
    'clz(' => { b.token(T_CLZ_C, ts, te); };
    'signextend(' => { b.token(T_SIGNEXTEND_C, ts, te); };
    'shift(' => { b.token(T_SHIFT_C, ts, te); };
    'addmod(' => { b.token(T_ADDMOD_C, ts, te); };
    'mulmod(' => { b.token(T_MULMOD_C, ts, te); };
    'bool(' => { b.token(T_BOOL_C, ts, te); };
    'uint' [0-9]+ '(' => { b.token(T_UINT_C, ts, te); };
    'address(' => { b.token(T_ADDRESS_C, ts, te); };
    'int' [0-9]+ '(' => { b.token(T_INT_C, ts, te); };
    'eth.balance(' => { b.token(T_BALANCE_C, ts, te); };
    'ext_code.size(' => { b.token(T_EXTSIZE_C, ts, te); };
    'ext_code.hash(' => { b.token(T_EXTHASH_C, ts, te); };
    'ext_code(' => { b.token(T_EXTCODE_C, ts, te); };
    'block.hash(' => { b.token(T_BLOCKHASH_C, ts, te); };
    'blobhash(' => { b.token(T_BLOBHASH_C, ts, te); };
    'selfdestruct(' => { b.token(T_SELFDESTRUCT_C, ts, te); };
    'Panic(' => { b.token(T_PANIC_C, ts, te); };
    'SafeMath.' word '(' => { b.token(T_SAFEMATH_C, ts, te); };
    'internal_0x' [0-9a-f]+ '(' => { b.token(T_INTERNAL_C, ts, te); };
    'ecrecover(' => { b.token(T_PRECOMPILE_C, ts, te, 1); };
    'sha256hash(' => { b.token(T_PRECOMPILE_C, ts, te, 2); };
    'ripemd160hash(' => { b.token(T_PRECOMPILE_C, ts, te, 3); };
    'identity(' => { b.token(T_PRECOMPILE_C, ts, te, 4); };
    'bigModExp(' => { b.token(T_PRECOMPILE_C, ts, te, 5); };
    'bn256Add(' => { b.token(T_PRECOMPILE_C, ts, te, 6); };
    'bn256ScalarMul(' => { b.token(T_PRECOMPILE_C, ts, te, 7); };
    'bn256Pairing(' => { b.token(T_PRECOMPILE_C, ts, te, 8); };
    '_fallback(' => { b.token(T_FALLBACK_C, ts, te); };

    # the names (after the keywords: of the longest matches, the first)
    'len=' => { b.token(T_LEN_EQ, ts, te); };
    'data=' => { b.token(T_DATA_EQ, ts, te); };
    word => { b.token(T_IDENT, ts, te); };
    word '(' => { b.token(T_IDENT_CALL, ts, te); };
    word '=' => { b.token(T_IDENT_EQ, ts, te); };

    any => { b.fail("a character no token starts with"); };
  *|;
}%%

%% write data noerror nofinal noentry;

Lexed lex(std::string_view text)
{
    Lexed out;
    out.kinds.reserve(text.size() / 3);
    out.tokens.reserve(text.size() / 3);
    Builder b(out);
    const auto* p = reinterpret_cast<const unsigned char*>(text.data());
    const auto* pe = p + text.size();
    const auto* eof = pe;
    const unsigned char* ts = nullptr;
    const unsigned char* te = nullptr;
    int cs;
    int act;
    b.set_base(p);
    %% write init;
    %% write exec;
    (void)act;
    b.end();
    return out;
}

std::string_view token_name(Tok kind) noexcept
{
    static constexpr std::array<std::string_view, T_COUNT> names = {
        "none", "end of line",
        "# not payable", "# not payable (invalid)", "# default function",
        "# not payable, default function", "# recursive...", "# precompiled",
        "# solidity >= 0.8", "# Decompilation aborted...", "a comment",
        "a number", "a hex number", "a string", "a name", "name(", "name=", "len=", "data=",
        "a type", "bytes", "array",
        "(", ")", "[", "]", ",", ":", ".", "?", "...", "=", "+=", "-=", "++", "--",
        "+", "-", "*", "/", "%", "**", "<<", ">>", ">>′", "&", "|", "^", "~",
        "==", "!=", "<", ">", "<=", ">=", "<′", ">′", "<=′", ">=′", "+′", "*′", "/′", "%′",
        ".length", ".field_N", ".member", ".name(", ".mem[", ".data[", "[all]",
        "def", "const", "if", "else", "while", "continue", "break", "require", "assert",
        "revert", "return", "stop", "invalid", "log", "call", "static call", "delegate",
        "codecall", "create", "create2", "not", "and", "or", "True", "False", "SafeMath",
        "with", "memory", "from", "to", "len", "value", "wei", "gas", "args", "funct",
        "indexed", "contract", "code", "salt", "storage", "is", "at", "offset", "of",
        "mapping", "fixed", "struct", "slot", "slots", "payable",
        "caller", "tx.origin", "tx.gasprice", "call.value", "call.func_hash", "calldata.size",
        "return_data.size", "this.address", "gas_remaining", "chainid", "msize",
        "block.number", "block.timestamp", "block.coinbase", "block.difficulty",
        "block.gas_limit", "block.basefee", "block.blobbasefee", "ext_call.success",
        "create.new_address",
        "mem[", "cd[", "stor[", "transient[", "call.data[", "ext_call.return_data[",
        "code.data[",
        "Mask(", "Bytes(", "Array(", "concat(", "sha3(", "ceil32(", "floor32(", "min(", "max(",
        "byte(", "clz(", "signextend(", "shift(", "addmod(", "mulmod(", "bool(", "uintN(",
        "address(", "intN(", "eth.balance(", "ext_code.size(", "ext_code.hash(", "ext_code(",
        "block.hash(", "blobhash(", "selfdestruct(", "Panic(", "SafeMath.f(", "internal_0x..(",
        "a precompile(", "_fallback(",
    };
    return kind < T_COUNT ? names[kind] : std::string_view("?");
}
}  // namespace validate::text
