// The parsers of the validation (AGENTS.md rule 2: Ragel machines, one per
// function): hex text to bytes, numbers, the function selectors of a runtime
// bytecode (read on its opcode bytes), evmrun's options.
#include "validate/scan.hpp"

#include <algorithm>

namespace validate
{
namespace
{
constexpr unsigned hex_value(unsigned char c) noexcept
{
    return c <= '9' ? c - '0' : (c | 0x20u) - 'a' + 10;
}
}  // namespace

%%{
  machine hex_text;
  alphtype unsigned char;

  action hi_digit { byte = static_cast<std::uint8_t>(hex_value(fc) << 4); }
  action lo_digit { out.push_back(static_cast<std::uint8_t>(byte | hex_value(fc))); }

  xdigit_ = [0-9a-fA-F];
  main := space* ('0' [xX])? (xdigit_ @hi_digit xdigit_ @lo_digit)* space*;
}%%

%% write data noerror noentry;

std::optional<Bytes> parse_hex(std::string_view text)
{
    Bytes out;
    out.reserve(text.size() / 2);
    std::uint8_t byte = 0;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(text.data());
    const auto* pe = p + text.size();
    %% write init;
    %% write exec;
    if (cs < hex_text_first_final)
        return std::nullopt;
    return out;
}

%%{
  machine number;
  alphtype unsigned char;

  action dec_digit {
      const unsigned d = fc - '0';
      if (value > (~Word{0} - d) / 10)
          overflow = true;
      value = value * 10 + d;
  }
  action hex_digit {
      if (value >> 252 != 0)
          overflow = true;
      value = (value << 4) | hex_value(fc);
  }

  main := [0-9]+ @dec_digit | '0' [xX] [0-9a-fA-F]+ @hex_digit;
}%%

%% write data noerror noentry;

std::optional<Word> parse_number(std::string_view text)
{
    Word value = 0;
    bool overflow = false;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(text.data());
    const auto* pe = p + text.size();
    %% write init;
    %% write exec;
    if (cs < number_first_final || overflow)
        return std::nullopt;
    return value;
}

%%{
  machine selectors;
  alphtype unsigned char;

  action sel_start { sel = 0; }
  action sel_byte { sel = (sel << 8) | fc; }
  action found { found.push_back(sel); }

  # the instructions: an opcode, its immediate's bytes
  push_n = 0x60 any | 0x61 any{2} | 0x62 any{3} | 0x63 any{4} | 0x64 any{5} | 0x65 any{6}
         | 0x66 any{7} | 0x67 any{8} | 0x68 any{9} | 0x69 any{10} | 0x6a any{11}
         | 0x6b any{12} | 0x6c any{13} | 0x6d any{14} | 0x6e any{15} | 0x6f any{16}
         | 0x70 any{17} | 0x71 any{18} | 0x72 any{19} | 0x73 any{20} | 0x74 any{21}
         | 0x75 any{22} | 0x76 any{23} | 0x77 any{24} | 0x78 any{25} | 0x79 any{26}
         | 0x7a any{27} | 0x7b any{28} | 0x7c any{29} | 0x7d any{30} | 0x7e any{31}
         | 0x7f any{32};
  insn = push_n | (0x00..0x5f | 0x80..0xff);

  # the dispatchers' comparisons of the selector with a function's, then the
  # jump to it (or past it):
  #   solc >= 0.5     DUP1 PUSH4 s EQ PUSH dest JUMPI
  #   solc 0.4        PUSH4 s DUP2 EQ PUSH dest JUMPI
  #   vyper           PUSH4 s DUP2 XOR PUSH dest JUMPI, PUSH4 s DUP2 EQ ISZERO ...
  #   vyper < 0.2     PUSH4 s PUSH1 0 MLOAD EQ ISZERO PUSH dest JUMPI
  push4_sel = 0x63 >sel_start (any @sel_byte){4};
  dup = 0x80..0x8f;
  cmp = 0x14 | 0x18;
  dest = 0x60 any | 0x61 any{2} | 0x62 any{3} | 0x63 any{4};
  compared = dup push4_sel cmp | push4_sel dup cmp | push4_sel cmp | push4_sel 0x60 0x00 0x51 cmp;
  selector = compared 0x15? dest 0x57 @found;

  main := (insn | selector)*;
}%%

%% write data noerror nofinal noentry;

std::vector<std::uint32_t> find_selectors(BytesView code)
{
    std::vector<std::uint32_t> found;
    std::uint32_t sel = 0;
    int cs;
    const auto* p = code.data();
    const auto* pe = p + code.size();
    %% write init;
    %% write exec;
    // in code order, once each
    std::vector<std::uint32_t> out;
    for (const auto s : found)
        if (std::ranges::find(out, s) == out.end())
            out.push_back(s);
    return out;
}

%%{
  machine evmrun_option;
  alphtype unsigned char;

  main := '--seed' @{ id = EvmrunOption::seed; }
        | '--empty' @{ id = EvmrunOption::empty; }
        | '--random' @{ id = EvmrunOption::random; }
        | '--per-selector' @{ id = EvmrunOption::per_selector; }
        | '--gas' @{ id = EvmrunOption::gas; }
        | '--caller' @{ id = EvmrunOption::caller; }
        | '--value' @{ id = EvmrunOption::value; }
        | '--selectors' @{ id = EvmrunOption::selectors; }
        | '--quiet' @{ id = EvmrunOption::quiet; }
        | '--corpus' @{ id = EvmrunOption::corpus; }
        | '--each' @{ id = EvmrunOption::each; }
        | '--compare' @{ id = EvmrunOption::compare; }
        | ('--help' | '-h') @{ id = EvmrunOption::help; };
}%%

%% write data noerror noentry;

EvmrunOption evmrun_option(std::string_view arg)
{
    auto id = EvmrunOption::none;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(arg.data());
    const auto* pe = p + arg.size();
    %% write init;
    %% write exec;
    return cs >= evmrun_option_first_final ? id : EvmrunOption::none;
}
}  // namespace validate
