// The command line and the front-ends' other readings of text (cli.hpp):
// a ragel machine each.
#include "cli.hpp"

#include <climits>
#include <cstdint>

// (ragel -G2 makes the cases of its switches fall through)
#pragma GCC diagnostic ignored "-Wimplicit-fallthrough"

namespace pan::cli {

namespace {

std::string text(const unsigned char* begin, const unsigned char* end)
{
    return {reinterpret_cast<const char*>(begin), static_cast<std::size_t>(end - begin)};
}

// The arguments one after the other, each ended by a NUL: the command line
// as one text, which one machine reads (see parse).
%%{
    machine command_line;
    alphtype unsigned char;

    action mark { mark = p + 1; }
    action decompile { command = Command::decompile; }
    action decode { command = Command::decode; }
    action disasm { command = Command::disasm; }
    action version { version = true; }
    action input { run.input = text(mark, p); }
    action dump { db.dump = text(mark, p); mark = p + 1; build_db = true; }
    action out { db.out = text(mark, p); }
    action no_color { run.options.color = false; }
    action verbose { run.options.verbose = true; }
    action explain { run.options.verbose = run.options.explain = true; }
    action repr { run.options.repr = true; }
    action returns { run.options.returns = true; }
    action json { run.options.json = true; }
    action threads {
        // (a negative count is no count; 0 asks for one, as panasm's: the
        // options' 0 is one per CPU)
        const long n = c_long(text(mark, p));
        if (n < 0) {
            failure = Failure::usage;
            fbreak;
        }
        run.options.threads = n == 0 ? 1 : static_cast<std::size_t>(n);
    }
    action level {
        if (const auto level = log_level_option(text(mark, p)))
            run.log_level = *level;
        else {
            failure = Failure::bad_level;
            fbreak;
        }
    }
    action function { run.options.only_function = text(mark, p); }

    end = 0;
    arg = [^\0]*;

    # the command: any word but build-db and --version (whose arguments
    # aren't options), the known ones noted - an unknown one is refused
    # after the options, as panasm does
    word = (arg - ('build-db' | '--version')) end
         | 'decompile' end @decompile
         | 'decode' end @decode
         | 'disasm' end @disasm;

    option = '--no-color' end @no_color
           | '--verbose' end @verbose
           | '--explain' end @explain
           | '--repr' end @repr
           | '--returns' end @returns
           | '--json' end @json
           | ('-j' | '--threads') end @mark arg end @threads
           | '-v' end @mark arg end @level
           | '--function' end @mark arg end @function;

    run = word @mark arg end @input option*;
    build_db = 'build-db' end @mark arg end @dump (arg end @out)? (arg end)*;
    version = '--version' end @version (arg end)*;

    main := run | build_db | version;
}%%

%% write data;

// C's atol: the sign and the digits after the blanks, the rest ignored -
// the left machine of each <: keeps what it can take (a '-' is the sign,
// not the rest; a digit after it is the number's)
%%{
    machine c_long;
    alphtype unsigned char;

    action minus { negative = true; }
    action digit {
        // (2^63 at most: LONG_MAX past it, LONG_MIN for its negative)
        const unsigned d = static_cast<unsigned>(fc - '0');
        magnitude = magnitude > (limit + 1 - d) / 10 ? limit + 1 : magnitude * 10 + d;
    }

    # (space: ragel's, C's isspace)
    main := space* <: ('+' | '-' @minus)? <: (digit @digit)* <: any*;
}%%

%% write data;

// python's logging's names of levels, any case
%%{
    machine level_names;
    alphtype unsigned char;

    action lv_debug { level = 10; }
    action lv_info { level = 20; }
    action lv_warning { level = 30; }
    action lv_error { level = 40; }
    action lv_critical { level = 50; }

    names = 'debug'i @lv_debug
          | 'info'i @lv_info
          | 'warning'i @lv_warning
          | 'warn'i @lv_warning
          | 'error'i @lv_error
          | 'critical'i @lv_critical
          | 'fatal'i @lv_critical;
}%%

%%{
    machine log_level_name;
    include level_names;
    main := names;
}%%

%% write data;

// -v's: atol's number when it begins with a digit, else a name
%%{
    machine log_level_option;
    include level_names;

    action digit {
        numeric = true;
        if (number <= INT_MAX)
            number = number * 10 + static_cast<unsigned>(fc - '0');
        if (number > INT_MAX)
            number = INT_MAX;
    }

    main := (digit @digit)+ <: any* | names;
}%%

%% write data;

%%{
    machine list;
    alphtype unsigned char;

    action comma {
        parts.emplace_back(reinterpret_cast<const char*>(start), static_cast<std::size_t>(p - start));
        start = p + 1;
    }

    main := ([^,] | ',' @comma)*;
}%%

%% write data;

// The shapes are noted at the end of the input (the leaving actions, run
// at eof by the final states they leave): every one the input has.
%%{
    machine input_shape;
    alphtype unsigned char;

    action standard_input { shape.standard_input = true; }
    action address { shape.address = true; }
    action hex { shape.hex = true; }

    main := '-' %standard_input
          | ('0' [xX] any{40}) %address
          | (('0' [xX])? xdigit+) %hex
          | any*;
}%%

%% write data;

%%{
    machine strip;
    alphtype unsigned char;

    action inner {
        if (!first)
            first = p;
        last = p + 1;
    }

    main := (0..0x20 | 0x21..0xff @inner)*;
}%%

%% write data;

enum class Failure { none, usage, bad_level };

}  // namespace

Parsed parse(std::span<const std::string_view> args)
{
    std::string line;
    for (const std::string_view arg : args) {
        line += arg;
        line += '\0';
    }
    const auto* p = reinterpret_cast<const unsigned char*>(line.data());
    const auto* const pe = p + line.size();
    const unsigned char* mark = p;
    std::optional<Command> command;
    Run run;
    BuildDb db;
    bool build_db = false, version = false;
    Failure failure = Failure::none;
    int cs;
    %% machine command_line;
    %% write init;
    %% write exec;
    switch (failure) {
    case Failure::usage:
        return Usage{};
    case Failure::bad_level:
        return BadLogLevel{};
    case Failure::none:
        break;
    }
    if (cs < command_line_first_final)  // (the error state too)
        return Usage{};
    if (version)
        return Version{};
    if (build_db)
        return db;
    if (!command)
        return Usage{};
    run.command = *command;
    return run;
}

long c_long(std::string_view text)
{
    constexpr std::uint64_t limit = LONG_MAX;
    std::uint64_t magnitude = 0;
    bool negative = false;
    const auto* p = reinterpret_cast<const unsigned char*>(text.data());
    const auto* const pe = p + text.size();
    int cs;
    %% machine c_long;
    %% write init;
    %% write exec;
    (void)cs;
    if (negative)
        return magnitude > limit ? LONG_MIN : -static_cast<long>(magnitude);
    return magnitude > limit ? LONG_MAX : static_cast<long>(magnitude);
}

std::optional<int> log_level_from_name(std::string_view name)
{
    int level = 0;
    const auto* p = reinterpret_cast<const unsigned char*>(name.data());
    const auto* const pe = p + name.size();
    int cs;
    %% machine log_level_name;
    %% write init;
    %% write exec;
    if (cs < log_level_name_first_final)
        return std::nullopt;
    return level;
}

std::optional<int> log_level_option(std::string_view value)
{
    int level = 0;
    std::uint64_t number = 0;
    bool numeric = false;
    const auto* p = reinterpret_cast<const unsigned char*>(value.data());
    const auto* const pe = p + value.size();
    int cs;
    %% machine log_level_option;
    %% write init;
    %% write exec;
    if (cs < log_level_option_first_final)
        return std::nullopt;
    return numeric ? static_cast<int>(number) : level;
}

std::vector<std::string_view> split_list(std::string_view list)
{
    std::vector<std::string_view> parts;
    const auto* p = reinterpret_cast<const unsigned char*>(list.data());
    const auto* const pe = p + list.size();
    const unsigned char* start = p;
    int cs;
    %% machine list;
    %% write init;
    %% write exec;
    (void)cs;
    parts.emplace_back(reinterpret_cast<const char*>(start), static_cast<std::size_t>(pe - start));
    return parts;
}

InputShape input_shape(std::string_view input)
{
    InputShape shape;
    const auto* p = reinterpret_cast<const unsigned char*>(input.data());
    const auto* const pe = p + input.size();
    const auto* const eof = pe;
    int cs;
    %% machine input_shape;
    %% write init;
    %% write exec;
    (void)cs;
    return shape;
}

std::string_view strip(std::string_view text)
{
    const auto* p = reinterpret_cast<const unsigned char*>(text.data());
    const auto* const pe = p + text.size();
    const unsigned char* first = nullptr;
    const unsigned char* last = nullptr;
    int cs;
    %% machine strip;
    %% write init;
    %% write exec;
    (void)cs;
    if (!first)
        return text.substr(text.size());
    return {reinterpret_cast<const char*>(first), static_cast<std::size_t>(last - first)};
}

}  // namespace pan::cli
