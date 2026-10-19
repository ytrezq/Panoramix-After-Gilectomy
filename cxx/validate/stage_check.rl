// stagecheck's parsers (AGENTS.md rule 2: Ragel machines): its options and
// the names of the stages (stage_check.hpp).
#include "validate/stage_check.hpp"

namespace validate
{
%%{
  machine stagecheck_option;
  alphtype unsigned char;

  main := '--stage' @{ id = StagecheckOption::stage; }
        | '--corpus' @{ id = StagecheckOption::corpus; }
        | '--seed' @{ id = StagecheckOption::seed; }
        | '--empty' @{ id = StagecheckOption::empty; }
        | '--random' @{ id = StagecheckOption::random; }
        | '--per-selector' @{ id = StagecheckOption::per_selector; }
        | '--sigdb' @{ id = StagecheckOption::sigdb; }
        | '--untyped' @{ id = StagecheckOption::untyped; }
        | ('-j' | '--jobs') @{ id = StagecheckOption::jobs; }
        | '--limit' @{ id = StagecheckOption::limit; }
        | '--show' @{ id = StagecheckOption::show; }
        | '--quiet' @{ id = StagecheckOption::quiet; }
        | '--timeout' @{ id = StagecheckOption::timeout; }
        | '--steps' @{ id = StagecheckOption::steps; }
        | '--gas' @{ id = StagecheckOption::gas; }
        | '--function' @{ id = StagecheckOption::function; }
        | '--seeds' @{ id = StagecheckOption::seeds; }
        | ('--help' | '-h') @{ id = StagecheckOption::help; };
}%%

%% write data noerror noentry;

StagecheckOption stagecheck_option(std::string_view arg)
{
    auto id = StagecheckOption::none;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(arg.data());
    const auto* pe = p + arg.size();
    %% write init;
    %% write exec;
    return cs >= stagecheck_option_first_final ? id : StagecheckOption::none;
}

%%{
  machine stage_name;
  alphtype unsigned char;

  main := 'raw' @{ s = Stage::raw; }
        | 'whiles' @{ s = Stage::whiles; }
        | 'simplified' @{ s = Stage::simplified; }
        | 'analysed' @{ s = Stage::analysed; }
        | 'folded' @{ s = Stage::folded; };
}%%

%% write data noerror noentry;

std::optional<Stage> parse_stage(std::string_view name)
{
    std::optional<Stage> s;
    int cs;
    const auto* p = reinterpret_cast<const unsigned char*>(name.data());
    const auto* pe = p + name.size();
    %% write init;
    %% write exec;
    if (cs < stage_name_first_final)
        return std::nullopt;
    return s;
}
}  // namespace validate
