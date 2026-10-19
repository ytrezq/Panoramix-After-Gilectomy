// lot 10: the printer (python prettify / pretty_line / pprint_logic, as the
// asm prints them), the escapes, the folder.
#include <doctest/doctest.h>

#include <optional>
#include <string>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "output/output.hpp"
#include "output/print.hpp"

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
