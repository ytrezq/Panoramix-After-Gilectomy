// The parser of the decompiled text (text_parser.hpp): Ragel machines, one
// per function (AGENTS.md rule 2), over the tokens of text_lexer.rl.
//
//   parse_line   a logical line: its statement (or definition, or the line
//                of a statement that goes on: `gas`, `args`, `from`...)
//   parse_expr   an expression: an operator-precedence machine, its
//                operands and operators on explicit stacks (the brackets,
//                the calls, the subscripts too)
//   parse_sig    a signature: f(uint256 a, (address,bytes)[] b) - a tuple
//                type with fcall/fret - the types of the params, their
//                names, `indexed`, the values of a log's params
//   build        the blocks: the lines' indentation as INDENT / DEDENT, a
//                block with fcall/fret (an explicit stack)
//   and the small ones: a string literal's bytes, unknown12345678's
//   selector, a type's bits, `.field_N`'s N, the frame of `# recursive`.
#include "validate/text_parser.hpp"

#include "validate/scan.hpp"
#include "validate/text_lexer.hpp"
#include "validate/text_lines.hpp"
#include "validate/world.hpp"

#include <array>
#include <optional>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace validate::text
{
namespace
{
constexpr unsigned hex_value(unsigned char c) noexcept
{
    return c <= '9' ? c - '0' : (c | 0x20u) - 'a' + 10;
}

// The operators' precedences, python's (the text prints them so): the
// higher binds tighter.
enum Prec : std::uint8_t
{
    P_RANGE = 0,  // a len n, inside brackets
    P_OR = 1,
    P_AND = 2,
    P_NOT = 3,
    P_CMP = 4,
    P_BOR = 5,
    P_BXOR = 6,
    P_BAND = 7,
    P_SHIFT = 8,
    P_ADD = 9,
    P_MUL = 10,
    P_UNARY = 11,
    P_POW = 12,
};

struct Binary
{
    Op op;
    std::uint8_t prec;
};

std::optional<Binary> binary_of(std::uint16_t kind) noexcept
{
    switch (kind)
    {
    case T_OR: return Binary{Op::lor, P_OR};
    case T_AND: return Binary{Op::land, P_AND};
    case T_EQ: return Binary{Op::eq, P_CMP};
    case T_NE: return Binary{Op::ne, P_CMP};
    case T_LT: return Binary{Op::lt, P_CMP};
    case T_GT: return Binary{Op::gt, P_CMP};
    case T_LE: return Binary{Op::le, P_CMP};
    case T_GE: return Binary{Op::ge, P_CMP};
    case T_SLT: return Binary{Op::slt, P_CMP};
    case T_SGT: return Binary{Op::sgt, P_CMP};
    case T_SLE: return Binary{Op::sle, P_CMP};
    case T_SGE: return Binary{Op::sge, P_CMP};
    case T_PIPE: return Binary{Op::bit_or, P_BOR};
    case T_CARET: return Binary{Op::bit_xor, P_BXOR};
    case T_AMP: return Binary{Op::bit_and, P_BAND};
    case T_SHL: return Binary{Op::shl, P_SHIFT};
    case T_SHR: return Binary{Op::shr, P_SHIFT};
    case T_SAR: return Binary{Op::sar, P_SHIFT};
    case T_PLUS: return Binary{Op::add, P_ADD};
    case T_MINUS: return Binary{Op::sub, P_ADD};
    case T_SADD: return Binary{Op::sadd, P_ADD};
    case T_STAR: return Binary{Op::mul, P_MUL};
    case T_SLASH: return Binary{Op::div, P_MUL};
    case T_PERCENT: return Binary{Op::mod, P_MUL};
    case T_SMUL: return Binary{Op::smul, P_MUL};
    case T_SDIV: return Binary{Op::sdiv, P_MUL};
    case T_SMOD: return Binary{Op::smod, P_MUL};
    case T_POW: return Binary{Op::pow, P_POW};
    default: return std::nullopt;
    }
}

/// The frames of the expression machine: what a bracket opened.
enum Frame : std::uint8_t
{
    F_PAREN,       // ( x )
    F_CALL,        // f(x, y): a builtin function
    F_ARRAY,       // Array(len=l, data=...)
    F_BRACKET,     // mem[...], cd[...], stor[...]...
    F_SUBSCRIPT,   // x[k]
    F_CALLEE_MEM,  // addr.mem[a len 4]
    F_EXT_DATA,    // ext_code(a).data[s len n]
};

struct OpEntry
{
    enum Kind : std::uint8_t
    {
        k_binary,
        k_prefix,
        k_frame,
    };
    Kind kind = k_binary;
    std::uint8_t prec = 0;
    Frame fk = F_PAREN;
    Op op = Op::num;
    std::uint16_t tok_kind = 0;  // the token that opened a frame
    std::uint32_t aux = 0;
    std::uint32_t base = 0;      // a frame's first operand in the values
    ExprId target = none;        // what a subscript (callee_mem, ext_data) applies to
    std::uint32_t tok = 0;
};

/// A parsed part of a line: an expression and where it is.
struct Part
{
    ExprId e = none;
    std::uint32_t first = 0;  // its tokens [first, last)
    std::uint32_t last = 0;
    bool indexed = false;
};

/// A param of a signature.
struct SigParam
{
    PType type;
    bool typed = false;
    std::uint32_t name = none;  // its token
    bool indexed = false;
    ExprId value = none;
};

struct Sig
{
    std::string_view name;
    bool unknown = false;  // (?)
    std::vector<SigParam> params;
};

enum class SigMode : std::uint8_t
{
    selector,  // types (and names) only
    def,       // a function's header: types and names, or names only
    log,       // a log's event: types, indexed, names, name=value
};

enum class Ctx : std::uint8_t
{
    top,
    storage,
    safemath,  // def SafeMath: (its defs)
    sm_def,    // a def of SafeMath, its body
    function,
};

struct Item
{
    LineKind kind = LK_NONE;
    std::uint32_t indent = 0;
    std::uint32_t number = 0;   // its line in the text
    StmtId stmt = none;
    std::vector<ExprId> exprs;  // a line that goes on a statement: its values
    std::uint32_t def = none;   // a def: the function or the SafeMath def
};

class Parser
{
public:
    explicit Parser(std::string_view text) : text_(text), lx_(lex(text)) {}

    Program run();

private:
    // --- the tokens
    std::string_view span(std::uint32_t tok) const
    {
        const auto& t = lx_.tokens[tok];
        return text_.substr(t.begin, t.end - t.begin);
    }
    std::uint16_t kind(std::uint32_t tok) const { return lx_.kinds[tok]; }
    std::uint32_t index(const std::uint16_t* p) const { return static_cast<std::uint32_t>(p - k0_); }

    // --- the errors
    bool fail(std::uint32_t tok, std::string_view what);

    // --- the nodes
    ExprId node(Op op, std::uint32_t aux, std::span<const ExprId> kids);
    ExprId leaf(Op op, std::uint32_t aux = 0) { return node(op, aux, {}); }
    ExprId number_leaf(const Word& value);
    StmtId stmt(St kind);

    // --- the small machines
    std::optional<Word> number(std::uint32_t tok);
    static std::optional<Word> decimal_mod(std::string_view digits);
    std::optional<Bytes> string_bytes(std::string_view literal);
    static std::optional<std::uint32_t> unknown_selector(std::string_view name);
    static std::optional<std::uint32_t> type_bits(std::string_view type);
    static std::optional<std::uint32_t> field_bits(std::string_view member);
    static std::optional<std::uint32_t> recursive_frame(std::string_view comment);

    // --- the names
    ExprId name_leaf(std::uint32_t tok);
    std::uint32_t local(std::string_view name);

    // --- the expression machine and its actions
    ExprId parse_expr(std::uint32_t pos);
    void push_val(ExprId e) { vals_.push_back(e); }
    bool push_number(std::uint32_t tok);
    bool push_string(std::uint32_t tok);
    ExprId evm_leaf(std::uint32_t tok);
    void push_prefix(Op op, std::uint32_t tok);
    void open_frame(Frame frame, std::uint32_t tok, Op op = Op::num, std::uint32_t aux = 0);
    bool open_call(std::uint32_t tok);
    bool open_postfix(Frame frame, std::uint32_t tok);
    bool array_data(std::uint32_t tok);
    std::optional<std::uint32_t> selector_at(std::uint32_t tok);
    bool push_selector(std::uint32_t tok);
    bool callee_sig(std::uint32_t tok);
    bool push_binary(std::uint32_t tok);
    bool push_range(std::uint32_t tok);
    bool postfix(Op op, std::uint32_t aux);
    bool postfix_field(std::uint32_t tok);
    bool postfix_member(std::uint32_t tok);
    bool comma(std::uint32_t tok);
    bool close_paren(std::uint32_t tok);
    bool close_empty(std::uint32_t tok);
    bool close_bracket(std::uint32_t tok);
    bool at_top() const;
    void reduce(unsigned prec, bool right);
    void reduce_one();
    bool frame_top(std::uint32_t tok, const char* closer);

    // --- the signature machine
    bool parse_sig(std::uint32_t name_tok, SigMode mode);
    void type_begin(std::uint32_t tok);
    void type_end(std::uint32_t tok);
    void tuple_close();
    void type_suffix(std::optional<std::uint64_t> dim);
    std::string canonical(const Sig& sig) const;
    std::uint32_t sig_selector(const Sig& sig) const;

    // --- the line machine and its actions
    void parse_line(std::uint32_t line);
    bool sub_expr(const std::uint16_t* p, bool indexed);
    bool sub_sig(const std::uint16_t* p, SigMode mode);
    ExprId part(std::size_t i) const { return parts_[i].e; }
    std::vector<ExprId> parts_from(std::size_t i) const;
    void finish(LineKind kind, StmtId s = none);
    void attribute(LineKind kind);
    // the statements
    void s_simple(St kind, std::uint16_t aux = 0);
    void s_cond(St kind);
    void s_if();
    void s_while();
    void s_continue();
    void s_revert(bool data);
    void s_return(bool data);
    void s_memret(St kind);
    void s_selfdestruct();
    void s_log(bool sig, bool topic);
    void s_call();
    void s_create();
    void s_internal(bool results);
    void s_precompiled();
    void s_assign(St kind);
    void s_const(bool sig);
    void s_def_storage(bool vyper);
    void s_def_safemath();
    void s_def(std::uint32_t name_tok, std::uint32_t comment_tok);
    void s_def_internal(std::uint32_t name_tok, std::uint32_t comment_tok);
    void s_stor_item();
    std::uint32_t storage_type();
    ExprId data_element(std::size_t i, bool revert);

    // --- the blocks
    void build();

    std::string_view text_;
    Lexed lx_;
    const std::uint16_t* k0_ = nullptr;
    Program prog_;
    std::vector<Item> items_;

    // the line being parsed
    std::uint32_t line_ = 0;
    std::uint32_t pos_ = 0;  // where a sub-machine stopped
    std::vector<Part> parts_;
    std::uint32_t nlv_ = 0;
    std::uint32_t tok_a_ = none;
    std::uint32_t tok_b_ = none;
    std::uint16_t call_kind_ = 0;
    Item item_;
    std::string error_;
    std::uint32_t error_tok_ = none;
    Sig sig_;

    // the storage type of a line
    std::vector<SType> swrap_;
    SType sbase_;

    // the context of the names
    Ctx ctx_ = Ctx::top;
    std::uint32_t fn_ = none;
    std::uint32_t sm_ = none;
    std::unordered_map<std::string_view, std::uint32_t> storage_names_;
    std::unordered_map<std::string_view, std::uint32_t> safemath_names_;
    std::unordered_map<std::string_view, std::uint32_t> param_names_;
    std::unordered_map<std::string_view, std::uint32_t> var_names_;
    std::unordered_map<std::string_view, std::uint32_t> sm_param_names_;
    std::unordered_map<std::string_view, std::uint32_t> member_names_;
    std::unordered_map<std::uint64_t, std::uint32_t> internal_entries_;
    std::vector<std::pair<StmtId, std::uint64_t>> internal_refs_;

    // the expression machine's stacks
    std::vector<ExprId> vals_;
    std::vector<OpEntry> ops_;
    std::size_t obase_ = 0;
    bool done_ = false;

    // the signature machine's types under construction
    std::vector<PType> ptypes_;
    std::vector<std::uint32_t> ptype_first_;   // their first tokens
    std::vector<std::uint8_t> ptype_tuple_;    // whether each is a tuple being filled
};

// --- errors, nodes ---------------------------------------------------------------

bool Parser::fail(std::uint32_t tok, std::string_view what)
{
    if (error_.empty())
    {
        error_ = std::string(what);
        error_tok_ = tok;
    }
    return false;
}

ExprId Parser::node(Op op, std::uint32_t aux, std::span<const ExprId> kids)
{
    Expr e;
    e.op = op;
    e.aux = aux;
    e.n = static_cast<std::uint16_t>(kids.size());
    e.kids = static_cast<std::uint32_t>(prog_.kids.size());
    prog_.kids.insert(prog_.kids.end(), kids.begin(), kids.end());
    prog_.exprs.push_back(e);
    return static_cast<ExprId>(prog_.exprs.size() - 1);
}

ExprId Parser::number_leaf(const Word& value)
{
    prog_.nums.push_back(value);
    return leaf(Op::num, static_cast<std::uint32_t>(prog_.nums.size() - 1));
}

StmtId Parser::stmt(St kind)
{
    Stmt s;
    s.kind = kind;
    s.line = lx_.lines[line_].number;
    prog_.stmts.push_back(std::move(s));
    return static_cast<StmtId>(prog_.stmts.size() - 1);
}

// --- the small machines --------------------------------------------------------------

std::optional<Word> Parser::number(std::uint32_t tok)
{
    return parse_number(span(tok));
}

%%{
  machine decimal_mod;
  alphtype unsigned char;

  action digit { n = n * 10 + Word{static_cast<std::uint64_t>(fc - '0')}; }
  main := ( [0-9] @digit )+;
}%%

%% write data noerror noentry;

std::optional<Word> Parser::decimal_mod(std::string_view digits)
{
    // a decimal number of more than 256 bits (python's numbers are of any
    // size): modulo 2**256, as the text's arithmetic is
    Word n = 0;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(digits.data());
    const auto* pe = p + digits.size();
    %% write init;
    %% write exec;
    if (cs < decimal_mod_first_final)
        return std::nullopt;
    return n;
}

%%{
  machine string_literal;
  alphtype unsigned char;

  action ch { out.push_back(fc); }
  action bs { out.push_back('\\'); }
  action quote { out.push_back('\''); }
  action nl { out.push_back('\n'); }
  action cr { out.push_back('\r'); }
  action tab { out.push_back('\t'); }
  action hex_hi { hi = hex_value(fc); }
  action hex_lo { out.push_back(static_cast<std::uint8_t>(hi << 4 | hex_value(fc))); }

  main := "'" ( [^'\\] @ch
              | '\\' ( '\\' @bs | "'" @quote | 'n' @nl | 'r' @cr | 't' @tab
                     | 'x' [0-9a-fA-F] @hex_hi [0-9a-fA-F] @hex_lo ) )* "'";
}%%

%% write data noerror noentry;

std::optional<Bytes> Parser::string_bytes(std::string_view literal)
{
    Bytes out;
    unsigned hi = 0;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(literal.data());
    const auto* pe = p + literal.size();
    %% write init;
    %% write exec;
    if (cs < string_literal_first_final || p != pe)
        return std::nullopt;
    return out;
}

%%{
  machine unknown_name;
  alphtype unsigned char;

  action digit { sel = sel << 4 | hex_value(fc); }
  main := '.'? 'unknown' ( [0-9a-f] @digit ){8} '('?;
}%%

%% write data noerror noentry;

std::optional<std::uint32_t> Parser::unknown_selector(std::string_view name)
{
    std::uint32_t sel = 0;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(name.data());
    const auto* pe = p + name.size();
    %% write init;
    %% write exec;
    if (cs < unknown_name_first_final)
        return std::nullopt;
    return sel;
}

%%{
  machine type_bits;
  alphtype unsigned char;

  action digit { n = n * 10 + (fc - '0'); if (n > 4096) n = 4096; }
  action address { n = 160; }
  action boolean { n = 8; }
  action bytes_n { n *= 8; }
  main := ( 'u'? 'int' ( [0-9] @digit )+
          | 'address' @address
          | 'bool' @boolean
          | 'bytes' ( [0-9] @digit )+ %bytes_n ) '('?;
}%%

%% write data noerror noentry;

std::optional<std::uint32_t> Parser::type_bits(std::string_view type)
{
    std::uint32_t n = 0;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(type.data());
    const auto* pe = p + type.size();
    const auto* eof = pe;
    %% write init;
    %% write exec;
    if (cs < type_bits_first_final || n == 0 || n > 256)
        return std::nullopt;
    return n;
}

%%{
  machine field_bits;
  alphtype unsigned char;

  action digit { if (n < 0xffffffffull) n = n * 10 + (fc - '0'); }
  main := '.field_' ( [0-9] @digit )+;
}%%

%% write data noerror noentry;

std::optional<std::uint32_t> Parser::field_bits(std::string_view member)
{
    std::uint64_t n = 0;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(member.data());
    const auto* pe = p + member.size();
    %% write init;
    %% write exec;
    if (cs < field_bits_first_final || n >= 0xffffffffull)
        return std::nullopt;
    return static_cast<std::uint32_t>(n);
}

%%{
  machine recursive_frame;
  alphtype unsigned char;

  action digit { if (n < 100000) n = n * 10 + (fc - '0'); }
  main := '# recursive, a call takes ' ( [0-9] @digit )+ ' of the 1024 words of the stack' ' '*;
}%%

%% write data noerror noentry;

std::optional<std::uint32_t> Parser::recursive_frame(std::string_view comment)
{
    std::uint32_t n = 0;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(comment.data());
    const auto* pe = p + comment.size();
    %% write init;
    %% write exec;
    if (cs < recursive_frame_first_final)
        return std::nullopt;
    return n;
}

// --- the names ------------------------------------------------------------------------

std::uint32_t Parser::local(std::string_view name)
{
    auto& fn = prog_.functions[fn_];
    const auto [it, added] = var_names_.try_emplace(name, static_cast<std::uint32_t>(fn.vars.size()));
    if (added)
        fn.vars.emplace_back(name);
    return it->second;
}

ExprId Parser::name_leaf(std::uint32_t tok)
{
    const std::string_view name = span(tok);
    if (ctx_ == Ctx::sm_def)
    {
        if (const auto it = sm_param_names_.find(name); it != sm_param_names_.end())
            return leaf(Op::sm_param, it->second);
        fail(tok, "a name in a SafeMath function that isn't one of its params");
        return none;
    }
    if (fn_ != none && ctx_ == Ctx::function)
    {
        if (const auto it = param_names_.find(name); it != param_names_.end())
            return leaf(Op::param, it->second);
    }
    if (const auto it = storage_names_.find(name); it != storage_names_.end())
        return leaf(Op::stor_var, it->second);
    if (fn_ == none || ctx_ != Ctx::function)
    {
        fail(tok, "a name outside a function");
        return none;
    }
    return leaf(Op::var, local(name));
}

// --- the expression machine ---------------------------------------------------------------

bool Parser::push_number(std::uint32_t tok)
{
    if (const auto v = number(tok))
    {
        push_val(number_leaf(*v));
        return true;
    }
    if (kind(tok) == T_NUM)
    {
        const auto v = decimal_mod(span(tok));
        if (!v)
            return fail(tok, "a number this can't read");
        push_val(number_leaf(*v));
        return true;
    }
    // the bytes of a code, of a long string: Bytes(420, 0x6080...)
    const std::string_view digits = span(tok).substr(2);
    auto bytes = digits.size() % 2 != 0 ? parse_hex("0" + std::string(digits)) : parse_hex(digits);
    if (!bytes)
        return fail(tok, "a hex number of no bytes");
    prog_.strs.push_back(std::move(*bytes));
    push_val(leaf(Op::big, static_cast<std::uint32_t>(prog_.strs.size() - 1)));
    return true;
}

bool Parser::push_string(std::uint32_t tok)
{
    auto bytes = string_bytes(span(tok));
    if (!bytes)
        return fail(tok, "a string with an escape this doesn't know");
    prog_.strs.push_back(std::move(*bytes));
    push_val(leaf(Op::str, static_cast<std::uint32_t>(prog_.strs.size() - 1)));
    return true;
}

ExprId Parser::evm_leaf(std::uint32_t tok)
{
    switch (kind(tok))
    {
    case T_CALLER: return leaf(Op::caller);
    case T_ORIGIN: return leaf(Op::origin);
    case T_GASPRICE: return leaf(Op::gas_price);
    case T_CALLVALUE: return leaf(Op::call_value);
    case T_FUNC_HASH: return leaf(Op::func_hash);
    case T_CALLDATASIZE: return leaf(Op::calldata_size);
    case T_RETDATASIZE: return leaf(Op::return_data_size);
    case T_THIS: return leaf(Op::this_address);
    case T_GAS_REMAINING: return leaf(Op::gas);
    case T_CHAINID: return leaf(Op::chain_id);
    case T_MSIZE: return leaf(Op::msize);
    case T_NUMBER: return leaf(Op::number);
    case T_TIMESTAMP: return leaf(Op::timestamp);
    case T_COINBASE: return leaf(Op::coinbase);
    case T_DIFFICULTY: return leaf(Op::difficulty);
    case T_GASLIMIT: return leaf(Op::gas_limit);
    case T_BASEFEE: return leaf(Op::base_fee);
    case T_BLOBBASEFEE: return leaf(Op::blob_base_fee);
    case T_CALL_SUCCESS: return leaf(Op::call_success);
    case T_CREATE_ADDR: return leaf(Op::create_address, lx_.tokens[tok].aux);
    case T_TRUE: return number_leaf(Word{1});
    case T_FALSE: return number_leaf(Word{0});
    default: return none;
    }
}

void Parser::push_prefix(Op op, std::uint32_t tok)
{
    OpEntry e;
    e.kind = OpEntry::k_prefix;
    e.op = op;
    e.prec = op == Op::not_ ? P_NOT : P_UNARY;
    e.tok = tok;
    ops_.push_back(e);
}

void Parser::open_frame(Frame frame, std::uint32_t tok, Op op, std::uint32_t aux)
{
    OpEntry e;
    e.kind = OpEntry::k_frame;
    e.fk = frame;
    e.op = op;
    e.aux = aux;
    e.tok_kind = kind(tok);
    e.base = static_cast<std::uint32_t>(vals_.size());
    e.tok = tok;
    ops_.push_back(e);
}

bool Parser::open_call(std::uint32_t tok)
{
    const auto k = kind(tok);
    switch (k)
    {
    case T_MASK_C: open_frame(F_CALL, tok, Op::mask); return true;
    case T_BYTES_C: open_frame(F_CALL, tok, Op::bytes); return true;
    case T_CONCAT_C: open_frame(F_CALL, tok, Op::concat); return true;
    case T_SHA3_C: open_frame(F_CALL, tok, Op::sha3); return true;
    case T_CEIL32_C: open_frame(F_CALL, tok, Op::ceil32); return true;
    case T_FLOOR32_C: open_frame(F_CALL, tok, Op::floor32); return true;
    case T_MIN_C: open_frame(F_CALL, tok, Op::min); return true;
    case T_MAX_C: open_frame(F_CALL, tok, Op::max); return true;
    case T_BYTE_C: open_frame(F_CALL, tok, Op::byte); return true;
    case T_CLZ_C: open_frame(F_CALL, tok, Op::clz); return true;
    case T_SIGNEXTEND_C: open_frame(F_CALL, tok, Op::signextend); return true;
    case T_SHIFT_C: open_frame(F_CALL, tok, Op::shift); return true;
    case T_ADDMOD_C: open_frame(F_CALL, tok, Op::addmod); return true;
    case T_MULMOD_C: open_frame(F_CALL, tok, Op::mulmod); return true;
    case T_BOOL_C: open_frame(F_CALL, tok, Op::to_bool); return true;
    case T_ADDRESS_C: open_frame(F_CALL, tok, Op::cast_uint, 160); return true;
    case T_UINT_C:
    case T_INT_C:
    {
        const auto bits = type_bits(span(tok));
        if (!bits)
            return fail(tok, "a cast of no width this knows");
        open_frame(F_CALL, tok, k == T_UINT_C ? Op::cast_uint : Op::cast_int, *bits);
        return true;
    }
    case T_BALANCE_C: open_frame(F_CALL, tok, Op::balance); return true;
    case T_EXTSIZE_C: open_frame(F_CALL, tok, Op::ext_code_size); return true;
    case T_EXTHASH_C: open_frame(F_CALL, tok, Op::ext_code_hash); return true;
    case T_EXTCODE_C: open_frame(F_CALL, tok, Op::ext_code); return true;
    case T_BLOCKHASH_C: open_frame(F_CALL, tok, Op::block_hash); return true;
    case T_BLOBHASH_C: open_frame(F_CALL, tok, Op::blob_hash); return true;
    case T_PANIC_C: open_frame(F_CALL, tok, Op::panic); return true;
    case T_SAFEMATH_C:
    {
        // SafeMath.name( - the name between the dot and the parenthesis
        const std::string_view s = span(tok);
        const auto it = safemath_names_.find(s.substr(9, s.size() - 10));
        if (it == safemath_names_.end())
            return fail(tok, "a SafeMath function that def SafeMath: doesn't have");
        open_frame(F_CALL, tok, Op::safemath, it->second);
        return true;
    }
    default:
        return fail(tok, "a call of no function this knows");
    }
}

bool Parser::open_postfix(Frame frame, std::uint32_t tok)
{
    const ExprId target = vals_.back();
    vals_.pop_back();
    open_frame(frame, tok);
    ops_.back().target = target;
    return true;
}

bool Parser::array_data(std::uint32_t tok)
{
    if (ops_.size() <= obase_ || ops_.back().kind != OpEntry::k_frame || ops_.back().fk != F_ARRAY
        || vals_.size() != ops_.back().base + 1)
        return fail(tok, "data= outside Array(len=..., data=...)");
    return true;
}

std::optional<std::uint32_t> Parser::selector_at(std::uint32_t tok)
{
    // a signature in an expression: the line's own signature (a log's) is
    // being read, kept as it is
    Sig saved = std::move(sig_);
    auto types = std::move(ptypes_);
    auto firsts = std::move(ptype_first_);
    auto tuples = std::move(ptype_tuple_);
    std::optional<std::uint32_t> sel;
    if (parse_sig(tok, SigMode::selector))
        sel = sig_selector(sig_);
    sig_ = std::move(saved);
    ptypes_ = std::move(types);
    ptype_first_ = std::move(firsts);
    ptype_tuple_ = std::move(tuples);
    return sel;
}

bool Parser::push_selector(std::uint32_t tok)
{
    const auto sel = selector_at(tok);
    if (!sel)
        return false;
    push_val(leaf(Op::selector, *sel));
    return true;
}

bool Parser::callee_sig(std::uint32_t tok)
{
    const auto sel = selector_at(tok);
    if (!sel)
        return false;
    const ExprId kid[1] = {vals_.back()};
    vals_.back() = node(Op::callee_sig, *sel, kid);
    return true;
}

bool Parser::at_top() const
{
    for (std::size_t i = ops_.size(); i > obase_; --i)
        if (ops_[i - 1].kind == OpEntry::k_frame)
            return false;
    return true;
}

void Parser::reduce_one()
{
    const OpEntry e = ops_.back();
    ops_.pop_back();
    if (e.kind == OpEntry::k_prefix)
    {
        const ExprId kid[1] = {vals_.back()};
        vals_.back() = node(e.op, 0, kid);
        return;
    }
    const ExprId b = vals_.back();
    vals_.pop_back();
    const ExprId kid[2] = {vals_.back(), b};
    vals_.back() = node(e.op, 0, kid);
}

void Parser::reduce(unsigned prec, bool right)
{
    while (ops_.size() > obase_ && ops_.back().kind != OpEntry::k_frame
           && (ops_.back().prec > prec || (ops_.back().prec == prec && !right)))
        reduce_one();
}

bool Parser::push_binary(std::uint32_t tok)
{
    const auto b = binary_of(kind(tok));
    if (!b)
        return fail(tok, "an operator this doesn't know");
    reduce(b->prec, b->op == Op::pow);
    OpEntry e;
    e.kind = OpEntry::k_binary;
    e.op = b->op;
    e.prec = b->prec;
    e.tok = tok;
    ops_.push_back(e);
    return true;
}

bool Parser::push_range(std::uint32_t tok)
{
    // `len` goes in a bracket only: elsewhere it ends the expression
    std::size_t i = ops_.size();
    while (i > obase_ && ops_[i - 1].kind != OpEntry::k_frame)
        --i;
    if (i == obase_)
        return false;
    const auto f = ops_[i - 1].fk;
    if (f != F_BRACKET && f != F_CALLEE_MEM && f != F_EXT_DATA)
        return false;
    reduce(P_RANGE, false);
    OpEntry e;
    e.kind = OpEntry::k_binary;
    e.op = Op::range;
    e.prec = P_RANGE;
    e.tok = tok;
    ops_.push_back(e);
    return true;
}

bool Parser::postfix(Op op, std::uint32_t aux)
{
    const ExprId kid[1] = {vals_.back()};
    vals_.back() = node(op, aux, kid);
    return true;
}

bool Parser::postfix_field(std::uint32_t tok)
{
    const auto bits = field_bits(span(tok));
    if (!bits)
        return fail(tok, "a .field_N of a too big N");
    return postfix(Op::field, *bits);
}

bool Parser::postfix_member(std::uint32_t tok)
{
    const std::string_view name = span(tok).substr(1);
    const auto [it, added] = member_names_.try_emplace(name, static_cast<std::uint32_t>(prog_.names.size()));
    if (added)
        prog_.names.emplace_back(name);
    return postfix(Op::member, it->second);
}

bool Parser::frame_top(std::uint32_t tok, const char* closer)
{
    reduce(0, false);
    // a range left: only a bracket closes it
    while (ops_.size() > obase_ && ops_.back().kind != OpEntry::k_frame)
        reduce_one();
    if (ops_.size() <= obase_)
        return fail(tok, closer);
    return true;
}

bool Parser::comma(std::uint32_t tok)
{
    if (!frame_top(tok, "a comma outside a call"))
        return false;
    const auto f = ops_.back().fk;
    if (f != F_CALL && f != F_ARRAY)
        return fail(tok, "a comma in brackets");
    return true;
}

bool Parser::close_empty(std::uint32_t tok)
{
    if (ops_.size() <= obase_ || ops_.back().kind != OpEntry::k_frame || ops_.back().fk != F_CALL
        || vals_.size() != ops_.back().base)
        return fail(tok, "an empty pair of parentheses");
    return close_paren(tok);
}

bool Parser::close_paren(std::uint32_t tok)
{
    if (!frame_top(tok, "a ) without its ("))
        return false;
    const OpEntry f = ops_.back();
    ops_.pop_back();
    const std::span<const ExprId> args(vals_.data() + f.base, vals_.size() - f.base);
    const std::size_t n = args.size();
    ExprId result = none;
    switch (f.fk)
    {
    case F_PAREN:
        if (n != 1)
            return fail(tok, "parentheses around no single expression");
        result = args[0];
        break;
    case F_ARRAY:
        if (n < 1)
            return fail(tok, "an Array without its length");
        result = node(Op::array, 0, args);
        break;
    case F_CALL:
    {
        std::size_t lo = 1, hi = 1;
        switch (f.op)
        {
        case Op::mask:
        case Op::addmod:
        case Op::mulmod: lo = hi = 3; break;
        case Op::bytes:
        case Op::byte:
        case Op::signextend:
        case Op::shift: lo = hi = 2; break;
        case Op::concat:
        case Op::sha3: lo = 0; hi = 0xffff; break;
        case Op::min:
        case Op::max: lo = 1; hi = 0xffff; break;
        case Op::safemath:
        {
            const auto& d = prog_.safemath[f.aux];
            lo = d.words;
            hi = d.words + d.messages;
            break;
        }
        default: break;
        }
        if (n < lo || n > hi)
            return fail(f.tok, "a call with a wrong number of operands");
        result = node(f.op, f.aux, args);
        break;
    }
    default:
        return fail(tok, "a ) closing a [");
    }
    vals_.resize(f.base);
    vals_.push_back(result);
    return true;
}

bool Parser::close_bracket(std::uint32_t tok)
{
    if (!frame_top(tok, "a ] without its ["))
        return false;
    const OpEntry f = ops_.back();
    ops_.pop_back();
    if (vals_.size() != f.base + 1)
        return fail(tok, "brackets around no single expression");
    const ExprId inside = vals_.back();
    vals_.pop_back();
    const Expr in = prog_.exprs[inside];
    const bool range = in.op == Op::range;
    const ExprId a = range ? prog_.kid(inside, 0) : inside;
    const ExprId n = range ? prog_.kid(inside, 1) : none;
    ExprId result = none;
    switch (f.fk)
    {
    case F_BRACKET:
    {
        const ExprId pair[2] = {a, n};
        const ExprId one[1] = {a};
        Op op = Op::mem;
        switch (f.tok_kind)
        {
        case T_MEM_B: op = range ? Op::mem_range : Op::mem; break;
        case T_CD_B: op = range ? Op::call_data : Op::cd; break;
        case T_STOR_B: op = range ? Op::num : Op::stor_raw; break;
        case T_TRANSIENT_B: op = range ? Op::num : Op::transient; break;
        case T_CALLDATA_B: op = Op::call_data; break;
        case T_RETDATA_B: op = Op::return_data; break;
        case T_CODEDATA_B: op = Op::code_data; break;
        default: return fail(tok, "brackets this doesn't know");
        }
        if (op == Op::num)
            return fail(tok, "a range in stor[...] or transient[...]");
        if (range || op == Op::mem || op == Op::cd || op == Op::stor_raw || op == Op::transient)
            result = node(op, 0, range ? std::span<const ExprId>(pair) : std::span<const ExprId>(one));
        else
        {
            // call.data[a], ext_call.return_data[a], code.data[a]: 32 bytes
            const ExprId with32[2] = {a, number_leaf(Word{32})};
            result = node(op, 0, with32);
        }
        break;
    }
    case F_SUBSCRIPT:
    {
        if (range)
            return fail(tok, "a range as a key");
        const ExprId kid[2] = {f.target, inside};
        result = node(Op::index, 0, kid);
        break;
    }
    case F_CALLEE_MEM:
    {
        if (!range)
            return fail(tok, "addr.mem[...] of no range");
        const ExprId r[2] = {a, n};
        const ExprId kid[2] = {f.target, node(Op::mem_range, 0, r)};
        result = node(Op::callee_mem, 0, kid);
        break;
    }
    case F_EXT_DATA:
    {
        const Expr t = prog_.exprs[f.target];
        if (t.op != Op::ext_code || t.n != 1 || !range)
            return fail(tok, "a .data[...] of no ext_code(...)");
        const ExprId kid[3] = {prog_.kid(f.target, 0), a, n};
        result = node(Op::ext_code_copy, 0, kid);
        break;
    }
    default:
        return fail(tok, "a ] closing a (");
    }
    vals_.push_back(result);
    return true;
}

%%{
  machine expr;
  alphtype unsigned short;
  import "text_lexer.hpp";

  action e_name { const ExprId e = name_leaf(index(fpc)); if (e == none) fbreak; push_val(e); }
  action e_num { if (!push_number(index(fpc))) fbreak; }
  action e_str { if (!push_string(index(fpc))) fbreak; }
  action e_evm { push_val(evm_leaf(index(fpc))); }
  action e_neg { push_prefix(Op::neg, index(fpc)); }
  action e_negneg { push_prefix(Op::neg, index(fpc)); push_prefix(Op::neg, index(fpc)); }
  action e_bitnot { push_prefix(Op::bit_not, index(fpc)); }
  action e_not { push_prefix(Op::not_, index(fpc)); }
  action e_paren { open_frame(F_PAREN, index(fpc)); }
  action e_call { if (!open_call(index(fpc))) fbreak; }
  action e_bracket { open_frame(F_BRACKET, index(fpc)); }
  action e_array { open_frame(F_ARRAY, index(fpc) - 1); }
  action e_data { if (!array_data(index(fpc))) fbreak; }
  action e_sig { if (!push_selector(index(fpc))) fbreak; fexec k0_ + pos_; }
  action e_panic_sig { if (!push_selector(index(fpc) - 1)) fbreak; fexec k0_ + pos_; }
  action e_panic { open_frame(F_CALL, index(fpc) - 1, Op::panic); fhold; }
  action e_empty { if (!close_empty(index(fpc))) fbreak; }

  action o_bin { if (!push_binary(index(fpc))) fbreak; }
  action o_range { if (!push_range(index(fpc))) { if (!at_top()) { fail(index(fpc), "len outside brackets"); fbreak; } done_ = true; fhold; fbreak; } }
  action o_sub { open_postfix(F_SUBSCRIPT, index(fpc)); }
  action o_all { postfix(Op::all, 0); }
  action o_length { postfix(Op::length, 0); }
  action o_field { if (!postfix_field(index(fpc))) fbreak; }
  action o_member { postfix_member(index(fpc)); }
  action o_callee { if (!callee_sig(index(fpc))) fbreak; fexec k0_ + pos_; }
  action o_calleemem { open_postfix(F_CALLEE_MEM, index(fpc)); }
  action o_extdata { open_postfix(F_EXT_DATA, index(fpc)); }
  action o_comma { if (at_top()) { done_ = true; fhold; fbreak; } if (!comma(index(fpc))) fbreak; }
  action o_rparen { if (at_top()) { done_ = true; fhold; fbreak; } if (!close_paren(index(fpc))) fbreak; }
  action o_rbrack { if (at_top()) { done_ = true; fhold; fbreak; } if (!close_bracket(index(fpc))) fbreak; }
  action o_term { if (!at_top()) { fail(index(fpc), "an unclosed bracket"); fbreak; } done_ = true; fhold; fbreak; }

  soft = T_WITH | T_MEMORY | T_FROM | T_TO | T_LEN | T_VALUE | T_WEI | T_GAS | T_ARGS | T_FUNCT
       | T_INDEXED | T_CONTRACT | T_CODE | T_SALT | T_STORAGE | T_IS | T_AT | T_OFFSET | T_OF
       | T_MAPPING | T_FIXED | T_STRUCT | T_SLOT | T_SLOTS | T_PAYABLE;
  names = T_IDENT | soft | T_TYPE | T_BYTES | T_ARRAY | T_SAFEMATH;
  evm = T_CALLER | T_ORIGIN | T_GASPRICE | T_CALLVALUE | T_FUNC_HASH | T_CALLDATASIZE
      | T_RETDATASIZE | T_THIS | T_GAS_REMAINING | T_CHAINID | T_MSIZE | T_NUMBER | T_TIMESTAMP
      | T_COINBASE | T_DIFFICULTY | T_GASLIMIT | T_BASEFEE | T_BLOBBASEFEE | T_CALL_SUCCESS
      | T_CREATE_ADDR | T_TRUE | T_FALSE;
  calls = T_MASK_C | T_BYTES_C | T_CONCAT_C | T_SHA3_C | T_CEIL32_C | T_FLOOR32_C | T_MIN_C
        | T_MAX_C | T_BYTE_C | T_CLZ_C | T_SIGNEXTEND_C | T_SHIFT_C | T_ADDMOD_C | T_MULMOD_C
        | T_BOOL_C | T_UINT_C | T_ADDRESS_C | T_INT_C | T_BALANCE_C | T_EXTSIZE_C | T_EXTHASH_C
        | T_EXTCODE_C | T_BLOCKHASH_C | T_BLOBHASH_C | T_SAFEMATH_C;
  brackets = T_MEM_B | T_CD_B | T_STOR_B | T_TRANSIENT_B | T_CALLDATA_B | T_RETDATA_B
           | T_CODEDATA_B;
  binops = T_PLUS | T_MINUS | T_STAR | T_SLASH | T_PERCENT | T_POW | T_SHL | T_SHR | T_SAR
         | T_AMP | T_PIPE | T_CARET | T_EQ | T_NE | T_LT | T_GT | T_LE | T_GE | T_SLT | T_SGT
         | T_SLE | T_SGE | T_SADD | T_SMUL | T_SDIV | T_SMOD | T_AND | T_OR;
  after_toks = binops | T_LEN | T_LBRACK | T_ALL | T_DOT_LENGTH | T_DOT_FIELD | T_DOT_MEMBER
             | T_DOT_CALL | T_DOT_MEM_B | T_DOT_DATA_B | T_COMMA | T_RPAREN | T_RBRACK;

  main := (
    start: (
        names @e_name -> after
      | ( T_NUM | T_HEX ) @e_num -> after
      | T_STR @e_str -> after
      | evm @e_evm -> after
      | T_MINUS @e_neg -> start
      | T_MINUSMINUS @e_negneg -> start
      | T_TILDE @e_bitnot -> start
      | T_NOT @e_not -> start
      | T_LPAREN @e_paren -> start
      | calls @e_call -> start
      | brackets @e_bracket -> start
      | T_ARRAY_C T_LEN_EQ @e_array -> start
      | T_DATA_EQ @e_data -> start
      | T_IDENT_CALL @e_sig -> after
      | T_PANIC_C ( T_TYPE | T_BYTES | T_LPAREN | T_RPAREN ) @e_panic_sig -> after
      | T_PANIC_C ( any - ( T_TYPE | T_BYTES | T_LPAREN | T_RPAREN ) ) @e_panic -> start
      | T_RPAREN @e_empty -> after
    ),
    after: (
        binops @o_bin -> start
      | T_LEN @o_range -> start
      | T_LBRACK @o_sub -> start
      | T_ALL @o_all -> after
      | T_DOT_LENGTH @o_length -> after
      | T_DOT_FIELD @o_field -> after
      | T_DOT_MEMBER @o_member -> after
      | T_DOT_CALL @o_callee -> after
      | T_DOT_MEM_B @o_calleemem -> start
      | T_DOT_DATA_B @o_extdata -> start
      | T_COMMA @o_comma -> start
      | T_RPAREN @o_rparen -> after
      | T_RBRACK @o_rbrack -> after
      | ( any - after_toks ) @o_term -> final
    )
  );
}%%

%% write data noerror nofinal noentry;

ExprId Parser::parse_expr(std::uint32_t pos)
{
    const std::size_t vbase = vals_.size();
    const std::size_t saved_obase = obase_;
    obase_ = ops_.size();
    done_ = false;
    int cs;
    const std::uint16_t* p = k0_ + pos;
    const std::uint16_t* pe = k0_ + lx_.lines[line_].last;
    %% write init;
    %% write exec;
    ExprId result = none;
    if (done_ && error_.empty())
    {
        pos_ = index(p);
        while (ops_.size() > obase_)
            reduce_one();
        if (vals_.size() == vbase + 1)
            result = vals_.back();
        else
            fail(index(p), "an expression this can't make");
    }
    else if (error_.empty())
        fail(p < pe ? index(p) : lx_.lines[line_].last - 1,
            p < pe ? "a token that can't go there in an expression" : "an unfinished expression");
    vals_.resize(vbase);
    ops_.resize(obase_);
    obase_ = saved_obase;
    return result;
}

// --- the signature machine ---------------------------------------------------------------

void Parser::type_begin(std::uint32_t tok)
{
    ptypes_.emplace_back();
    ptype_first_.push_back(tok);
    ptype_tuple_.push_back(0);
}

void Parser::tuple_close()
{
    // the tuple's components are in: static when they all are
    auto& t = ptypes_.back();
    ptype_tuple_.back() = 0;
    std::uint32_t words = 0;
    bool dynamic = false;
    for (const auto& c : t.components)
    {
        dynamic = dynamic || c.dynamic;
        words += c.words;
    }
    t.dynamic = dynamic;
    t.words = dynamic ? 1 : words;
}

void Parser::type_suffix(std::optional<std::uint64_t> dim)
{
    auto& t = ptypes_.back();
    PType elem = t;
    elem.canonical.clear();
    t.components.clear();
    t.is_array = true;
    t.elem_words = elem.words;
    t.elem_dynamic = elem.dynamic;
    t.components.push_back(std::move(elem));
    if (!dim)
    {
        t.dynamic = true;
        t.has_length = true;
        t.words = 1;
        t.count = 0;
    }
    else
    {
        t.count = static_cast<std::uint32_t>(*dim);
        t.has_length = false;
        if (t.elem_dynamic)
        {
            t.dynamic = true;
            t.words = 1;
        }
        else
        {
            t.dynamic = false;
            t.words = static_cast<std::uint32_t>(std::min<std::uint64_t>(*dim * t.elem_words, 0xffffffu));
        }
    }
}

void Parser::type_end(std::uint32_t tok)
{
    // its canonical text: its tokens, written without spaces
    auto& t = ptypes_.back();
    const auto first = ptype_first_.back();
    t.canonical = std::string(text_.substr(lx_.tokens[first].begin, lx_.tokens[tok - 1].end - lx_.tokens[first].begin));
    if (ptypes_.size() >= 2 && ptype_tuple_[ptypes_.size() - 2])
    {
        // a component of the tuple under it
        PType done = std::move(ptypes_.back());
        ptypes_.pop_back();
        ptype_first_.pop_back();
        ptype_tuple_.pop_back();
        ptypes_.back().components.push_back(std::move(done));
    }
}

%%{
  machine sig;
  alphtype unsigned short;
  import "text_lexer.hpp";

  prepush {
      if (top >= static_cast<int>(stack_vec.size()))
          stack_vec.resize(stack_vec.size() * 2);
      stack = stack_vec.data();
  }

  action ty_word { type_begin(index(fpc)); }
  action ty_dynamic { type_begin(index(fpc)); auto& t = ptypes_.back(); t.dynamic = true; t.has_length = true; }
  action ty_array {
      type_begin(index(fpc));
      auto& t = ptypes_.back();
      t.dynamic = true; t.has_length = true; t.is_array = true;
  }
  action ty_tuple { type_begin(index(fpc)); ptype_tuple_.back() = 1; fcall tuple_items; }
  action ty_dim_none { dim.reset(); }
  action ty_dim { const auto v = number(index(fpc)); if (!v || *v > 0xffffffu) { fail(index(fpc), "an array of too many elements"); fbreak; } dim = static_cast<std::uint64_t>(*v); }
  action ty_suffix { type_suffix(dim); }
  action ty_end { type_end(index(fpc)); }
  action tuple_done { tuple_close(); fret; }

  action pn_typed {
      sig_.params.emplace_back();
      sig_.params.back().typed = true;
      sig_.params.back().type = std::move(ptypes_.back());
      ptypes_.pop_back(); ptype_first_.pop_back(); ptype_tuple_.pop_back();
  }
  action pn_indexed { sig_.params.back().indexed = true; }
  action pn_name { sig_.params.back().name = index(fpc); }
  action pn_value {
      if (mode != SigMode::log) { fail(index(fpc), "a param with a value outside a log"); fbreak; }
      const ExprId e = parse_expr(index(fpc));
      if (e == none) fbreak;
      sig_.params.back().value = e;
      fexec k0_ + pos_;
  }
  action pn_only { sig_.params.emplace_back(); sig_.params.back().name = index(fpc); }
  action sg_qmark { sig_.unknown = true; }
  action sg_done { done = true; }

  soft = T_WITH | T_MEMORY | T_FROM | T_TO | T_LEN | T_VALUE | T_WEI | T_GAS | T_ARGS | T_FUNCT
       | T_CONTRACT | T_CODE | T_SALT | T_STORAGE | T_IS | T_AT | T_OFFSET | T_OF
       | T_MAPPING | T_FIXED | T_STRUCT | T_SLOT | T_SLOTS | T_PAYABLE;
  hard = T_DEF | T_CONST | T_IF | T_ELSE | T_WHILE | T_CONTINUE | T_BREAK | T_REQUIRE | T_ASSERT
       | T_REVERT | T_RETURN | T_STOP | T_INVALID | T_LOG | T_CALL | T_DELEGATE | T_CODECALL
       | T_CREATE | T_CREATE2 | T_NOT | T_AND | T_OR | T_TRUE | T_FALSE | T_SAFEMATH | T_CALLER
       | T_CHAINID | T_MSIZE | T_GAS_REMAINING;
  bname = T_IDENT | soft | hard;
  pname = bname | T_TYPE | T_BYTES | T_ARRAY;
  value_first = any - ( T_COMMA | T_RPAREN | T_EOL );

  suffix = T_LBRACK @ty_dim_none ( T_NUM @ty_dim )? T_RBRACK @ty_suffix;
  type = ( T_TYPE @ty_word | T_BYTES @ty_dynamic | T_ARRAY @ty_array | T_LPAREN @ty_tuple ) suffix*;
  ctype = type %ty_end;

  tuple_items := ( ctype ( T_COMMA ctype )* )? T_RPAREN @tuple_done;

  typed = ctype %pn_typed ( T_INDEXED @pn_indexed )?
          ( pname @pn_name | ( T_IDENT_EQ | T_LEN_EQ | T_DATA_EQ ) @pn_name value_first @pn_value )?;
  bare = bname @pn_only;

  main := ( T_QMARK @sg_qmark | typed ( T_COMMA typed )* | bare ( T_COMMA bare )* )? T_RPAREN @sg_done;
}%%

%% write data noerror nofinal noentry;

bool Parser::parse_sig(std::uint32_t name_tok, SigMode mode)
{
    // the name: the token's text without its parenthesis (and the dot of
    // a callee: .transfer()
    std::string_view name = span(name_tok);
    name.remove_suffix(1);
    if (kind(name_tok) == T_DOT_CALL)
        name.remove_prefix(1);
    sig_ = Sig{};
    sig_.name = name;
    ptypes_.clear();
    ptype_first_.clear();
    ptype_tuple_.clear();
    std::optional<std::uint64_t> dim;
    bool done = false;
    std::vector<int> stack_vec(16);
    int* stack = stack_vec.data();
    int top = 0;
    int cs;
    const std::uint16_t* p = k0_ + name_tok + 1;
    const std::uint16_t* pe = k0_ + lx_.lines[line_].last;
    %% write init;
    %% write exec;
    if (!done)
    {
        if (error_.empty())
            fail(p < pe ? index(p) : name_tok, "a signature this can't read");
        return false;
    }
    pos_ = index(p);
    return true;
}

std::string Parser::canonical(const Sig& sig) const
{
    std::string s(sig.name);
    s += '(';
    for (std::size_t i = 0; i < sig.params.size(); ++i)
    {
        if (i)
            s += ',';
        s += sig.params[i].type.canonical;
    }
    s += ')';
    return s;
}

std::uint32_t Parser::sig_selector(const Sig& sig) const
{
    if (const auto sel = unknown_selector(sig.name))
        return *sel;
    return selector_of(canonical(sig));
}

// --- the line machine -------------------------------------------------------------------------

bool Parser::sub_expr(const std::uint16_t* p, bool indexed)
{
    const auto first = index(p);
    const ExprId e = parse_expr(first);
    if (e == none)
        return false;
    parts_.push_back({e, first, pos_, indexed});
    return true;
}

bool Parser::sub_sig(const std::uint16_t* p, SigMode mode)
{
    tok_a_ = index(p);
    return parse_sig(tok_a_, mode);
}

std::vector<ExprId> Parser::parts_from(std::size_t i) const
{
    std::vector<ExprId> out;
    for (; i < parts_.size(); ++i)
        out.push_back(parts_[i].e);
    return out;
}

void Parser::finish(LineKind kind, StmtId s)
{
    item_.kind = kind;
    item_.stmt = s;
}

void Parser::attribute(LineKind kind)
{
    item_.kind = kind;
    item_.exprs = parts_from(0);
}

void Parser::s_simple(St kind, std::uint16_t aux)
{
    const StmtId s = stmt(kind);
    prog_.stmts[s].aux = aux;
    finish(LK_SIMPLE, s);
}

void Parser::s_cond(St kind)
{
    const StmtId s = stmt(kind);
    prog_.stmts[s].a = part(0);
    finish(LK_SIMPLE, s);
}

void Parser::s_if()
{
    const StmtId s = stmt(St::if_);
    prog_.stmts[s].a = part(0);
    finish(LK_IF, s);
}

void Parser::s_while()
{
    const StmtId s = stmt(St::while_);
    auto& st = prog_.stmts[s];
    st.a = part(0);
    if (tok_a_ != none)
    {
        // loop2: the label's number (loopN)
        const auto n = parse_number(span(tok_a_).substr(4));
        st.aux = static_cast<std::uint16_t>(n && *n < 0xffff ? static_cast<unsigned>(*n) : 0xffff);
    }
    finish(LK_WHILE, s);
}

void Parser::s_continue()
{
    const StmtId s = stmt(St::continue_);
    if (tok_a_ != none)
    {
        const auto n = parse_number(span(tok_a_).substr(4));
        prog_.stmts[s].aux = static_cast<std::uint16_t>(n && *n < 0xffff ? static_cast<unsigned>(*n) : 0xffff);
    }
    finish(LK_SIMPLE, s);
}

ExprId Parser::data_element(std::size_t i, bool revert)
{
    // the first element of a revert's data, 8 hex digits: a selector (a
    // word that small would be printed in decimal)
    const Part& pt = parts_[i];
    if (revert && i == 0 && pt.last == pt.first + 1 && kind(pt.first) == T_HEX && span(pt.first).size() == 10)
    {
        const auto v = number(pt.first);
        return leaf(Op::selector, static_cast<std::uint32_t>(*v));
    }
    return pt.e;
}

void Parser::s_revert(bool data)
{
    const StmtId s = stmt(St::revert);
    auto& st = prog_.stmts[s];
    if (data)
    {
        for (std::size_t i = 0; i < parts_.size(); ++i)
            st.list.push_back(data_element(i, true));
        // revert with 'text': Error(string)'s
        if (st.list.size() == 1 && prog_.exprs[st.list[0]].op == Op::str)
            st.aux = 1;
    }
    finish(LK_SIMPLE, s);
}

void Parser::s_return(bool data)
{
    // in a recursive internal function, or a SafeMath function: its results
    const bool leave = ctx_ == Ctx::sm_def || (fn_ != none && prog_.functions[fn_].kind == Function::internal);
    const StmtId s = stmt(leave ? St::leave : (data ? St::return_ : St::stop));
    if (data)
        prog_.stmts[s].list = parts_from(0);
    finish(LK_SIMPLE, s);
}

void Parser::s_memret(St kind)
{
    finish(LK_MEMRET, stmt(kind));
}

void Parser::s_selfdestruct()
{
    const StmtId s = stmt(St::selfdestruct);
    prog_.stmts[s].a = part(0);
    finish(LK_SIMPLE, s);
}

void Parser::s_log(bool sig, bool topic)
{
    const StmtId s = stmt(St::log);
    auto& st = prog_.stmts[s];
    std::size_t from = 0;
    if (sig)
    {
        // the event's signature: topic 0
        prog_.nums.push_back(keccak256(BytesView(
            reinterpret_cast<const std::uint8_t*>(canonical(sig_).data()), canonical(sig_).size())));
        st.list2.push_back(leaf(Op::num, static_cast<std::uint32_t>(prog_.nums.size() - 1)));
        bool valued = false;
        for (const auto& p : sig_.params)
            valued = valued || p.value != none;
        if (valued)
        {
            // log Transfer(address indexed from=x, ...): the indexed ones are
            // the topics, the others the data, in order
            for (const auto& p : sig_.params)
            {
                if (p.value == none)
                {
                    fail(tok_a_, "a param of a log without its value");
                    return;
                }
                (p.indexed ? st.list2 : st.list).push_back(p.value);
            }
        }
    }
    else if (topic)
    {
        // log 0xddf2...: the topic 0 is the first part
        st.list2.push_back(part(0));
        from = 1;
    }
    for (std::size_t i = from; i < parts_.size(); ++i)
        (parts_[i].indexed ? st.list2 : st.list).push_back(parts_[i].e);
    if (st.list2.size() > 4)
    {
        fail(tok_a_, "a log of more than 4 topics");
        return;
    }
    finish(LK_SIMPLE, s);
}

void Parser::s_call()
{
    const StmtId s = stmt(St::call);
    auto& st = prog_.stmts[s];
    st.aux = call_kind_;
    st.a = part(0);
    finish(LK_CALL, s);
}

void Parser::s_create()
{
    const StmtId s = stmt(St::create);
    auto& st = prog_.stmts[s];
    st.aux = call_kind_;
    st.a = part(0);
    finish(LK_CREATE, s);
}

void Parser::s_internal(bool results)
{
    const StmtId s = stmt(St::internal_call);
    auto& st = prog_.stmts[s];
    const std::size_t nres = results ? nlv_ : 0;
    for (std::size_t i = 0; i < nres; ++i)
    {
        const Expr& e = prog_.exprs[part(i)];
        if (e.op != Op::var)
        {
            fail(parts_[i].first, "a result of an internal function that isn't a variable");
            return;
        }
        st.vars.push_back(e.aux);
    }
    st.list = parts_from(nres);
    // internal_0x1a2( - its entry, resolved when all the functions are known
    const std::string_view name = span(tok_b_);
    const auto entry = parse_number(name.substr(9, name.size() - 10));
    internal_refs_.emplace_back(s, entry ? static_cast<std::uint64_t>(*entry) : ~0ull);
    finish(LK_SIMPLE, s);
}

void Parser::s_precompiled()
{
    if (nlv_ != 1 || prog_.exprs[part(0)].op != Op::var)
    {
        fail(parts_.empty() ? tok_b_ : parts_[0].first, "a precompiled contract's result that isn't a variable");
        return;
    }
    const StmtId s = stmt(St::precompiled);
    auto& st = prog_.stmts[s];
    st.vars.push_back(prog_.exprs[part(0)].aux);
    st.aux = lx_.tokens[tok_b_].aux;
    st.list = parts_from(1);
    finish(LK_SIMPLE, s);
}

void Parser::s_assign(St kind)
{
    const ExprId lhs = part(0);
    const Op op = prog_.exprs[lhs].op;
    if (kind == St::assign && nlv_ != 1)
    {
        fail(parts_[1].first, "several values set at once, not by an internal function");
        return;
    }
    const StmtId s = stmt(kind);
    auto& st = prog_.stmts[s];
    st.a = lhs;
    if (kind == St::assign)
    {
        if (op == Op::mem_range || op == Op::mem)
            st.list = parts_from(1);
        else if (parts_.size() == 2)
            st.b = part(1);
        else
        {
            fail(parts_[2].first, "a list of data set to something else than memory");
            return;
        }
    }
    else if (kind == St::add_assign || kind == St::sub_assign)
        st.b = part(1);
    finish(LK_SIMPLE, s);
}

void Parser::s_const(bool sig)
{
    Function f;
    f.kind = Function::constant;
    f.payable = false;
    f.line = lx_.lines[line_].number;
    if (sig)
    {
        f.name = canonical(sig_);
        f.selector = sig_selector(sig_);
    }
    else
    {
        // const name = ...: the function name()
        const std::string_view name = span(tok_a_);
        f.name = std::string(name) + "()";
        f.selector = unknown_selector(name).value_or(selector_of(f.name));
    }
    f.data = parts_from(0);
    prog_.functions.push_back(std::move(f));
    finish(LK_CONST);
    item_.def = static_cast<std::uint32_t>(prog_.functions.size() - 1);
}

void Parser::s_def_storage(bool vyper)
{
    prog_.vyper = vyper;
    ctx_ = Ctx::storage;
    finish(LK_DEF_STORAGE);
}

void Parser::s_def_safemath()
{
    ctx_ = Ctx::safemath;
    finish(LK_DEF_SAFEMATH);
}

void Parser::s_def(std::uint32_t name_tok, std::uint32_t comment_tok)
{
    const std::uint16_t comment = comment_tok == none ? std::uint16_t{T_NONE} : kind(comment_tok);
    if (lx_.lines[line_].indent > 0)
    {
        // def add(a, b): of def SafeMath: - its params a, b, errorMessage...
        if (ctx_ != Ctx::safemath && ctx_ != Ctx::sm_def)
        {
            fail(name_tok, "a def in a block");
            return;
        }
        SafeMathDef d;
        d.name = std::string(sig_.name);
        d.solidity08 = comment == T_C_SOLIDITY08;
        d.line = lx_.lines[line_].number;
        sm_param_names_.clear();
        std::uint32_t words = 0, messages = 0;
        for (std::size_t i = 0; i < sig_.params.size(); ++i)
        {
            const auto& p = sig_.params[i];
            if (p.typed || p.name == none)
            {
                fail(name_tok, "a SafeMath function with a typed param");
                return;
            }
            sm_param_names_.emplace(span(p.name), static_cast<std::uint32_t>(i));
            // a, b - then the messages (errorMessage, errorMessage2...)
            (i < 2 && span(p.name).size() == 1 ? words : messages) += 1;
        }
        d.words = words;
        d.messages = messages;
        prog_.safemath.push_back(std::move(d));
        sm_ = static_cast<std::uint32_t>(prog_.safemath.size() - 1);
        safemath_names_.emplace(sig_.name, sm_);
        ctx_ = Ctx::sm_def;
        finish(LK_SM_DEF);
        item_.def = sm_;
        return;
    }

    Function f;
    f.line = lx_.lines[line_].number;
    f.name = std::string(span(name_tok).substr(0, span(name_tok).size() - 1));
    f.kind = kind(name_tok) == T_FALLBACK_C ? Function::fallback : Function::regular;
    switch (comment)
    {
    case T_C_NOT_PAYABLE: f.payable = false; break;
    case T_C_NOT_PAYABLE_INVALID: f.payable = false; f.value_invalid = true; break;
    case T_C_NOT_PAYABLE_DEFAULT: f.payable = false; break;
    default: f.payable = true; break;
    }
    if (f.kind == Function::regular)
    {
        f.selector = sig_selector(sig_);
        f.name = canonical(sig_);
        if (sig_.unknown)
            f.name = std::string(sig_.name) + "(?)";
    }
    // the params: where their words are in the calldata
    param_names_.clear();
    var_names_.clear();
    std::uint32_t at = 4;
    for (auto& sp : sig_.params)
    {
        if (!sp.typed || sp.name == none)
        {
            fail(name_tok, "a param without its type or its name");
            return;
        }
        Param p;
        p.name = std::string(span(sp.name));
        p.type = std::move(sp.type);
        p.position = at;
        at += p.type.words * 32;
        param_names_.emplace(span(sp.name), static_cast<std::uint32_t>(f.params.size()));
        f.params.push_back(std::move(p));
    }
    prog_.functions.push_back(std::move(f));
    fn_ = static_cast<std::uint32_t>(prog_.functions.size() - 1);
    ctx_ = Ctx::function;
    finish(LK_DEF_FUNC);
    item_.def = fn_;
}

void Parser::s_def_internal(std::uint32_t name_tok, std::uint32_t comment_tok)
{
    Function f;
    f.kind = Function::internal;
    f.line = lx_.lines[line_].number;
    const std::string_view name = span(name_tok);
    f.name = std::string(name.substr(0, name.size() - 1));
    const auto entry = parse_number(name.substr(9, name.size() - 10));
    if (!entry || *entry > Word{0xffffffffffffull})
    {
        fail(name_tok, "an internal function of no entry");
        return;
    }
    f.entry = static_cast<std::uint64_t>(*entry);
    f.frame = recursive_frame(span(comment_tok)).value_or(0);
    param_names_.clear();
    var_names_.clear();
    for (const auto& sp : sig_.params)
    {
        if (sp.typed || sp.name == none)
        {
            fail(name_tok, "a typed param of an internal function");
            return;
        }
        Param p;
        p.name = std::string(span(sp.name));
        param_names_.emplace(span(sp.name), static_cast<std::uint32_t>(f.params.size()));
        f.params.push_back(std::move(p));
    }
    prog_.functions.push_back(std::move(f));
    fn_ = static_cast<std::uint32_t>(prog_.functions.size() - 1);
    internal_entries_.emplace(prog_.functions[fn_].entry, fn_);
    ctx_ = Ctx::function;
    finish(LK_DEF_INTERNAL);
    item_.def = fn_;
}

std::uint32_t Parser::storage_type()
{
    // the base, then the wrappers from the innermost
    prog_.types.push_back(sbase_);
    auto t = static_cast<std::uint32_t>(prog_.types.size() - 1);
    for (std::size_t i = swrap_.size(); i > 0; --i)
    {
        SType w = swrap_[i - 1];
        w.elem = t;
        prog_.types.push_back(w);
        t = static_cast<std::uint32_t>(prog_.types.size() - 1);
    }
    return t;
}

void Parser::s_stor_item()
{
    if (ctx_ != Ctx::storage)
    {
        fail(tok_a_, "a storage definition outside def storage:");
        return;
    }
    StorageDef d;
    d.name = std::string(span(tok_a_));
    const auto slot = number(tok_b_);
    if (!slot)
    {
        fail(tok_b_, "a slot of more than 256 bits");
        return;
    }
    d.slot = *slot;
    if (parts_.size() == 1)
    {
        // the offset: parts_[0] holds its token (no expression)
        const auto off = number(parts_[0].first);
        if (!off || *off >= 256)
        {
            fail(parts_[0].first, "an offset of 256 bits or more");
            return;
        }
        d.offset = static_cast<std::uint32_t>(*off);
    }
    d.type = storage_type();
    d.line = lx_.lines[line_].number;
    storage_names_.emplace(span(tok_a_), static_cast<std::uint32_t>(prog_.storage.size()));
    prog_.storage.push_back(std::move(d));
    finish(LK_STOR_ITEM);
}

%%{
  machine line;
  alphtype unsigned short;
  import "text_lexer.hpp";

  action x { if (!sub_expr(fpc, false)) fbreak; fexec k0_ + pos_; }
  action x_indexed { if (!sub_expr(fpc, true)) fbreak; fexec k0_ + pos_; }
  action lv_count { nlv_ = static_cast<std::uint32_t>(parts_.size()); }
  action sig_def { if (!sub_sig(fpc, SigMode::def)) fbreak; fexec k0_ + pos_; }
  action sig_log { if (!sub_sig(fpc, SigMode::log)) fbreak; fexec k0_ + pos_; }
  action sig_sel { if (!sub_sig(fpc, SigMode::selector)) fbreak; fexec k0_ + pos_; }
  action rem_a { tok_a_ = index(fpc); }
  action rem_b { tok_b_ = index(fpc); }
  action rem_comment { comment_tok = index(fpc); }
  action go_assign { fexec k0_ + lx_.lines[line_].first; fgoto assign; }

  action k_call { call_kind_ = static_cast<std::uint16_t>(CallKind::call); }
  action k_static { call_kind_ = static_cast<std::uint16_t>(CallKind::staticcall); }
  action k_delegate { call_kind_ = static_cast<std::uint16_t>(CallKind::delegatecall); }
  action k_codecall { call_kind_ = static_cast<std::uint16_t>(CallKind::callcode); }
  action k_create { call_kind_ = static_cast<std::uint16_t>(CreateKind::create); }
  action k_create2 { call_kind_ = static_cast<std::uint16_t>(CreateKind::create2); }

  # the storage types
  action w_mapping { swrap_.push_back({SType::mapping}); }
  action w_array { swrap_.push_back({SType::array}); }
  action w_fixed { swrap_.push_back({SType::fixed}); }
  action w_len { const auto v = number(index(fpc)); if (!v || *v > Word{~0ull}) { fail(index(fpc), "a length too big"); fbreak; } swrap_.back().length = static_cast<std::uint64_t>(*v); }
  action b_value { const auto bits = type_bits(span(index(fpc))); if (!bits) { fail(index(fpc), "a type of no width this knows"); fbreak; } sbase_ = SType{}; sbase_.width = *bits; }
  action b_fixed_len {
      const auto v = number(index(fpc));
      if (!v || *v > Word{~0ull}) { fail(index(fpc), "a length too big"); fbreak; }
      SType f{SType::fixed};
      f.length = static_cast<std::uint64_t>(*v);
      swrap_.push_back(f);
  }
  action b_bytes { sbase_ = SType{SType::bytes}; }
  action b_struct { sbase_ = SType{SType::struct_}; sbase_.width = 0; }
  action b_slots { const auto v = number(index(fpc)); if (!v || *v > Word{0xffffffu}) { fail(index(fpc), "a struct of too many slots"); fbreak; } sbase_.width = static_cast<std::uint32_t>(*v); }
  action si_offset { parts_.push_back({none, index(fpc), index(fpc) + 1, false}); }

  # the statements
  action s_comment { finish(LK_NONE); comment_line = true; }
  action s_if { s_if(); }
  action s_else { finish(LK_ELSE); }
  action s_while { s_while(); }
  action s_continue { s_continue(); }
  action s_break { s_simple(St::break_); }
  action s_require { s_cond(St::require); }
  action s_assert { s_cond(St::assert_); }
  action s_revert { s_revert(false); }
  action s_revert_data { s_revert(true); }
  action s_revert_mem { s_memret(St::revert_memory); }
  action s_return { s_return(false); }
  action s_return_data { s_return(true); }
  action s_return_mem { s_memret(St::return_memory); }
  action s_stop { s_simple(St::stop); }
  action s_invalid { s_simple(St::invalid); }
  action s_selfdestruct { s_selfdestruct(); }
  action s_log_none { s_log(false, false); }
  action s_log_sig { s_log(true, false); }
  action s_log_topic { s_log(false, true); }
  action s_log_data { s_log(false, false); }
  action s_call { s_call(); }
  action s_create { s_create(); }
  action s_internal { s_internal(false); }
  action s_internal_results { s_internal(true); }
  action s_precompiled { s_precompiled(); }
  action s_assign { s_assign(St::assign); }
  action s_add { s_assign(St::add_assign); }
  action s_sub { s_assign(St::sub_assign); }
  action s_inc { s_assign(St::inc); }
  action s_dec { s_assign(St::dec); }
  action s_aborted { s_simple(St::aborted); }
  action s_const { s_const(false); }
  action s_const_sig { s_const(true); }
  action s_def_storage { s_def_storage(false); }
  action s_def_vyper { s_def_storage(true); }
  action s_def_safemath { s_def_safemath(); }
  action s_def { s_def(tok_a_, comment_tok); }
  action s_def_internal { s_def_internal(tok_a_, comment_tok); }
  action s_stor_item { s_stor_item(); }
  action a_funct { attribute(LK_FUNCT); }
  action a_value { attribute(LK_VALUE); }
  action a_gas { attribute(LK_GAS); }
  action a_args { attribute(LK_ARGS); }
  action a_from { attribute(LK_FROM); }
  action a_len { attribute(LK_LEN); }
  action a_to { attribute(LK_TO); }
  action a_code { attribute(LK_CODE); }
  action a_salt { attribute(LK_SALT); }

  soft = T_WITH | T_MEMORY | T_FROM | T_TO | T_LEN | T_VALUE | T_WEI | T_GAS | T_ARGS | T_FUNCT
       | T_INDEXED | T_CONTRACT | T_CODE | T_SALT | T_STORAGE | T_IS | T_AT | T_OFFSET | T_OF
       | T_MAPPING | T_FIXED | T_STRUCT | T_SLOT | T_SLOTS | T_PAYABLE;
  names = T_IDENT | soft | T_TYPE | T_BYTES | T_ARRAY | T_SAFEMATH;
  evm = T_CALLER | T_ORIGIN | T_GASPRICE | T_CALLVALUE | T_FUNC_HASH | T_CALLDATASIZE
      | T_RETDATASIZE | T_THIS | T_GAS_REMAINING | T_CHAINID | T_MSIZE | T_NUMBER | T_TIMESTAMP
      | T_COINBASE | T_DIFFICULTY | T_GASLIMIT | T_BASEFEE | T_BLOBBASEFEE | T_CALL_SUCCESS
      | T_CREATE_ADDR | T_TRUE | T_FALSE;
  calls = T_MASK_C | T_BYTES_C | T_CONCAT_C | T_SHA3_C | T_CEIL32_C | T_FLOOR32_C | T_MIN_C
        | T_MAX_C | T_BYTE_C | T_CLZ_C | T_SIGNEXTEND_C | T_SHIFT_C | T_ADDMOD_C | T_MULMOD_C
        | T_BOOL_C | T_UINT_C | T_ADDRESS_C | T_INT_C | T_BALANCE_C | T_EXTSIZE_C | T_EXTHASH_C
        | T_EXTCODE_C | T_BLOCKHASH_C | T_BLOBHASH_C | T_SAFEMATH_C;
  brackets = T_MEM_B | T_CD_B | T_STOR_B | T_TRANSIENT_B | T_CALLDATA_B | T_RETDATA_B
           | T_CODEDATA_B;
  expr_first = names | evm | T_NUM | T_HEX | T_STR | calls | brackets | T_ARRAY_C | T_PANIC_C
             | T_IDENT_CALL | T_LPAREN | T_MINUS | T_MINUSMINUS | T_TILDE | T_NOT;
  def_name = T_IDENT_CALL | calls | T_ARRAY_C | T_PANIC_C | T_SELFDESTRUCT_C | T_PRECOMPILE_C
           | T_FALLBACK_C;
  hdr_comment = T_C_NOT_PAYABLE | T_C_NOT_PAYABLE_INVALID | T_C_DEFAULT | T_C_NOT_PAYABLE_DEFAULT
              | T_C_SOLIDITY08;
  any_comment = hdr_comment | T_C_RECURSIVE | T_C_PRECOMPILED | T_C_ABORTED | T_COMMENT;
  eol = T_COMMENT? T_EOL;

  ex = expr_first @x;
  ex_nomem = ( expr_first - T_MEMORY ) @x;
  ex_noidx = ( expr_first - T_INDEXED ) @x;
  ex_nosig = ( expr_first - ( T_IDENT_CALL | T_INDEXED ) ) @x;
  datalist = ex ( T_COMMA ex )*;
  log_items = ( T_INDEXED ( expr_first - T_INDEXED ) @x_indexed | ex_noidx )
              ( T_COMMA ( T_INDEXED ( expr_first - T_INDEXED ) @x_indexed | ex_noidx ) )*;

  stype_num = T_NUM | T_HEX;
  stype_wrap = T_MAPPING T_OF @w_mapping
             | T_ARRAY T_OF @w_array
             | T_FIXED T_ARRAY T_OF @w_fixed ( T_NUM @w_len )?;
  stype_base = T_TYPE @b_value ( T_LBRACK T_NUM @b_fixed_len T_RBRACK )?
             | T_BYTES @b_bytes
             | T_STRUCT @b_struct ( T_OF T_NUM @b_slots ( T_SLOT | T_SLOTS ) )?;

  def_line = T_DEF (
        T_STORAGE ( T_COLON eol @s_def_storage
                  | T_LPAREN T_IDENT T_RPAREN T_COLON eol @s_def_vyper )
      | T_SAFEMATH T_COLON eol @s_def_safemath
      | T_INTERNAL_C @rem_a @sig_def T_COLON T_C_RECURSIVE @rem_comment T_EOL @s_def_internal
      | def_name @rem_a @sig_def T_PAYABLE? T_COLON ( hdr_comment @rem_comment )? T_EOL @s_def
  );

  const_line = T_CONST ( names @rem_a T_ASSIGN datalist eol @s_const
                       | def_name @sig_def T_ASSIGN datalist eol @s_const_sig );

  log_line = T_LOG @rem_a (
        T_EOL @s_log_none
      | T_IDENT_CALL @sig_log ( T_COLON log_items? )? eol @s_log_sig
      | ex_nosig ( T_COLON log_items? eol @s_log_topic
                 | ( T_COMMA ex_nosig )* eol @s_log_data )
  );

  # the lines whose first word is also a name: decided by the second token
  # (priorities: a name's assignment otherwise)
  stor_item = names @rem_a ( T_IS >(lead, 2) ) stype_wrap* stype_base T_AT T_STORAGE
              stype_num @rem_b ( T_OFFSET T_NUM @si_offset )? eol @s_stor_item;
  label_while = T_IDENT @rem_a ( T_COLON >(lead, 2) ) T_WHILE ex T_COLON eol @s_while;
  a_funct = T_FUNCT ( ex >(lead, 1) ) eol @a_funct;
  a_value = T_VALUE ( ex >(lead, 1) ) T_WEI eol @a_value;
  a_gas = T_GAS ( ex >(lead, 1) ) eol @a_gas;
  a_args = T_ARGS ( ex >(lead, 1) ) ( T_COMMA ex )* eol @a_args;
  a_from = T_FROM ( ex >(lead, 1) ) eol @a_from;
  a_len = T_LEN ( ex >(lead, 1) ) eol @a_len;
  a_to = T_TO ( ex >(lead, 1) ) eol @a_to;
  a_code = T_CODE ( T_COLON >(lead, 1) ) datalist eol @a_code;
  a_salt = T_SALT ( T_COLON >(lead, 1) ) ex eol @a_salt;
  lead = names | brackets | calls | T_LPAREN;
  fallback = lead ( any >(lead, 0) ) @go_assign;

  main := (
      any_comment T_EOL @s_comment
    | def_line
    | const_line
    | T_IF ex T_COLON eol @s_if
    | T_ELSE T_COLON eol @s_else
    | T_WHILE ex T_COLON eol @s_while
    | T_CONTINUE ( T_IDENT @rem_a )? eol @s_continue
    | T_BREAK eol @s_break
    | T_REQUIRE ex eol @s_require
    | T_ASSERT ex eol @s_assert
    | T_REVERT ( eol @s_revert
               | T_WITH ( T_MEMORY eol @s_revert_mem
                        | ex_nomem ( T_COMMA ex )* eol @s_revert_data ) )
    | T_RETURN ( eol @s_return
               | T_MEMORY eol @s_return_mem
               | ex_nomem ( T_COMMA ex )* eol @s_return_data )
    | T_STOP eol @s_stop
    | T_INVALID eol @s_invalid
    | T_SELFDESTRUCT_C ex T_RPAREN eol @s_selfdestruct
    | log_line
    | ( T_CALL @k_call | T_STATIC_CALL @k_static | T_DELEGATE @k_delegate | T_CODECALL @k_codecall )
      ex T_WITH T_COLON eol @s_call
    | ( T_CREATE @k_create | T_CREATE2 @k_create2 ) T_CONTRACT T_WITH ex T_WEI eol @s_create
    | T_INTERNAL_C @rem_b ( ex ( T_COMMA ex )* )? T_RPAREN eol @s_internal
    | T_ELLIPSIS T_C_ABORTED T_EOL @s_aborted
    | stor_item | label_while
    | a_funct | a_value | a_gas | a_args | a_from | a_len | a_to | a_code | a_salt
    | fallback
  );

  assign := ex ( ( T_COMMA ex )* T_ASSIGN @lv_count (
                     T_PRECOMPILE_C @rem_b ( ex ( T_COMMA ex )* )? T_RPAREN T_C_PRECOMPILED T_EOL @s_precompiled
                   | T_INTERNAL_C @rem_b ( ex ( T_COMMA ex )* )? T_RPAREN eol @s_internal_results
                   | datalist eol @s_assign )
               | T_PLUSEQ ex eol @s_add
               | T_MINUSEQ ex eol @s_sub
               | T_PLUSPLUS eol @s_inc
               | T_MINUSMINUS eol @s_dec );
}%%

%% write data noerror nofinal;

void Parser::parse_line(std::uint32_t line)
{
    line_ = line;
    const Line& ln = lx_.lines[line];
    parts_.clear();
    swrap_.clear();
    sbase_ = SType{};
    nlv_ = 0;
    tok_a_ = tok_b_ = none;
    call_kind_ = 0;
    item_ = Item{};
    item_.indent = ln.indent;
    item_.number = ln.number;
    error_.clear();
    error_tok_ = none;
    std::uint32_t comment_tok = none;
    bool comment_line = false;

    // a line at the indentation 0 ends the def it was in
    if (ln.indent == 0)
    {
        ctx_ = Ctx::top;
        fn_ = none;
        sm_ = none;
    }
    else if (ctx_ == Ctx::sm_def && ln.indent <= 2)
        ctx_ = Ctx::safemath;

    int cs;
    const std::uint16_t* p = k0_ + ln.first;
    const std::uint16_t* pe = k0_ + ln.last;
    %% write init;
    %% write exec;

    if (comment_line)
        return;
    if (item_.kind == LK_NONE || !error_.empty())
    {
        if (error_.empty())
            fail(p < pe ? index(p) : ln.last - 1, "a line this can't read");
        std::string msg = "line " + std::to_string(ln.number) + ": " + error_;
        if (error_tok_ != none && error_tok_ < lx_.tokens.size())
            msg += " (at " + std::string(token_name(Tok(kind(error_tok_)))) + " '" + std::string(span(error_tok_)) + "')";
        prog_.errors.push_back(std::move(msg));
        // the line, left out, keeps the blocks as they are: a block opener
        // (it ends with a colon) as an if that can't run, any other line as
        // a statement that can't
        Item bad;
        bad.indent = ln.indent;
        bad.number = ln.number;
        const bool opener = ln.last >= ln.first + 2 && kind(ln.last - 2) == T_COLON;
        if (ctx_ == Ctx::storage || (ln.indent == 0 && !opener))
            return;
        const std::uint32_t saved = line_;
        line_ = line;
        if (opener)
        {
            const StmtId s = stmt(St::if_);
            bad.kind = LK_IF;
            bad.stmt = s;
        }
        else
        {
            const StmtId s = stmt(St::aborted);
            prog_.stmts[s].aux = 1;  // a line that couldn't be parsed
            bad.kind = LK_SIMPLE;
            bad.stmt = s;
        }
        line_ = saved;
        if (ln.indent == 0)
            return;
        items_.push_back(std::move(bad));
        return;
    }
    items_.push_back(std::move(item_));
}

// --- the blocks ---------------------------------------------------------------------------------

%%{
  machine blocks;
  alphtype unsigned char;
  import "text_lines.hpp";

  prepush {
      if (top >= static_cast<int>(stack_vec.size()))
          stack_vec.resize(stack_vec.size() * 2);
      stack = stack_vec.data();
  }

  action b_append { append(it()); }
  action b_call { append(it()); last = it().stmt; }
  action b_funct { prog_.stmts[last].b = it().exprs.at(0); }
  action b_value { prog_.stmts[last].c = it().exprs.at(0); }
  action b_args { prog_.stmts[last].list = it().exprs; prog_.stmts[last].has_args = true; }
  action b_from { prog_.stmts[last].a = it().exprs.at(0); }
  action b_len { prog_.stmts[last].b = it().exprs.at(0); }
  action b_to { prog_.stmts[last].b = it().exprs.at(0); prog_.stmts[last].aux = 1; }
  action b_salt { prog_.stmts[last].b = it().exprs.at(0); }
  action b_code { prog_.stmts[last].list = it().exprs; }
  action b_if { append(it()); pending = &prog_.stmts[it().stmt].body; }
  action b_else {
      // the if: the last statement of the block
      auto& blk = *blocks.back();
      if (blk.empty() || prog_.stmts[blk.back()].kind != St::if_) { bad = "an else after no if"; fbreak; }
      pending = &prog_.stmts[blk.back()].orelse;
  }
  action b_while { append(it()); pending = &prog_.stmts[it().stmt].body; }
  action b_enter { blocks.push_back(pending); fcall block; }
  action b_leave { blocks.pop_back(); fret; }
  action b_fn { pending = &prog_.functions[it().def].body; }
  action b_sm { pending = &prog_.safemath[it().def].body; }

  stmt = LK_SIMPLE @b_append
       | LK_CALL @b_call ( LK_FUNCT @b_funct )? ( LK_VALUE @b_value )? LK_GAS? ( LK_ARGS @b_args )?
       | LK_MEMRET @b_call LK_FROM @b_from ( LK_LEN @b_len | LK_TO @b_to )
       | LK_CREATE @b_call ( LK_SALT @b_salt )? LK_CODE @b_code
       | LK_IF @b_if LK_INDENT @b_enter ( LK_ELSE @b_else LK_INDENT @b_enter )?
       | LK_WHILE @b_while LK_INDENT @b_enter;

  block := stmt* LK_DEDENT @b_leave;

  storage = LK_DEF_STORAGE LK_INDENT LK_STOR_ITEM+ LK_DEDENT;
  safemath = LK_DEF_SAFEMATH LK_INDENT ( LK_SM_DEF @b_sm LK_INDENT @b_enter )+ LK_DEDENT;
  func = ( LK_DEF_FUNC | LK_DEF_INTERNAL ) @b_fn LK_INDENT @b_enter;

  main := ( LK_CONST | storage | safemath | func )*;
}%%

%% write data nofinal;

void Parser::build()
{
    // the lines' kinds, with INDENT and DEDENT where the indentation goes
    // deeper and back (the lines that go on a statement aren't counted)
    std::vector<std::uint8_t> seq;
    std::vector<std::uint32_t> seq_item;
    std::vector<std::uint32_t> levels{0};
    for (std::uint32_t i = 0; i < items_.size(); ++i)
    {
        const Item& item = items_[i];
        switch (item.kind)
        {
        case LK_FUNCT:
        case LK_VALUE:
        case LK_GAS:
        case LK_ARGS:
        case LK_FROM:
        case LK_LEN:
        case LK_TO:
        case LK_SALT:
        case LK_CODE:
            seq.push_back(item.kind);
            seq_item.push_back(i);
            continue;
        default:
            break;
        }
        if (item.indent > levels.back())
        {
            levels.push_back(item.indent);
            seq.push_back(LK_INDENT);
            seq_item.push_back(i);
        }
        else
        {
            while (item.indent < levels.back())
            {
                levels.pop_back();
                seq.push_back(LK_DEDENT);
                seq_item.push_back(i);
            }
            if (item.indent != levels.back())
            {
                prog_.errors.push_back("line " + std::to_string(item.number)
                    + ": an indentation that matches no enclosing block");
                return;
            }
        }
        seq.push_back(item.kind);
        seq_item.push_back(i);
    }
    while (levels.size() > 1)
    {
        levels.pop_back();
        seq.push_back(LK_DEDENT);
        seq_item.push_back(static_cast<std::uint32_t>(items_.size()));
    }

    std::vector<std::vector<StmtId>*> blocks;
    std::vector<StmtId>* pending = nullptr;
    StmtId last = none;
    const char* bad = nullptr;
    std::vector<int> stack_vec(64);
    int* stack = stack_vec.data();
    int top = 0;
    int cs;
    const std::uint8_t* p = seq.data();
    const std::uint8_t* pe = p + seq.size();
    auto it = [&]() -> Item& { return items_[seq_item[static_cast<std::size_t>(p - seq.data())]]; };
    auto append = [&](const Item& item) { blocks.back()->push_back(item.stmt); };
    %% write init;
    %% write exec;
    if (bad != nullptr || cs == blocks_error || p != pe)
    {
        const std::size_t at = static_cast<std::size_t>(p - seq.data());
        const std::uint32_t number = at < seq_item.size() && seq_item[at] < items_.size()
            ? items_[seq_item[at]].number : 0;
        prog_.errors.push_back("line " + std::to_string(number) + ": "
            + (bad != nullptr ? bad : "a line that can't go there (its block, its indentation)"));
    }
}

Program Parser::run()
{
    if (!lx_.error.empty())
        prog_.errors.push_back("line " + std::to_string(lx_.error_line) + ": " + lx_.error);
    k0_ = lx_.kinds.data();
    items_.reserve(lx_.lines.size());
    for (std::uint32_t i = 0; i < lx_.lines.size(); ++i)
        parse_line(i);
    build();
    // the calls of the recursive internal functions: by their entry
    for (const auto& [s, entry] : internal_refs_)
    {
        const auto it = internal_entries_.find(entry);
        if (it == internal_entries_.end())
        {
            prog_.errors.push_back("line " + std::to_string(prog_.stmts[s].line)
                + ": a call of an internal function the text doesn't have");
            prog_.stmts[s].kind = St::aborted;
            prog_.stmts[s].aux = 1;
            continue;
        }
        prog_.stmts[s].aux = static_cast<std::uint16_t>(it->second);
    }
    return std::move(prog_);
}
}  // namespace

Program parse(std::string_view text)
{
    return Parser(text).run();
}

bool place_params(Program& program, std::uint32_t selector, std::span<const std::uint32_t> positions)
{
    for (auto& f : program.functions)
    {
        if (f.kind != Function::regular || f.selector != selector)
            continue;
        if (f.params.size() != positions.size())
            return false;
        for (std::size_t i = 0; i < positions.size(); ++i)
            f.params[i].position = positions[i];
        return true;
    }
    return false;
}

std::uint32_t selector_of(std::string_view signature)
{
    const Word h = keccak256(BytesView(reinterpret_cast<const std::uint8_t*>(signature.data()), signature.size()));
    return static_cast<std::uint32_t>(h >> 224);
}
}  // namespace validate::text
