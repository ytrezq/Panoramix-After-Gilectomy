// lot 10: the printer (python prettify / pretty_line / pprint_logic, as the
// asm prints them), the escapes, the folder.
#include <doctest/doctest.h>

#include <optional>
#include <string>

#include "analysis/safemath.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "output/output.hpp"
#include "output/print.hpp"
#include "storage/storage.hpp"

using namespace pan;
using namespace pan::output;

namespace {

struct Fixture {
    Budget budget{Budget::Limits{}};
    std::unique_ptr<Context> ctx;
    std::optional<ContextScope> scope;
    Fixture()
    {
        init();
        budget.attach_thread();
        ctx = Context::create(budget);
        scope.emplace(*ctx);
    }
    ~Fixture()
    {
        scope.reset();
        ctx.reset();
        budget.detach_thread();
    }
};

std::string E(std::string_view s) { return print_exp(V(s)); }
// a trace's lines, as a function's body prints them
std::string L(std::string_view s) { return print_trace(V(s)); }

}  // namespace

TEST_CASE("output: numbers")
{
    Fixture f;
    CHECK(E("0") == "0");
    CHECK(E("32") == "32");
    CHECK(E("1000000000000000000") == "10**18");
    CHECK(E("500000000000000000") == "5 * 10**17");
    CHECK(E("10000000") == "10 * 10**6");
    CHECK(E("86400") == "24 * 3600");
    CHECK(E("172800") == "2 * 24 * 3600");
    CHECK(E("18000") == "5 * 3600");
    CHECK(E("-1") == "-1");
    CHECK(E("0xffffffffffffffffffffffffffffffffffffffff") == "0xffffffffffffffffffffffffffffffffffffffff");
    // below 8**30 as decimal, past it hex
    CHECK(E("1237940039285380274899124223") == "1237940039285380274899124223");
    CHECK(E("1237940039285380274899124225") == "0x40000000000000000000001");
}

TEST_CASE("output: expressions")
{
    Fixture f;
    CHECK(E("(add 1 (calldataload 4))") == "cd[4] + 1");
    CHECK(E("(add -4 calldatasize)") == "calldata.size - 4");
    CHECK(E("(add -4 calldatasize (mul -1 (calldataload 4)))") == "calldata.size - cd[4] - 4");
    CHECK(E("(mask_shl 160 0 0 (calldataload 4))") == "address(cd[4])");
    CHECK(E("(mask_shl 8 0 0 tmp1)") == "uint8(_1)");
    CHECK(E("(mask_shl 160 0 0 caller)") == "caller");
    CHECK(E("(mask_shl 251 5 0 (add 31 tmp1))") == "ceil32(_1)");
    CHECK(E("(mask_shl 251 5 0 tmp1)") == "floor32(_1)");
    CHECK(E("(mask_shl 32 224 0 (calldataload 0))") == "call.func_hash");
    CHECK(E("(mask_shl 8 160 -160 tmp1)") == "uint8(_1 >> 160)");
    CHECK(E("(mask_shl 4 0 0 tmp1)") == "_1 % 16");
    CHECK(E("(mask_shl 96 160 0 tmp1)") == "Mask(96, 160, _1)");
    CHECK(E("(mul 96 (mask_shl 8 0 0 tmp1))") == "96 * uint8(_1)");
    CHECK(E("(mul -1 tmp1)") == "-_1");
    CHECK(E("(mul 18446744073709551616 tmp1)") == "_1 << 64");
    CHECK(E("(iszero (eq caller (storage 160 0 0)))") == "address(stor[0]) != caller");
    CHECK(E("(iszero tmp1)") == "not _1");
    CHECK(E("(lt tmp1 (add 1 tmp2))") == "_1 < _2 + 1");
    CHECK(E("(sgt tmp1 tmp2)") == "_1 >′ _2");
    CHECK(E("(and (lt tmp1 tmp2) (eq tmp1 3))") == "_1 < _2 and _1 == 3");
    CHECK(E("(or tmp1 tmp2)") == "_1 | _2");
    CHECK(E("(exp 256 tmp1)") == "256**_1");
    CHECK(E("(div (add tmp1 tmp2) 2)") == "(_1 + _2) / 2");
    CHECK(E("(sub tmp1 (sub tmp2 tmp3))") == "_1 - (_2 - _3)");
    CHECK(E("(shl 3 tmp1)") == "_1 << 3");
    CHECK(E("(sar tmp2 tmp1)") == "_1 >>′ _2");
    CHECK(E("(not tmp1)") == "~_1");
    CHECK(E("(bool tmp1)") == "bool(_1)");
    CHECK(E("(bool (lt tmp1 2))") == "_1 < 2");
    CHECK(E("(signextend 0 tmp1)") == "int8(_1)");
    CHECK(E("(max tmp1 tmp2)") == "max(_1, _2)");
    CHECK(E("(balance address)") == "eth.balance(this.address)");
    CHECK(E("(tload 5)") == "transient[5]");
    CHECK(E("(extcodesize caller)") == "ext_code.size(caller)");
    CHECK(E("(mem (range 64 32))") == "mem[64]");
    CHECK(E("(mem (range 64 4))") == "mem[64 len 4]");
    CHECK(E("(calldata_bytes 4 32)") == "call.data[4]");
    CHECK(E("(calldata_bytes 4 tmp1)") == "call.data[4 len _1]");
    CHECK(E("(code_bytes 4 32)") == "code.data[4 len 32]");
    CHECK(E("(returndata_bytes 1 0 32)") == "ext_call.return_data[0]");
    CHECK(E("(storage 256 0 3)") == "stor[3]");
    CHECK(E("(storage 160 0 3)") == "address(stor[3])");
    CHECK(E("(storage 8 160 3)") == "uint8(stor[3].field_160)");
    CHECK(E("(storage 96 160 3)") == "stor[3].field_160");
    CHECK(E("(sha3 (sized 32 tmp1) (sized 32 4))") == "sha3(_1, 4)");
    CHECK(E("(sized 20 (mask_shl 160 0 0 tmp1))") == "Bytes(20, address(_1))");
    CHECK(E("(sized 4 0x12345678)") == "Bytes(4, 0x12345678)");
    CHECK(E("(sized 3 0x616263)") == "'abc'");
    CHECK(E("(land tmp1 tmp2)") == "_1 and _2");
    CHECK(E("(lor (iszero tmp1) tmp2)") == "not _1 or _2");
    // the top of the words as python's trace has them (simplify_exp's
    // to_real_int), but in unsigned comparisons
    const std::string max = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    CHECK(E(max) == "-1");
    CHECK(E("(eq tmp1 " + max + ")") == "_1 == -1");
    CHECK(E("(iszero (eq tmp1 " + max + "))") == "_1 != -1");
    CHECK(E("(lt tmp1 " + max + ")") == "_1 < " + max);
    CHECK(E("(iszero (lt tmp1 " + max + "))") == "_1 >= " + max);
    CHECK(E("(gt tmp1 (div " + max + " tmp2))") == "_1 > -1 / _2");
    CHECK(E("(add 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc calldatasize)") ==
          "calldata.size - 4");
    CHECK(E("(mul " + max + " tmp1)") == "-_1");
    CHECK(E("(sized 32 " + max + ")") == "-1");
    CHECK(E("0x8000000000000000000000000000000000000000000000000000000000000000") ==
          "0x8000000000000000000000000000000000000000000000000000000000000000");
    CHECK(E("loop0") == "idx");
    CHECK(E("loop1") == "s");
    CHECK(E("_msize") == "_msize");
    CHECK(E("prec_1_1") == "signer");
    CHECK(E("prec_1_2") == "signer2");
}

TEST_CASE("output: lines")
{
    Fixture f;
    CHECK(L("{(if (lt (add -4 calldatasize) 32) {(revert None)} {}) (return (sized 32 1))}") ==
          "  require calldata.size - 4 >= 32\n  return 1\n");
    CHECK(L("{(revert (data (sized 4 0x08c379a0) (sized 32 32) (sized 32 22) "
            "(sized 32 0x4f6e6c792063616c6c61626c65206279206f776e657200000000000000000000)))}") ==
          "  revert with 'Only callable by owner'\n");
    CHECK(L("{(revert (data (sized 4 0x4e487b71) (sized 32 17)))}") ==
          "  revert with Panic(17)  # If an arithmetic operation results in underflow or overflow outside of an "
          "unchecked { ... } block.\n");
    CHECK(L("{(revert None)}") == "  revert\n");
    CHECK(L("{(stop)}") == "  stop\n");  // (python pprint_ast: an empty body is stop)
    CHECK(L("{(setvar tmp3 (add 1 tmp2)) (stop)}") == "  _3 = _2 + 1\n");
    CHECK(L("{(setmem (range 64 32) 128)}") == "  mem[64] = 128\n");
    CHECK(L("{(setmem (range 64 4) (sized 4 2835717307))}") == "  mem[64 len 4] = 2835717307\n");
    CHECK(L("{(store 256 0 5 (add 1 (storage 256 0 5)))}") == "  stor[5]++\n");
    CHECK(L("{(store 160 0 5 caller)}") == "  address(stor[5]) = caller\n");
    CHECK(L("{(store 256 0 5 (add (storage 256 0 5) (mul -1 tmp1)))}") == "  stor[5] -= _1\n");
    CHECK(L("{(log1 None 0x1234)}") == "  log 0x0000000000000000000000000000000000000000000000000000000000001234:\n");
    CHECK(L("{(return (mem (range 128 tmp1)))}") == "  return memory\n    from 128\n     len _1\n");
    CHECK(L("{(invalid 1 0)}") == "  invalid\n");
    CHECK(L("{(undefined 1 7)}") == "  ...  # Decompilation aborted, sorry: (\"decompilation didn't finish\",)\n");
    CHECK(L("{(tstore 1 2)}") == "  transient[1] = 2\n");
    CHECK(L("{(staticcall 1 (gas 1) tmp1 (sized 4 0x06fdde03) None)}") ==
          "  static call _1.unknown06fdde03(?) with:\n          gas gas_remaining\n");
    CHECK(L("{(call 1 (gas 1) caller 5 None None)}") ==
          "  call caller with:\n     value 5 wei\n       gas gas_remaining\n");
    CHECK(L("{(precompiled 1 prec_1_1 1 (mem (range 0 128)))}") == "  signer = ecrecover(mem[0 len 128]) # precompiled\n");
    CHECK(L("{(internal 4660 [1 tmp2] [tmp5]) (leave [tmp5])}") == "  _5 = internal_0x1234(1, _2)\n  return _5\n");
    // python's other_2: `if a == b: return a == b` returns True
    CHECK(L("{(if (eq tmp1 5) {(return (sized 32 (eq tmp1 5)))} {}) (return (sized 32 0))}") ==
          "  if _1 == 5:\n      return True\n  return 0\n");
}

TEST_CASE("output: loops")
{
    Fixture f;
    // a while: its first setvars, its body with the continue's
    CHECK(L("{(while (lt loop0 10) {(setmem (range loop0 32) 0) (continue loopid1 {(setvar loop0 (add 32 loop0))})} "
            "loopid1 {(setvar loop0 0)})}") ==
          "  idx = 0\n  while idx < 10:\n      mem[idx] = 0\n      idx = idx + 32\n      continue\n");
    // simultaneous assignments: a copy for a swap
    CHECK(L("{(while 1 {(continue loopid1 {(setvar loop0 loop1) (setvar loop1 loop0)})} loopid1 {})}") ==
          "  while True:\n      _old = idx\n      idx = s\n      s = _old\n      continue\n");
    // a body that ends without a continue leaves the loop: a break
    CHECK(L("{(while (lt loop0 10) {(setvar loop0 (add 1 loop0))} loopid1 {(setvar loop0 0)})}") ==
          "  idx = 0\n  while idx < 10:\n      idx = idx + 1\n      break\n");
}

TEST_CASE("output: escapes of the database's text")
{
    using pan::output::detail::db_text;
    CHECK(db_text("transfer") == "transfer");
    CHECK(db_text("a\x1b[31mb") == "a\\x1b[31mb");
    CHECK(db_text("a\nb") == "a\\x0ab");
    CHECK(db_text("del\x7f") == "del\\x7f");
    CHECK(db_text("caf\xc3\xa9") == "caf\xc3\xa9");          // é: text
    CHECK(db_text("x\xc2\x85y") == "x\\xc2\\x85y");          // NEL (C1)
    CHECK(db_text("x\xe2\x80\xaey") == "x\\xe2\\x80\\xaey");  // RLO
    CHECK(db_text("x\xe2\x81\xa6y") == "x\\xe2\\x81\\xa6y");  // LRI
    CHECK(db_text("x\xd8\x9cy") == "x\\xd8\\x9cy");          // ALM
    CHECK(db_text("x\xffy") == "x\\xffy");                   // no UTF-8
    CHECK(db_text("x\xe2\x80") == "x\\xe2\\x80");            // cut short
    CHECK(db_text("\xf0\x9f\x98\x80") == "\xf0\x9f\x98\x80");  // an emoji: text
    using pan::output::detail::pretty_text;
    const u8 abc[] = {'a', 'b', 'c'};
    CHECK(pretty_text(abc) == std::optional<std::string>("'abc'"));
    const u8 q[] = {'a', '\'', '\n', 'b'};
    CHECK(pretty_text(q) == std::optional<std::string>("'a\\'\\nb'"));
    const u8 bin[] = {0, 'a', 'b'};
    CHECK(!pretty_text(bin));
    const u8 punct[] = {',', ' '};
    CHECK(!pretty_text(punct));
    CHECK(pretty_text(punct, true) == std::optional<std::string>("', '"));
}

namespace {

// a layout of each kind of variable (lot 9's StorageLayout), no getter: the
// names are python's defaults
StorageLayout test_layout()
{
    using K = StorageType::Kind;
    const auto type = [](K kind, u16 width = 256, u32 elem = 0, std::optional<u64> slots = std::nullopt,
                         std::optional<u64> length = std::nullopt) {
        StorageType t;
        t.kind = kind;
        t.width = width;
        t.elem = elem;
        t.slots = slots;
        t.length = length;
        return t;
    };
    const auto var = [](const Word256& slot, u32 type, u16 off = 0) {
        StorageVar v;
        v.slot = slot;
        v.off = off;
        v.type = type;
        return v;
    };
    StorageLayout l;
    l.types = {
        type(K::Value),                    // 0 uint256
        type(K::Mapping, 256, 0),          // 1 mapping of uint256
        type(K::Bytes),                    // 2 bytes
        type(K::Value, 8),                 // 3 uint8
        type(K::Mapping, 256, 1),          // 4 mapping of mapping of uint256
        type(K::Struct, 256, 0, 2),        // 5 struct of 2 slots
        type(K::Fixed, 256, 3, {}, 3),     // 6 uint8[3]
        type(K::Array, 256, 0),            // 7 array of uint256
        type(K::Value, 160),               // 8 address
    };
    const Word256 big = Word256::from_int(EvmInt(i64(0x1234)) * EvmInt::pow2(200));
    l.vars = {
        var(Word256::of(0), 2),                     // stor0: bytes
        var(Word256::of(3), 1),                     // stor3: mapping
        var(Word256::of(4), 4),                     // stor4: mapping of mapping
        var(Word256::of(5), 8),                     // stor5: address
        var(Word256::of(5), 3, 160),                // stor5_160: uint8
        var(Word256::of(9), 6),                     // stor9: uint8[3]
        var(Word256::of(10), 5),                    // stor10: struct
        var(Word256::of(11), 7),                    // stor11: array
        var(big, 0),                                // stor1234
        var(pan::add(big, Word256::of(1)), 0),      // stor1234 taken: stor1234_12340000
    };
    return l;
}

}  // namespace

TEST_CASE("output: the storage's forms and def storage (lot 9)")
{
    Fixture f;
    const StorageLayout l = test_layout();
    const TraceContext c{nullptr, nullptr, false, &l, nullptr};
    auto e = [&](std::string_view s) { return print_exp(V(s), c); };
    auto t = [&](std::string_view s) { return print_trace(V(s), c); };
    CHECK(e("(st 256 (si (sv stor1) caller) 256)") == "stor3[caller]");
    CHECK(e("(st 256 (si (si (sv stor2) caller) (calldataload 4)) 256)") == "stor4[caller][cd[4]]");
    CHECK(e("(st 160 (sv stor3) 160)") == "stor5");
    CHECK(e("(st 160 (sv stor3) 256)") == "address(stor5)");
    CHECK(e("(st 8 (sv stor4) 8)") == "stor5_160");
    CHECK(e("(st 8 (sv stor4) None)") == "stor5_160");
    CHECK(e("(st 256 (sbl (sv stor0)) 256)") == "stor0.length");
    CHECK(e("(st 256 (sl (sv stor7)) 256)") == "stor11.length");
    CHECK(e("(sall (sv stor0))") == "stor0[all]");
    CHECK(e("(st 256 (sr 7) 256)") == "stor[7]");
    CHECK(e("(st 8 (sf (sr 7) 8) 8)") == "stor[7].field_8");
    CHECK(e("(st 8 (si (sv stor5) 2) 8)") == "stor9[2]");
    CHECK(e("(st 256 (sv stor8) 256)") == "stor1234");
    CHECK(e("(st 256 (sv stor9) 256)") == "stor1234_12340000");
    // under a mask, shifted by its offset (python's other_2, prettify's st rule)
    CHECK(e("(mask_shl 8 8 -8 (st 16 (sv stor4) 16))") == "stor5_160 / 256");
    CHECK(e("(mask_shl 7 1 -1 (st 8 (sv stor4) 8))") == "stor5_160 / 2");
    CHECK(e("(mask_shl 8 16 -16 (st 24 (sv stor3) 24))") == "stor5 >> 16");
    // the writes
    CHECK(t("{(set (st 256 (si (sv stor1) caller) 256) (add callvalue (st 256 (si (sv stor1) caller) 256)))}") ==
          "  stor3[caller] += call.value\n");
    CHECK(t("{(set (st 8 (sv stor4) 8) (add 1 (st 8 (sv stor4) 8)))}") == "  stor5_160++\n");
    CHECK(t("{(set (st 160 (sv stor3) 160) caller)}") == "  stor5 = caller\n");
    CHECK(t("{(set (st 256 (sr 7) 256) (add (st 256 (sr 7) 256) (mul -1 tmp1)))}") == "  stor[7] -= _1\n");
    // def storage: a line each, by slot
    pan::output::detail::Out o(false);
    pan::output::detail::storage_block(o, pan::output::detail::contract_names(&l, nullptr, nullptr));
    CHECK(o.s == "def storage:\n"
                 "  stor0 is bytes at storage 0\n"
                 "  stor3 is mapping of uint256 at storage 3\n"
                 "  stor4 is mapping of mapping of uint256 at storage 4\n"
                 "  stor5 is address at storage 5\n"
                 "  stor5_160 is uint8 at storage 5 offset 160\n"
                 "  stor9 is uint8[3] at storage 9\n"
                 "  stor10 is struct of 2 slots at storage 10\n"
                 "  stor11 is array of uint256 at storage 11\n"
                 "  stor1234 is uint256 at storage 0x123400000000000000000000000000000000000000000000000000\n"
                 "  stor1234_12340000 is uint256 at storage 0x123400000000000000000000000000000000000000000000000001\n"
                 "\n");
    // the params named as the storage's variables are not: python's _name
    // (the loop variables either)
    StorageLayout s = l;
    s.vars.resize(1);
    s.vars[0].slot = Word256::of(1);  // stor1
    const TraceContext cs{nullptr, nullptr, false, &s, nullptr};
    CHECK(print_exp(V("(st 256 (sbl (sv stor0)) 256)"), cs) == "stor1.length");
}

namespace {

// a SafeMath of each kind of check (lot 8's SafeMathTable)
SafeMathTable test_safemath()
{
    using A = SafeMathTable::Arith;
    using F = SafeMathTable::Fail;
    const auto check = [](std::string_view cond, F kind, std::string_view fail, u32 panic = 0,
                          std::optional<u32> message = std::nullopt) {
        SafeMathTable::Check c;
        c.cond = V(cond);
        c.kind = kind;
        c.panic = panic;
        if (!fail.empty())
            c.fail = V(fail);
        c.message = message;
        return c;
    };
    const auto fn = [](A op, u32 number, u32 params, u32 messages, std::string_view result) {
        SafeMathTable::Fn f;
        f.op = op;
        f.number = number;
        f.params = params;
        f.messages = messages;
        f.result = V(result);
        return f;
    };
    SafeMathTable t;
    t.fns.push_back(fn(A::Add, 1, 2, 0, "(add sm0 sm1)"));
    t.fns.back().checks.push_back(check("(lt (add sm0 sm1) sm0)", F::Error,
                                        "(revert (data (sized 4 0x08c379a0) 32 27 "
                                        "0x536166654d6174683a206164646974696f6e206f766572666c6f770000000000))"));
    t.fns.push_back(fn(A::Sub, 1, 2, 1, "(add sm0 (mul -1 sm1))"));
    t.fns.back().checks.push_back(check("(gt sm1 sm0)", F::Error, "", 0, 0));
    t.fns.push_back(fn(A::Sub, 2, 2, 0, "(add sm0 (mul -1 sm1))"));
    t.fns.back().checks.push_back(
        check("(gt (add sm0 (mul -1 sm1)) sm0)", F::Panic, "(revert (data (sized 4 0x4e487b71) 17))", 0x11));
    t.fns.push_back(fn(A::Div, 1, 2, 0, "(div sm0 sm1)"));
    t.fns.back().checks.push_back(check("(iszero sm1)", F::Revert, "(revert None)"));
    t.fns.push_back(fn(A::Inc, 1, 1, 0, "(add 1 sm0)"));
    t.fns.back().checks.push_back(check("(iszero sm0)", F::Invalid, "(invalid 2 7)"));
    return t;
}

}  // namespace

TEST_CASE("output: SafeMath's calls and def SafeMath (lot 8)")
{
    Fixture f;
    const SafeMathTable sm = test_safemath();
    const TraceContext c{nullptr, nullptr, false, nullptr, &sm};
    CHECK(print_exp(V("(safemath 0 tmp1 tmp2)"), c) == "SafeMath.add(_1, _2)");
    CHECK(print_exp(V("(safemath 1 tmp1 (mul 2 tmp2) (data (sized 4 0x08c379a0) 32 27 "
                      "0x536166654d6174683a206164646974696f6e206f766572666c6f770000000000))"),
                    c) == "SafeMath.sub(_1, 2 * _2, 'SafeMath: addition overflow')");
    CHECK(print_exp(V("(safemath 4 tmp1)"), c) == "SafeMath.inc(_1)");
    CHECK(print_exp(V("(add 1 (safemath 2 tmp1 tmp2))"), c) == "SafeMath.sub2(_1, _2) + 1");
    pan::output::detail::Out o(false);
    pan::output::detail::safemath_block(o, pan::output::detail::contract_names(nullptr, &sm, nullptr), nullptr);
    CHECK(o.s == "def SafeMath:\n"
                 "  def add(a, b):\n"
                 "      if a + b < a:\n"
                 "          revert with 'SafeMath: addition overflow'\n"
                 "      return a + b\n"
                 "  def sub(a, b, errorMessage):\n"
                 "      if b > a:\n"
                 "          revert with errorMessage\n"
                 "      return a - b\n"
                 "  def sub2(a, b):  # solidity >= 0.8\n"
                 "      if a - b > a:\n"
                 "          revert with Panic(17)  # If an arithmetic operation results in underflow or overflow "
                 "outside of an unchecked { ... } block.\n"
                 "      return a - b\n"
                 "  def div(a, b):\n"
                 "      require b\n"
                 "      return a / b\n"
                 "  def inc(a):\n"
                 "      assert a\n"
                 "      return a + 1\n"
                 "\n");
}

TEST_CASE("output: python's view in --explain and --verbose")
{
    Fixture f;
    // --explain: the traces before the traits and the storage - a storage
    // read is python's tuple
    std::string ex;
    explain_trace(ex, "Initial decompiled trace", V("{(return (sized 32 (storage 160 0 (add 1 tmp2))))}"), {});
    CHECK(ex == "\n Initial decompiled trace: \n\n  return ('storage', 160, 0, ('add', 1, ('var', '_2')))\n\n\n");
    // the final text: the asm's form of the analysis' failure
    CHECK(L("{(return (sized 32 (storage 160 0 (add 1 tmp2))))}") == "  return address(stor[_2 + 1])\n");
    // --verbose: the VM's stacks as python printed them in its VM
    CHECK(L("{(asm 7 0x54 None [(storage 256 0 7) 5]) (stop)}") ==
          "  #        [('storage', 256, 0, 7), 5]\n  # \n  # [7] sload\n");
    // --explain's function traits: python's str() of its return lines
    FunctionInfo fn;
    fn.trace = V("{(return (sized 32 5))}");
    fn.is_const = fn.read_only = fn.entry.nonpayable = true;
    std::string tr;
    explain_traits(tr, fn, TraceContext{&fn});
    CHECK(tr == "\n function traits: \n\n possible return values: [('return', ('bytes', 32, 5))]\n payable: False\n"
                " read_only: True\n const: ('return', ('bytes', 32, 5))\n\n");
    // --repr: python's pprint_repr, its IR's tuples
    std::string rp;
    pan::output::detail::repr_lines(
        rp, V("{(if (iszero callvalue) {(return (sized 32 (storage 160 0 7)))} {(revert None)})}"), 0);
    CHECK(rp == " [if, ('iszero', 'callvalue'), [\n   ('return', ('bytes', 32, ('storage', 160, 0, 7))), \n ],[\n"
                "   ('revert', None), \n ] \n");
}

TEST_CASE("output: make_ast's passes")
{
    Fixture f;
    auto ast_text = [](std::string_view trace, std::string_view entry = "{}") {
        FunctionInfo fn;
        fn.kind = FunctionInfo::Kind::Fallback;
        fn.trace = V(trace);
        fn.entry.entry_lines = V(entry);
        return print_trace(make_ast(fn), TraceContext{&fn});
    };
    // a call's result read after another call: a variable right after it
    CHECK(ast_text("{(staticcall 1 (gas 1) caller (sized 4 0x0dfe1681) None)"
                   " (staticcall 2 (gas 2) caller (sized 4 0xd21220a7) None)"
                   " (if (eq (returndata_bytes 1 0 32) (returndata_bytes 2 0 32)) {(revert None)}"
                   " {(return (sized 32 (returndata_bytes 1 0 32)))})}") ==
          "  static call caller.unknown0dfe1681(?) with:\n          gas gas_remaining\n"
          "  _1 = ext_call.return_data[0]\n"
          "  static call caller.unknownd21220a7(?) with:\n          gas gas_remaining\n"
          "  require _1 != ext_call.return_data[0]\n  return _1\n");
    // the entry's SETMEMs the body reads before it writes them
    CHECK(ast_text("{(log1 (mem (range (mem (range 64 32)) 32)) 4660)}", "{(setmem (range 64 32) 128)}") ==
          "  mem[64] = 128\n  log 0x0000000000000000000000000000000000000000000000000000000000001234: mem[mem[64]]\n");
    CHECK(ast_text("{(setmem (range 64 32) 160) (log1 (mem (range (mem (range 64 32)) 32)) 4660)}",
                   "{(setmem (range 64 32) 128)}") ==
          "  mem[64] = 160\n  log 0x0000000000000000000000000000000000000000000000000000000000001234: mem[mem[64]]\n");
    // an if of the same lines but for its calls' ids (and gas reads): its lines
    CHECK(ast_text("{(if (iszero tmp1) {(call 1 (gas 1) caller 5 None None) (stop)}"
                   " {(call 2 (gas 2) caller 5 None None) (stop)})}") ==
          "  call caller with:\n     value 5 wei\n       gas gas_remaining\n");
}

TEST_CASE("output: the folder")
{
    Fixture f;
    // nested checks: requires, one after the other
    const Value t = V("{(if (iszero tmp1) {(revert None)} {(if (lt tmp2 3) {(revert None)} {(return (sized 32 tmp2))})})}");
    CHECK(print_trace(fold(t)) == "  require _1\n  require _2 >= 3\n  return _2\n");
    // a branch that ends: no else
    const Value u = V("{(if tmp1 {(revert (sized 32 1))} {(setvar tmp3 2) (return (sized 32 tmp3))})}");
    CHECK(print_trace(fold(u)) == "  if _1:\n      revert with 1\n  _3 = 2\n  return _3\n");
    // the same end after both branches, once
    const Value w = V("{(if tmp1 {(setvar tmp3 1) (log0 None) (stop)} {(setvar tmp3 2) (log0 None) (stop)})}");
    CHECK(print_trace(fold(w)) == "  if _1:\n      _3 = 1\n  else:\n      _3 = 2\n  log\n");
    // an if whose branches join (merged): folded on its own
    const Value m = V("{(if tmp1 {(setvar tmp3 1)} {(setvar tmp3 2)}) (return (sized 32 tmp3))}");
    CHECK(print_trace(fold(m)) == "  if _1:\n      _3 = 1\n  else:\n      _3 = 2\n  return _3\n");
}
