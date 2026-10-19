// The decompiled text as a program (text_parser.rl makes it, text_interp
// runs it): the storage it declares, its SafeMath, its functions, their
// statements and expressions - by what they mean, not how they're printed.
//
// Expressions and statements live in flat arrays of the Program, referred to
// by index. Names are integer ids: a local variable is an index into the
// frame of its function, a param an index into its params, a storage
// variable an index into the definitions. The text of the names stays only
// for the display.
#pragma once

#include "validate/world.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace validate::text
{
using ExprId = std::uint32_t;
using StmtId = std::uint32_t;
inline constexpr std::uint32_t none = 0xffffffffu;

/// What an expression is. The number of operands (Expr::n) and Expr::aux
/// are said for each.
enum class Op : std::uint16_t
{
    // leaves
    num,        ///< a number: Program::nums[aux]
    big,        ///< a number of more than 256 bits (code: Bytes(420, 0x6080...)): its
                ///< big-endian bytes Program::strs[aux]
    str,        ///< 'text': the bytes Program::strs[aux]
    var,        ///< a local variable: its id aux
    param,      ///< a param of the function: its index aux
    stor_var,   ///< a storage variable: its definition aux
    selector,   ///< a 4-byte selector (Error(string reason), unknown12345678(?)): aux
    sm_param,   ///< a param of a SafeMath function: its index aux

    // what the EVM gives (no operands)
    caller,
    origin,
    gas_price,
    call_value,
    func_hash,
    calldata_size,
    return_data_size,
    this_address,
    gas,
    chain_id,
    msize,
    number,
    timestamp,
    coinbase,
    difficulty,
    gas_limit,
    base_fee,
    blob_base_fee,
    call_success,    ///< ext_call.success and the like: the last call's success
    create_address,  ///< create.new_address, create2.new_address

    // unary
    neg,      ///< -x
    bit_not,  ///< ~x
    not_,     ///< not x

    // binary (2 operands)
    add,
    sub,
    mul,
    div,
    mod,
    pow,
    shl,
    shr,
    sar,
    bit_and,
    bit_or,
    bit_xor,
    eq,
    ne,
    lt,
    gt,
    le,
    ge,
    slt,
    sgt,
    sle,
    sge,
    sadd,
    smul,
    sdiv,
    smod,
    land,  ///< python's and: the first operand when it's 0, else the second
    lor,   ///< python's or: the first operand when it isn't 0, else the second
    range, ///< a len n: inside brackets only (mem[a len n]...), gone after parsing

    // functions
    to_bool,        ///< bool(x)
    cast_uint,      ///< uintN(x), address(x): the low aux bits
    cast_int,       ///< intN(x): the low aux bits sign-extended
    mask,           ///< Mask(size, offset, x)
    ceil32,
    floor32,
    min,            ///< n >= 1 operands
    max,
    byte,           ///< byte(i, x)
    clz,
    signextend,     ///< signextend(b, x)
    shift,          ///< shift(x, n)
    addmod,
    mulmod,
    sha3,           ///< sha3(data...): n elements of data
    concat,         ///< concat(data...)
    array,          ///< Array(len=l, data=...): the length, then the elements
    bytes,          ///< Bytes(n, v)
    balance,        ///< eth.balance(a)
    ext_code_size,  ///< ext_code.size(a)
    ext_code_hash,  ///< ext_code.hash(a)
    ext_code,       ///< ext_code(a) - only before .data[...]
    ext_code_copy,  ///< ext_code(a).data[s len n]: a, s, n
    block_hash,
    blob_hash,
    panic,          ///< Panic(n) in a revert's data: the selector and the word n
    safemath,       ///< SafeMath.f(...): the definition aux, its operands

    // memory, calldata, return data, code, transient storage
    mem,          ///< mem[a]: the word at a
    mem_range,    ///< mem[a len n]
    cd,           ///< cd[a]: the word of calldata at a
    call_data,    ///< call.data[a len n] (n 32 when written call.data[a])
    return_data,  ///< ext_call.return_data[a len n] (32: [a])
    code_data,    ///< code.data[a len n]
    transient,    ///< transient[k]

    // the places of the storage (and of the params): a path from a storage
    // variable (stor_var), a slot (stor_raw) or a param
    stor_raw,  ///< stor[slot]
    index,     ///< base[key]
    length,    ///< base.length
    field,     ///< base.field_N: N = aux
    all,       ///< base[all]
    member,    ///< base.name (a member of a struct param): the name Program::names[aux]

    // the address of an external call and what it calls (call ... with:)
    callee_sig,  ///< addr.f(sig): the address, the selector aux
    callee_mem,  ///< addr.mem[a len 4]: the address, the range
};

struct Expr
{
    Op op = Op::num;
    std::uint16_t n = 0;     ///< the number of operands
    std::uint32_t aux = 0;   ///< see Op
    std::uint32_t kids = 0;  ///< the first operand: Program::kids[kids + i]
};

/// What a statement is.
enum class St : std::uint16_t
{
    assign,         ///< a = b; mem[...] = list (a list of data)
    add_assign,     ///< a += b
    sub_assign,     ///< a -= b
    inc,            ///< a++
    dec,            ///< a--
    if_,            ///< if a: body else: orelse
    while_,         ///< [label:] while a: body (aux: its label, 0 none)
    continue_,      ///< continue [label] (aux: the label, 0 the innermost loop)
    break_,
    require,        ///< a
    assert_,        ///< a
    revert,         ///< revert [with list] (aux 1: the list is an Error(string)'s text)
    return_,        ///< return list
    revert_memory,  ///< revert with memory from a len b (aux 1: from a to b)
    return_memory,  ///< return memory from a len b (aux 1: from a to b)
    stop,
    invalid,
    selfdestruct,   ///< a: the beneficiary
    log,            ///< topics: list2, data: list
    call,           ///< aux: CallKind; a: the address (callee_sig / callee_mem /
                    ///< other), b: funct (none), c: the value (none: 0); list: args
                    ///< (has_args: whether there's an args line)
    create,         ///< aux: CreateKind; a: the value, b: the salt; list: the code
    precompiled,    ///< var = name(list) # precompiled: aux the address, vars[0]
    internal_call,  ///< vars = internal_0x..(list): aux the function
    leave,          ///< return list (of a recursive internal function)
    aborted,        ///< ...  # Decompilation aborted
};

struct Stmt
{
    St kind = St::stop;
    std::uint16_t aux = 0;
    bool has_args = false;      ///< a call's args line
    std::uint32_t line = 0;     ///< its line in the text
    ExprId a = none;
    ExprId b = none;
    ExprId c = none;
    std::vector<ExprId> list;
    std::vector<ExprId> list2;
    std::vector<std::uint32_t> vars;
    std::vector<StmtId> body;
    std::vector<StmtId> orelse;
};

/// A type of the storage (def storage:).
struct SType
{
    enum Kind : std::uint8_t
    {
        value,     ///< width bits (uint8, address...)
        struct_,   ///< width: its slots (0: not said)
        mapping,   ///< of elem
        array,     ///< of elem: its length at the slot, its elements from keccak(slot)
        fixed,     ///< of elem: its elements from the slot (length: said, 0 not)
        bytes,
    };
    Kind kind = value;
    std::uint32_t width = 256;
    std::uint32_t elem = none;  ///< an index into Program::types
    std::uint64_t length = 0;
};

struct StorageDef
{
    std::string name;
    Word slot;
    std::uint32_t offset = 0;  ///< in bits
    std::uint32_t type = none; ///< an index into Program::types
    std::uint32_t line = 0;
};

/// A type of a param (of the calldata), for where its words are.
struct PType
{
    std::string canonical;           ///< as in a signature: (uint256,address)[3]
    bool dynamic = false;            ///< its head is an offset
    std::uint32_t words = 1;         ///< its words in the head (1 when dynamic)
    std::uint32_t count = 0;         ///< of a static array: its elements
    std::uint32_t elem_words = 1;    ///< of an array: the head words of an element
    bool elem_dynamic = false;
    bool is_array = false;           ///< T[] or T[k] (or the decompiler's `array`)
    bool has_length = false;         ///< bytes, string, T[], array: p.length
    std::vector<PType> components;   ///< of a tuple, without their names
};

struct Param
{
    std::string name;
    PType type;
    std::uint32_t position = 4;  ///< the calldata offset of its first head word
};

struct Function
{
    enum Kind : std::uint8_t
    {
        regular,
        constant,  ///< const name = data
        fallback,  ///< _fallback(?)
        internal,  ///< def internal_0x..(_param1, ...): recursive
    };
    Kind kind = regular;
    std::string name;             ///< as printed (the signature)
    std::uint32_t selector = 0;   ///< regular, constant
    bool payable = true;
    bool value_invalid = false;   ///< # not payable (invalid): an invalid opcode
    bool unknown_params = false;  ///< f(?): its params, _param1..., the words it reads
    std::vector<Param> params;
    std::vector<StmtId> body;
    std::vector<ExprId> data;     ///< a constant's data
    std::uint64_t entry = 0;      ///< internal: its code offset
    std::uint32_t frame = 0;      ///< internal: the stack words a call takes
    std::vector<std::string> vars;  ///< the names of its local variables, by id
    std::uint32_t line = 0;
};

/// A function of `def SafeMath:` - its params a (b), errorMessage...
struct SafeMathDef
{
    std::string name;
    std::uint32_t words = 2;      ///< the operands: 1 for inc and dec
    std::uint32_t messages = 0;   ///< the errorMessage params after them
    bool solidity08 = false;
    std::vector<StmtId> body;
    std::uint32_t line = 0;
};

struct Program
{
    std::vector<Expr> exprs;
    std::vector<ExprId> kids;
    std::vector<Word> nums;
    std::vector<Bytes> strs;
    std::vector<std::string> names;  ///< members of struct params
    std::vector<Stmt> stmts;

    bool vyper = false;  ///< def storage (vyper): mappings hash the slot, then the key
    std::vector<SType> types;
    std::vector<StorageDef> storage;
    std::vector<SafeMathDef> safemath;
    std::vector<Function> functions;

    /// "line N: what" for each line that couldn't be parsed.
    std::vector<std::string> errors;

    const Expr& expr(ExprId e) const { return exprs[e]; }
    ExprId kid(ExprId e, unsigned i) const { return kids[exprs[e].kids + i]; }
};
}  // namespace validate::text
