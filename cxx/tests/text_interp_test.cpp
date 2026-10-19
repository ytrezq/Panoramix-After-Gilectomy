// validate/text_interp.cpp: the decompiled text run against the world, its
// effects - the meaning of each construct.
#include "validate/text_interp.hpp"
#include "validate/scan.hpp"
#include "validate/text_check.hpp"
#include "validate/text_parser.hpp"

#include "validate_test_util.hpp"

#include <string>
#include <variant>

using namespace validate;
using namespace validate::text;

namespace
{
Word word(std::string_view s)
{
    return *parse_number(s);
}

Bytes calldata(std::string_view signature, std::initializer_list<Word> args)
{
    Bytes out;
    const auto sel = selector_of(signature);
    for (int i = 3; i >= 0; --i)
        out.push_back(static_cast<std::uint8_t>(sel >> (8 * i)));
    for (const auto& a : args)
        append_word(out, a);
    return out;
}

Bytes words(std::initializer_list<Word> ws)
{
    Bytes out;
    for (const auto& w : ws)
        append_word(out, w);
    return out;
}

Bytes abi_error(std::string_view text)
{
    Bytes out{0x08, 0xc3, 0x79, 0xa0};
    append_word(out, 32);
    append_word(out, text.size());
    out.insert(out.end(), text.begin(), text.end());
    out.resize(out.size() + (32 - text.size() % 32) % 32, 0);
    return out;
}

/// A text, run in the empty world.
struct Text
{
    explicit Text(const std::string& text)
      : program(parse(text)), interp(program)
    {
        for (const auto& e : program.errors)
            MESSAGE(e);
        CHECK(program.errors.empty());
    }

    Effects call(Bytes data, Word value = 0)
    {
        CallContext c;
        c.caller = world.actors().front();
        c.origin = c.caller;
        c.value = value;
        c.calldata = std::move(data);
        return interp.run(state, c);
    }

    SeededWorld world{WorldConfig{.random = false}};
    State state{world, world.contract_address(), Bytes{0x00}};
    Program program;
    Interpreter interp;
};

template <typename T>
std::vector<T> events_of(const Effects& e)
{
    std::vector<T> out;
    for (const auto& ev : e.events)
        if (const auto* x = std::get_if<T>(&ev))
            out.push_back(*x);
    return out;
}
}  // namespace

TEST_CASE("text interp: the storage - mappings, packed values, arrays, fields")
{
    Text t(
        "def storage:\n"
        "  balanceOf is mapping of uint256 at storage 1\n"
        "  small is array of uint8 at storage 3\n"
        "  stor8 is uint112 at storage 8\n"
        "  stor8_112 is uint112 at storage 8 offset 112\n"
        "  pairs is array of struct of 2 slots at storage 9\n"
        "\n"
        "def set(uint256 v): # not payable\n"
        "  balanceOf[caller] = v\n"
        "  stor8_112 = v\n"
        "  small[33] = v\n"
        "  uint64(pairs[2].field_256) = v\n"
        "  pairs.length++\n"
        "\n"
        "def get(): # not payable\n"
        "  return balanceOf[caller], stor8_112, stor8, small[33], pairs[2].field_256, pairs.length\n");
    const auto caller = t.world.actors().front();
    const auto set = t.call(calldata("set(uint256)", {Word{0x1234567}}));
    CHECK(set.end.status == Status::stop);
    Bytes key = words({caller, 1});
    CHECK(set.storage_diff.at(keccak256(key)) == 0x1234567);
    CHECK(set.storage_diff.at(8) == Word{0x1234567} << 112);
    const Word data3 = keccak256(words({3}));
    CHECK(set.storage_diff.at(data3 + 1) == Word{0x67} << 8);  // 33 = 32 + 1: the slot 1, the byte 1
    const Word data9 = keccak256(words({9}));
    CHECK(set.storage_diff.at(data9 + 5) == 0x1234567);  // the element 2 of 2 slots, its slot 1
    CHECK(set.storage_diff.at(9) == 1);
    const auto get = t.call(calldata("get()", {}));
    CHECK(get.end.status == Status::return_);
    CHECK(get.end.data == words({0x1234567, 0x1234567, 0, 0x67, 0x1234567, 1}));
}

TEST_CASE("text interp: the ends - revert texts, Panic, require, assert, payable")
{
    Text t(
        "def a(uint256 x): # not payable\n"
        "  require x\n"
        "  assert x - 1\n"
        "  if x == 2:\n"
        "      revert with 'too much'\n"
        "  if x == 3:\n"
        "      revert with Panic(17)  # If an arithmetic operation results in underflow\n"
        "  if x == 4:\n"
        "      revert with 0x12345678, x\n"
        "  return 'ok'\n"
        "\n"
        "def b(): # not payable (invalid)\n"
        "  stop\n");
    CHECK(t.call(calldata("a(uint256)", {0})).end.status == Status::revert);
    CHECK(t.call(calldata("a(uint256)", {0})).end.data.empty());
    CHECK(t.call(calldata("a(uint256)", {1})).end.status == Status::invalid);
    CHECK(t.call(calldata("a(uint256)", {2})).end.data == abi_error("too much"));
    Bytes panic{0x4e, 0x48, 0x7b, 0x71};
    append_word(panic, 17);
    CHECK(t.call(calldata("a(uint256)", {3})).end.data == panic);
    Bytes custom{0x12, 0x34, 0x56, 0x78};
    append_word(custom, 4);
    CHECK(t.call(calldata("a(uint256)", {4})).end.data == custom);
    // return 'text': ABI-encoded
    const Bytes ok = abi_error("ok");
    CHECK(t.call(calldata("a(uint256)", {5})).end.data == Bytes(ok.begin() + 4, ok.end()));
    // not payable: no data when sent ether, an invalid opcode for old compilers
    const auto sent = t.call(calldata("a(uint256)", {5}), 1);
    CHECK(sent.end.status == Status::revert);
    CHECK(sent.end.data.empty());
    CHECK(t.call(calldata("b()", {}), 1).end.status == Status::invalid);
    CHECK(t.call(calldata("b()", {}), 0).end.status == Status::stop);
}

TEST_CASE("text interp: loops, labels, python's and/or")
{
    Text t(
        "def sum(uint256 n): # not payable\n"
        "  s = 0\n"
        "  idx = 0\n"
        "  while idx < n:\n"
        "      idx = idx + 1\n"
        "      if idx == 3:\n"
        "          continue\n"
        "      if idx > 5:\n"
        "          break\n"
        "      s = s + idx\n"
        "      continue\n"
        "  t = 0\n"
        "  loop1: while t < 2:\n"
        "      t = t + 1\n"
        "      u = 0\n"
        "      while u < 10:\n"
        "          u = u + 1\n"
        "          continue loop1\n"
        "  return s, t, 0 and n, n or 7, 5 and n\n");
    // 1 + 2 + 4 + 5
    CHECK(t.call(calldata("sum(uint256)", {10})).end.data == words({12, 2, 0, 10, 10}));
    CHECK(t.call(calldata("sum(uint256)", {0})).end.data == words({0, 2, 0, 7, 0}));
}

TEST_CASE("text interp: memory, data, Bytes, Array, sha3")
{
    Text t(
        "def m(uint256 x): # not payable\n"
        "  mem[64] = 128\n"
        "  mem[128 len 4] = Bytes(4, 0x12345678)\n"
        "  mem[132 len 36] = Bytes(4, 0xa9059cbb), x\n"
        "  if x == 1:\n"
        "      return memory\n"
        "        from 128\n"
        "         len 40\n"
        "  if x == 2:\n"
        "      return Array(len=2, data=7, 8)\n"
        "  if x == 3:\n"
        "      return sha3(Bytes(2, 0x1901), x), mem[128 len 4] + 0, mem[mem[64] + 4]\n"
        "  return Bytes(3, 0x616263), 'de', concat(Bytes(1, 0x66), Bytes(1, 0x67))\n");
    Bytes mem{0x12, 0x34, 0x56, 0x78, 0xa9, 0x05, 0x9c, 0xbb};
    append_word(mem, 1);
    CHECK(t.call(calldata("m(uint256)", {1})).end.data == mem);
    CHECK(t.call(calldata("m(uint256)", {2})).end.data == words({32, 2, 7, 8}));
    Bytes h{0x19, 0x01};
    append_word(h, 3);
    // mem[128 len 4] as a word: its 4 bytes; mem[mem[64] + 4]: 0xa9059cbb then x
    const auto three = t.call(calldata("m(uint256)", {3})).end.data;
    CHECK(three == words({keccak256(h), 0x12345678,
                          word("0xa9059cbb00000000000000000000000000000000000000000000000000000000")}));
    CHECK(t.call(calldata("m(uint256)", {4})).end.data == Bytes{'a', 'b', 'c', 'd', 'e', 'f', 'g'});
}

TEST_CASE("text interp: logs, external calls, precompiles, creations")
{
    Text t(
        "def l(address to, uint256 v) payable: \n"
        "  log Transfer(\n"
        "        address indexed from=caller,\n"
        "        address indexed to=address(to),\n"
        "        uint256 value=v)\n"
        "  log 0xabcd: v, indexed 7\n"
        "  log v\n"
        "  call to.transfer(address to, uint256 amount) with:\n"
        "     value 3 wei\n"
        "       gas gas_remaining\n"
        "      args caller, v\n"
        "  require ext_call.success\n"
        "  h = sha256hash(Bytes(3, 0x616263)) # precompiled\n"
        "  require sha256hash.result\n"
        "  create2 contract with 0 wei\n"
        "                  salt: 5\n"
        "                  code: Bytes(1, 0)\n"
        "  return h, return_data.size, create2.new_address\n");
    const auto caller = t.world.actors().front();
    const auto to = word("0x1111111111111111111111111111111111111111");
    const auto e = t.call(calldata("l(address,uint256)", {to, 9}), 10);
    INFO(to_string(e));
    REQUIRE(e.end.status == Status::return_);
    const auto logs = events_of<Log>(e);
    REQUIRE(logs.size() == 3);
    CHECK(logs[0].topics == std::vector<Word>{word("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"),
                                caller, to});
    CHECK(logs[0].data == words({9}));
    CHECK(logs[1].topics == std::vector<Word>{0xabcd, 7});
    CHECK(logs[2].topics.empty());
    CHECK(logs[2].data == words({9}));
    const auto calls = events_of<ExternalCall>(e);
    REQUIRE(calls.size() == 2);
    CHECK(calls[0].target == to);
    CHECK(calls[0].value == 3);
    Bytes input{0xa9, 0x05, 0x9c, 0xbb};
    append_word(input, caller);
    append_word(input, 9);
    CHECK(calls[0].input == input);
    CHECK(calls[1].precompile);
    CHECK(calls[1].target == 2);
    const auto creations = events_of<Creation>(e);
    REQUIRE(creations.size() == 1);
    CHECK(creations[0].salt == Word{5});
    CHECK(e.end.data == words({word("0xba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"), 0,
                               creations[0].address}));
}

TEST_CASE("text interp: SafeMath, internal functions, constants, the fallback")
{
    Text t(
        "const name = 'Uniswap V2'\n"
        "\n"
        "def SafeMath:\n"
        "  def sub(a, b, errorMessage):\n"
        "      if b > a:\n"
        "          revert with errorMessage\n"
        "      return a - b\n"
        "  def add(a, b):  # solidity >= 0.8\n"
        "      if a > -b - 1:\n"
        "          revert with Panic(17)  # If an arithmetic operation results in underflow\n"
        "      return a + b\n"
        "\n"
        "def s(uint256 x): # not payable\n"
        "  _1 = internal_0x10(x % 8, 2)\n"
        "  return SafeMath.sub(x, 5, 'too low'), SafeMath.add(x, 1), _1\n"
        "\n"
        "def _fallback(?) payable: # default function\n"
        "  return calldata.size\n"
        "\n"
        "#\n"
        "#  Internal functions\n"
        "#\n"
        "\n"
        "def internal_0x10(_param1, _param2): # recursive, a call takes 4 of the 1024 words of the stack\n"
        "  if _param1 <= 1:\n"
        "      return _param2\n"
        "  _3 = internal_0x10(_param1 - 1, _param2 * 2)\n"
        "  return _3\n");
    CHECK(t.call(calldata("s(uint256)", {7})).end.data == words({2, 8, 128}));
    CHECK(t.call(calldata("s(uint256)", {3})).end.data == abi_error("too low"));
    Bytes panic{0x4e, 0x48, 0x7b, 0x71};
    append_word(panic, 17);
    CHECK(t.call(calldata("s(uint256)", {~Word{0}})).end.data == panic);
    const Bytes name = abi_error("Uniswap V2");
    CHECK(t.call(calldata("name()", {})).end.data == Bytes(name.begin() + 4, name.end()));
    CHECK(t.call(calldata("name()", {}), 1).end.status == Status::revert);
    CHECK(t.call(Bytes{1, 2}).end.data == words({2}));
    CHECK(t.call(calldata("nothing()", {5})).end.data == words({36}));
}

TEST_CASE("text interp: what can't be run precisely is unsupported")
{
    Text t(
        "def u(uint256 x): # not payable\n"
        "  if x == 1:\n"
        "      return msize\n"
        "  if x == 2:\n"
        "      ...  # Decompilation aborted, sorry: (\"decompilation didn't finish\",)\n"
        "  return y\n");
    CHECK(t.call(calldata("u(uint256)", {1})).end.status == Status::unsupported);
    CHECK(t.call(calldata("u(uint256)", {2})).end.status == Status::unsupported);
    CHECK(t.call(calldata("u(uint256)", {3})).end.status == Status::unsupported);
    const auto& u = t.interp.unsupported();
    CHECK(u[static_cast<std::size_t>(Unsupported::msize)] == 1);
    CHECK(u[static_cast<std::size_t>(Unsupported::aborted)] == 1);
    CHECK(u[static_cast<std::size_t>(Unsupported::unset_variable)] == 1);
}

TEST_CASE("text interp: the members of a struct param, the params' places")
{
    Text t(
        "def fill((uint256,address,uint256) order, uint256 x): # not payable\n"
        "  return order.amount, order.maker, x\n"
        "\n"
        "def unknown12345678(uint256 _param1, uint256 _param2): # not payable\n"
        "  return _param1, _param2\n"
        "\n"
        "def _fallback(?) payable: # default function\n"
        "  return _param2\n");
    const auto fill = calldata("fill((uint256,address,uint256),uint256)", {1, 2, 3, 4});
    // the members' names are the ABI's: unsupported without them
    CHECK(t.call(fill).end.status == Status::unsupported);
    t.interp.set_param_names([](std::uint32_t) -> std::optional<std::vector<NameTree>> {
        return std::vector<NameTree>{{"order", {{"salt", {}}, {"maker", {}}, {"amount", {}}}}, {"x", {}}};
    });
    CHECK(t.call(fill).end.data == words({3, 2, 4}));

    // which functions' params the text doesn't place
    const auto& fs = t.program.functions;
    REQUIRE(fs.size() == 3);
    CHECK(!fs[0].places_unknown);
    CHECK(fs[1].places_unknown);
    CHECK(fs[2].places_unknown);
    CHECK(fs[2].params.size() == 2);  // _param1, _param2: those it reads
    CHECK(!fs[2].params[1].typed);

    // an unknown function's params: the first words, unless placed by side
    // information
    Bytes unknown{0x12, 0x34, 0x56, 0x78};
    for (const Word w : {Word{5}, Word{6}, Word{7}, Word{8}})
        append_word(unknown, w);
    CHECK(t.interp.function_for(unknown) == 1u);
    CHECK(t.call(unknown).end.data == words({5, 6}));
    const ParamPlace places[] = {{68, {}}, {100, {}}};
    CHECK(!place_params(t.program, 0x12345678u, std::span(places).first(1)));  // not as many
    CHECK(!fs[1].placed);
    CHECK(place_params(t.program, 0x12345678u, places));
    CHECK(fs[1].placed);
    CHECK(t.call(unknown).end.data == words({7, 8}));
    // a known function's params are where its signature says
    CHECK(!place_params(t.program, selector_of("fill((uint256,address,uint256),uint256)"), places));

    // the fallback's _paramN: the words it reads
    Bytes other{1, 2, 3, 4};
    for (const Word w : {Word{5}, Word{6}, Word{7}})
        append_word(other, w);
    CHECK(t.interp.function_for(other) == 2u);
    CHECK(t.interp.function_for(Bytes{1, 2}) == 2u);
    CHECK(t.call(other).end.data == words({6}));
    const ParamPlace fallback[] = {{4, {}}, {68, {}}, {100, {}}};  // more than it reads: fine
    CHECK(place_params(t.program, std::nullopt, fallback));
    CHECK(t.call(other).end.data == words({7}));
}

TEST_CASE("text interp: side information - the types of the fallback's params")
{
    Text t(
        "def _fallback(?) payable: # default function\n"
        "  return _param1, _param2.length\n");
    Bytes cd{1, 2, 3, 4};
    for (const Word w : {Word{7}, Word{0x40}, Word{3}})  // _param2: its offset 0x40, its length 3
        append_word(cd, w);
    // _param2 a word: it has no length
    CHECK(t.call(cd).end.status == Status::unsupported);
    // the side information's lines (text_check --params), the types read
    // as a signature's
    const auto side = parse_side_info("0x12345678 68 100:uint256\n_fallback 4:uint256 36:array\n");
    REQUIRE(side);
    REQUIRE(side->size() == 2);
    CHECK((*side)[0].selector == 0x12345678u);
    CHECK((*side)[0].places.size() == 2);
    CHECK((*side)[0].places[0].offset == 68);
    CHECK((*side)[0].places[0].type.empty());
    CHECK((*side)[0].places[1].type == "uint256");
    CHECK(!(*side)[1].selector);
    CHECK((*side)[1].places[1].offset == 36);
    CHECK((*side)[1].places[1].type == "array");
    CHECK(!parse_side_info("0x1234 4:\n"));
    CHECK(!parse_side_info("_fallback 4"));  // the line's end
    std::vector<ParamPlace> places;
    for (const auto& p : (*side)[1].places)
        places.push_back({p.offset, parse_type(p.type)});
    CHECK(place_params(t.program, std::nullopt, places));
    CHECK(t.call(cd).end.data == words({7, 3}));
}

TEST_CASE("text parser: a param's type alone")
{
    const auto word = parse_type("uint256");
    REQUIRE(word);
    CHECK(!word->dynamic);
    CHECK(word->words == 1);
    const auto array = parse_type("array");
    REQUIRE(array);
    CHECK(array->dynamic);
    CHECK(array->has_length);
    CHECK(array->is_array);
    const auto tuples = parse_type("(uint256,bytes)[]");
    REQUIRE(tuples);
    CHECK(tuples->dynamic);
    CHECK(tuples->is_array);
    CHECK(tuples->elem_dynamic);
    const auto fixed = parse_type("(uint256,address)[3]");
    REQUIRE(fixed);
    CHECK(!fixed->dynamic);
    CHECK(fixed->words == 6);
    CHECK(fixed->canonical == "(uint256,address)[3]");
    CHECK(!parse_type("tuple"));  // the JSON's word for a tuple: no type of a signature
    CHECK(!parse_type("uint256 x"));
    CHECK(!parse_type(""));
    CHECK(!parse_type("uint256) + (1"));
}
