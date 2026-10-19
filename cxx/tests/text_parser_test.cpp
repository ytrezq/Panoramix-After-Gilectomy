// validate/text_lexer.rl, text_parser.rl: the decompiled text's tokens, its
// lines and blocks, its expressions, its signatures, as a Program.
#include "validate/text_lexer.hpp"
#include "validate/scan.hpp"
#include "validate/text_parser.hpp"

#include "validate_test_util.hpp"

#include <string>
#include <vector>

using namespace validate;
using namespace validate::text;

namespace
{
std::vector<Tok> kinds(const Lexed& lx)
{
    std::vector<Tok> out;
    for (const auto k : lx.kinds)
        out.push_back(static_cast<Tok>(k));
    return out;
}

/// An expression's shape, as a nested string: add(var, num 1)...
std::string shape(const Program& p, ExprId e)
{
    const Expr& x = p.exprs[e];
    std::string s;
    switch (x.op)
    {
    case Op::num: return validate::hex(p.nums[x.aux]);
    case Op::var: return "var" + std::to_string(x.aux);
    case Op::param: return "param" + std::to_string(x.aux);
    case Op::stor_var: return "stor" + std::to_string(x.aux);
    case Op::str: return "'" + std::string(p.strs[x.aux].begin(), p.strs[x.aux].end()) + "'";
    case Op::selector: return "sel" + validate::hex(Word{x.aux});
    case Op::add: s = "add"; break;
    case Op::sub: s = "sub"; break;
    case Op::mul: s = "mul"; break;
    case Op::pow: s = "pow"; break;
    case Op::neg: s = "neg"; break;
    case Op::not_: s = "not"; break;
    case Op::eq: s = "eq"; break;
    case Op::lt: s = "lt"; break;
    case Op::land: s = "and"; break;
    case Op::lor: s = "or"; break;
    case Op::bit_and: s = "band"; break;
    case Op::shr: s = "shr"; break;
    case Op::mem: s = "mem"; break;
    case Op::mem_range: s = "memr"; break;
    case Op::index: s = "index"; break;
    case Op::field: s = "field" + std::to_string(x.aux); break;
    case Op::length: s = "length"; break;
    case Op::all: s = "all"; break;
    case Op::cast_uint: s = "uint" + std::to_string(x.aux); break;
    case Op::mask: s = "mask"; break;
    case Op::sha3: s = "sha3"; break;
    case Op::bytes: s = "bytes"; break;
    case Op::array: s = "array"; break;
    case Op::caller: return "caller";
    case Op::callee_sig: s = "callee" + validate::hex(Word{x.aux}); break;
    case Op::return_data: s = "retdata"; break;
    case Op::safemath: s = "safemath" + std::to_string(x.aux); break;
    case Op::member: s = "member"; break;
    case Op::stor_raw: s = "storraw"; break;
    default: s = "op" + std::to_string(static_cast<int>(x.op)); break;
    }
    s += "(";
    for (unsigned i = 0; i < x.n; ++i)
        s += (i ? ", " : "") + shape(p, p.kid(e, i));
    return s + ")";
}

/// The program of a function's body (its first function).
const Function& first_fn(const Program& p)
{
    REQUIRE(!p.functions.empty());
    return p.functions.front();
}

const Stmt& stmt0(const Program& p, std::size_t i = 0)
{
    const Function& f = first_fn(p);
    REQUIRE(f.body.size() > i);
    return p.stmts[f.body[i]];
}

std::string fn_text(const std::string& body)
{
    return "def f(uint256 a, address b): # not payable\n" + body;
}
}  // namespace

TEST_CASE("text: the tokens, the logical lines")
{
    const auto lx = lex("def f():\n  x = (1 +\n     2)\n  return x, \n         y\n\n  # a comment\n");
    CHECK(lx.error.empty());
    REQUIRE(lx.lines.size() == 4);
    CHECK(lx.lines[0].indent == 0);
    CHECK(lx.lines[1].indent == 2);
    CHECK(lx.lines[1].number == 2);
    // the brackets and the trailing comma join the lines
    CHECK(kinds(lx) == std::vector<Tok>{T_DEF, T_IDENT_CALL, T_RPAREN, T_COLON, T_EOL, T_IDENT, T_ASSIGN,
                           T_LPAREN, T_NUM, T_PLUS, T_NUM, T_RPAREN, T_EOL, T_RETURN, T_IDENT, T_COMMA,
                           T_IDENT, T_EOL, T_COMMENT, T_EOL});

    const auto ops = lex("a >=′ b >>′ 2 <′ c +′ d mem[x len 4] p[all] s.field_256 s.length desc.amount");
    CHECK(kinds(ops) == std::vector<Tok>{T_IDENT, T_SGE, T_IDENT, T_SAR, T_NUM, T_SLT, T_IDENT, T_SADD,
                            T_IDENT, T_MEM_B, T_IDENT, T_LEN, T_NUM, T_RBRACK, T_IDENT, T_ALL, T_IDENT,
                            T_DOT_FIELD, T_IDENT, T_DOT_LENGTH, T_IDENT, T_DOT_MEMBER, T_EOL});

    const auto kw = lex("value to from=caller len=3 data=x call.value ext_call.return_data[0] uint8(x) "
                        "SafeMath.add(a) static call x.transfer(address to) # not payable (invalid)");
    CHECK(kinds(kw) == std::vector<Tok>{T_VALUE, T_TO, T_IDENT_EQ, T_CALLER, T_LEN_EQ, T_NUM, T_DATA_EQ,
                           T_IDENT, T_CALLVALUE, T_RETDATA_B, T_NUM, T_RBRACK, T_UINT_C, T_IDENT, T_RPAREN,
                           T_SAFEMATH_C, T_IDENT, T_RPAREN, T_STATIC_CALL, T_IDENT, T_DOT_CALL, T_TYPE,
                           T_TO, T_RPAREN, T_C_NOT_PAYABLE_INVALID, T_EOL});

    CHECK(token_name(T_EOL) == "end of line");
    CHECK(token_name(T_FALLBACK_C) == "_fallback(");
    CHECK(token_name(T_SAR) == ">>′");

    const auto bad = lex("x = (1\n");
    CHECK(!bad.error.empty());
}

TEST_CASE("text: the operators' precedences")
{
    const auto p = parse(fn_text("  x = a + b * 2 ** 3\n  y = -a ** 2\n  z = not a == b and b or a\n"
                                 "  w = (a - b) - (a - 1) & a >> 3\n"));
    CHECK(p.errors.empty());
    CHECK(shape(p, stmt0(p, 0).b) == "add(param0, mul(param1, pow(0x2, 0x3)))");
    CHECK(shape(p, stmt0(p, 1).b) == "neg(pow(param0, 0x2))");
    CHECK(shape(p, stmt0(p, 2).b) == "or(and(not(eq(param0, param1)), param1), param0)");
    CHECK(shape(p, stmt0(p, 3).b) == "band(sub(sub(param0, param1), sub(param0, 0x1)), shr(param0, 0x3))");
}

TEST_CASE("text: the places of the storage, the memory, the params")
{
    const std::string text =
        "def storage:\n"
        "  balanceOf is mapping of uint256 at storage 1\n"
        "  tokens is array of struct of 2 slots at storage 2\n"
        "  stor8_112 is uint112 at storage 8 offset 112\n"
        "  big is uint256 at storage 0x2c355a1029f7297de90b706beea350b0073a5f8d06c07726a159113e4caa7d69\n"
        "  fixed3 is uint256[3] at storage 9\n"
        "  allow is mapping of mapping of uint8 at storage 10\n"
        "\n"
        "def f(bytes data, uint256[3] amounts, (uint256,address) order): # not payable\n"
        "  x = balanceOf[caller]\n"
        "  y = address(tokens[x].field_256)\n"
        "  z = mem[mem[64] + 4 len data.length]\n"
        "  w = data[all]\n"
        "  v = amounts[2] + order.amount\n"
        "  u = allow[caller][b] + stor[x].field_8\n";
    const auto p = parse(text);
    CHECK(p.errors.empty());
    REQUIRE(p.storage.size() == 6);
    CHECK(p.storage[2].slot == 8);
    CHECK(p.storage[2].offset == 112);
    CHECK(p.types[p.storage[2].type].width == 112);
    CHECK(p.storage[3].slot == *parse_number("0x2c355a1029f7297de90b706beea350b0073a5f8d06c07726a159113e4caa7d69"));
    const auto& t1 = p.types[p.storage[1].type];
    CHECK(t1.kind == SType::array);
    CHECK(p.types[t1.elem].kind == SType::struct_);
    CHECK(p.types[t1.elem].width == 2);
    const auto& t4 = p.types[p.storage[4].type];
    CHECK(t4.kind == SType::fixed);
    CHECK(t4.length == 3);
    const auto& t5 = p.types[p.storage[5].type];
    CHECK(t5.kind == SType::mapping);
    CHECK(p.types[t5.elem].kind == SType::mapping);

    const Function& f = first_fn(p);
    REQUIRE(f.params.size() == 3);
    CHECK(f.params[0].position == 4);
    CHECK(f.params[0].type.dynamic);
    CHECK(f.params[1].position == 36);
    CHECK(f.params[1].type.words == 3);
    CHECK(f.params[2].position == 132);
    CHECK(f.params[2].type.words == 2);
    CHECK(f.selector == selector_of("f(bytes,uint256[3],(uint256,address))"));

    CHECK(shape(p, stmt0(p, 0).b) == "index(stor0, caller)");
    CHECK(shape(p, stmt0(p, 1).b) == "uint160(field256(index(stor1, var0)))");
    CHECK(shape(p, stmt0(p, 2).b) == "memr(add(mem(0x40), 0x4), length(param0))");
    CHECK(shape(p, stmt0(p, 3).b) == "all(param0)");
    CHECK(shape(p, stmt0(p, 4).b) == "add(index(param1, 0x2), member(param2))");
    CHECK(shape(p, stmt0(p, 5).b) == "add(index(index(stor5, caller), var6), field8(storraw(var0)))");
}

TEST_CASE("text: the statements")
{
    const std::string text =
        "const name = 'Uniswap V2'\n"
        "const decimals = 18\n"
        "\n"
        "def storage:\n"
        "  owner is address at storage 0\n"
        "\n"
        "def SafeMath:\n"
        "  def sub(a, b, errorMessage):\n"
        "      if b > a:\n"
        "          revert with errorMessage\n"
        "      return a - b\n"
        "\n"
        "def transfer(address to, uint256 amount): # not payable\n"
        "  require calldata.size - 4 >= 64\n"
        "  if owner != caller:\n"
        "      revert with 'Ownable: caller is not the owner'\n"
        "  else:\n"
        "      x = SafeMath.sub(amount, 1, 'too low')\n"
        "  idx = 0\n"
        "  loop1: while idx < amount:\n"
        "      if idx == 3:\n"
        "          break\n"
        "      idx = idx + 1\n"
        "      continue loop1\n"
        "  log Transfer(\n"
        "        address indexed from=caller,\n"
        "        address indexed to=address(to),\n"
        "        uint256 value=amount)\n"
        "  log 0xddf252ad: amount, indexed caller\n"
        "  call to.balanceOf(address account) with:\n"
        "     value 5 wei\n"
        "       gas gas_remaining\n"
        "      args this.address\n"
        "  signer = ecrecover(mem[0 len 128]) # precompiled\n"
        "  mem[64 len 36] = Bytes(4, 0xa9059cbb), caller\n"
        "  revert with Error(string reason), 32, 2, 'ab', mem[100 len 30]\n"
        "  return memory\n"
        "    from 128\n"
        "     len 64\n"
        "\n"
        "def _fallback(?) payable: # default function\n"
        "  revert with Panic(17)  # If an arithmetic operation results in underflow\n";
    const auto p = parse(text);
    for (const auto& e : p.errors)
        MESSAGE(e);
    CHECK(p.errors.empty());
    REQUIRE(p.functions.size() == 4);
    CHECK(p.functions[0].kind == Function::constant);
    CHECK(p.functions[0].selector == selector_of("name()"));
    CHECK(p.functions[1].selector == selector_of("decimals()"));
    REQUIRE(p.safemath.size() == 1);
    CHECK(p.safemath[0].words == 2);
    CHECK(p.safemath[0].messages == 1);
    CHECK(p.safemath[0].body.size() == 2);

    const Function& f = p.functions[2];
    CHECK(f.selector == 0xa9059cbb);
    CHECK(!f.payable);
    REQUIRE(f.body.size() == 11);
    const auto& st = [&](std::size_t i) -> const Stmt& { return p.stmts[f.body[i]]; };
    CHECK(st(0).kind == St::require);
    CHECK(st(1).kind == St::if_);
    CHECK(st(1).body.size() == 1);
    CHECK(st(1).orelse.size() == 1);
    CHECK(p.stmts[st(1).body[0]].aux == 1);  // revert with 'text': Error(string)
    CHECK(shape(p, p.stmts[st(1).orelse[0]].b) == "safemath0(param1, 0x1, 'too low')");
    CHECK(st(3).kind == St::while_);
    CHECK(st(3).aux == 1);
    CHECK(st(3).body.size() == 3);
    CHECK(p.stmts[st(3).body[2]].kind == St::continue_);
    CHECK(p.stmts[st(3).body[2]].aux == 1);
    // the log: topic 0 the event's signature, the indexed params, the data
    CHECK(st(4).kind == St::log);
    REQUIRE(st(4).list2.size() == 3);
    CHECK(p.nums[p.exprs[st(4).list2[0]].aux] ==
          *parse_number("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"));
    CHECK(st(4).list.size() == 1);
    CHECK(st(5).list2.size() == 2);
    CHECK(st(5).list.size() == 1);
    // the call and its lines
    CHECK(st(6).kind == St::call);
    CHECK(shape(p, st(6).a) == "callee0x70a08231(param0)");
    CHECK(st(6).c != none);
    CHECK(st(6).has_args);
    CHECK(st(6).list.size() == 1);
    CHECK(st(7).kind == St::precompiled);
    CHECK(st(7).aux == 1);
    CHECK(st(8).kind == St::assign);
    CHECK(st(8).list.size() == 2);
    CHECK(st(9).kind == St::revert);
    REQUIRE(st(9).list.size() == 5);
    CHECK(shape(p, st(9).list[0]) == "sel0x8c379a0");
    CHECK(st(10).kind == St::return_memory);
    CHECK(st(10).a != none);
    CHECK(st(10).b != none);
    CHECK(p.functions[3].kind == Function::fallback);
    CHECK(p.functions[3].payable);
}

TEST_CASE("text: the errors are by line, the rest is parsed")
{
    const auto p = parse(fn_text("  x = 1 +\n  y = 2\n  if x ++ y:\n      z = 3\n"));
    REQUIRE(p.errors.size() == 2);
    CHECK(p.errors[0].starts_with("line 2:"));
    CHECK(p.errors[1].starts_with("line 4:"));
    const Function& f = first_fn(p);
    REQUIRE(f.body.size() == 3);
    CHECK(p.stmts[f.body[0]].kind == St::aborted);
    CHECK(p.stmts[f.body[1]].kind == St::assign);
    // a block opener that can't be read: an if that can't run, its block kept
    CHECK(p.stmts[f.body[2]].kind == St::if_);
    CHECK(p.stmts[f.body[2]].a == none);
    CHECK(p.stmts[f.body[2]].body.size() == 1);
}
