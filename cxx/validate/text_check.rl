// text_check's command line words (text_check.hpp): a Ragel machine.
#include "validate/text_check.hpp"

namespace validate::text
{
%%{
  machine check_word;
  alphtype unsigned char;

  known = '--seed' | '--empty' | '--random' | '--per-selector' | '--each' | '--verbose' | '--quiet'
        | '--corpus' | '--texts' | '--params' | '--call' | '--trace' | '--sigdb' | '-h' | '--help';
  main := ( 'parse' %{ w = CheckWord::parse; }
          | 'run' %{ w = CheckWord::run; }
          | '--seed' %{ w = CheckWord::seed; }
          | '--empty' %{ w = CheckWord::empty; }
          | '--random' %{ w = CheckWord::random; }
          | '--per-selector' %{ w = CheckWord::per_selector; }
          | '--each' %{ w = CheckWord::each; }
          | '--verbose' %{ w = CheckWord::verbose; }
          | '--quiet' %{ w = CheckWord::quiet; }
          | '--corpus' %{ w = CheckWord::corpus; }
          | '--texts' %{ w = CheckWord::texts; }
          | '--params' %{ w = CheckWord::params; }
          | '--call' %{ w = CheckWord::call; }
          | '--trace' %{ w = CheckWord::trace; }
          | '--sigdb' %{ w = CheckWord::sigdb; }
          | ( '-h' | '--help' ) %{ w = CheckWord::help; }
          | ( ( '-' any* ) - known ) %{ w = CheckWord::unknown; } );
}%%

%% write data noerror nofinal noentry;

CheckWord check_word(std::string_view arg) noexcept
{
    CheckWord w = CheckWord::none;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(arg.data());
    const auto* pe = p + arg.size();
    const auto* eof = pe;
    %% write init;
    %% write exec;
    return w;
}

namespace
{
constexpr unsigned hex_value(unsigned char c) noexcept
{
    return c <= '9' ? c - '0' : (c | 0x20u) - 'a' + 10;
}
}  // namespace

%%{
  machine side_info;
  alphtype unsigned char;

  action sel_digit { sel = sel << 4 | hex_value(fc); }
  action pos_start { pos = 0; }
  action pos_digit { if (pos < 0xffffffffull) pos = pos * 10 + (fc - '0'); }
  action pos_end { places.push_back({static_cast<std::uint32_t>(pos), {}}); }
  action type_start { type = fpc; }
  action type_end {
      places.back().type = std::string_view(reinterpret_cast<const char*>(type), static_cast<std::size_t>(fpc - type));
  }
  action line_start { sel = 0; fallback = false; places.clear(); }
  action fallback { fallback = true; }
  action line_end { out.push_back({fallback ? std::nullopt : std::optional<std::uint32_t>(sel), places}); }

  place = ( [0-9] @pos_digit )+ >pos_start %pos_end ( ':' ( [^ \n]+ >type_start %type_end ) )?;
  line = ( ( '0x' ( [0-9a-fA-F] @sel_digit ){1,8} | '_fallback' @fallback ) ( ' ' place )* ) >line_start
         '\n' @line_end;
  main := line*;
}%%

%% write data noerror noentry;

std::optional<std::vector<SideInfo>> parse_side_info(std::string_view text)
{
    std::vector<SideInfo> out;
    std::uint32_t sel = 0;
    bool fallback = false;
    std::uint64_t pos = 0;
    std::vector<SidePlace> places;
    const unsigned char* type = nullptr;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(text.data());
    const auto* pe = p + text.size();
    %% write init;
    %% write exec;
    if (cs < side_info_first_final)
        return std::nullopt;
    return out;
}
}  // namespace validate::text
