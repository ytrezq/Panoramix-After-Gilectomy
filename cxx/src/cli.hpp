// The command line of pancxx (the asm's panasm's: the same commands,
// options, messages and exit codes), and the readings of text the front-ends
// share: log levels, lists of inputs, what an input is. Every reading is a
// ragel machine (cli.rl).
#pragma once

#include <cstddef>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

#include "decompile.hpp"

namespace pan::cli {

inline constexpr std::string_view usage =
    "usage: pancxx disasm <file.hex|->\n"
    "       pancxx decode <file.hex|-|address|bytecode>\n"
    "       pancxx decompile <file.hex|-|address|bytecode>[,...] [-j threads] [--function name]\n"
    "                        [--no-color] [--json] [-v level] [--verbose] [--explain] [--repr] [--returns]\n"
    "       pancxx build-db <abi_dump.xz> [out.bin]\n"
    "       pancxx --version\n";

inline constexpr std::string_view bad_log_level = "Logging should be DEBUG/INFO/WARNING/ERROR.\n";

enum class Command { disasm, decode, decompile };

// disasm, decode or decompile an input
struct Run {
    Command command = Command::decompile;
    // argv[2]: a file of hex, "-" (standard input), an address, the bytecode
    // in hex - for decompile, a comma-separated list of them too
    std::string input;
    // decompile's (-j, --function, --no-color, --verbose, --explain, --repr,
    // --returns; --json sets options.json); disasm and decode take the
    // options but none of them
    DecompileOptions options;
    // -v's (the last one), to set before anything else
    std::optional<int> log_level;
};

// build-db <dump> [out]: the signature database (out empty: the default)
struct BuildDb {
    std::string dump;
    std::string out;
};

struct Version {};
// the usage on stderr, exit code 2
struct Usage {};
// bad_log_level on stderr, exit code 1
struct BadLogLevel {};

using Parsed = std::variant<Run, BuildDb, Version, Usage, BadLogLevel>;

// The arguments after the program's name, as panasm reads them: build-db
// first (and what follows its two arguments ignored), else a command and
// its input, then the options left to right - the first mistake decides
// (a bad -v level: BadLogLevel; anything else: Usage), the command is
// checked after them. An argument holds no NUL (argv's can't).
Parsed parse(std::span<const std::string_view> args);

// The level of a name, any case: debug 10, info 20, warning (warn) 30,
// error 40, critical (fatal) 50 - python's logging's.
std::optional<int> log_level_from_name(std::string_view name);

// -v's level: atol's of a number (when it begins with a digit; past INT_MAX,
// INT_MAX), else a name's.
std::optional<int> log_level_option(std::string_view value);

// C's atol (strtol's base 10): blanks, a sign, the digits, anything after
// ignored; LONG_MAX or LONG_MIN past them.
long c_long(std::string_view text);

// A list split at its commas, empty parts kept (python's split(",")).
std::vector<std::string_view> split_list(std::string_view list);

// The shapes an input has (an argument can have several: 0x and 40 hex
// digits is an address and hex).
struct InputShape {
    bool standard_input = false;  // "-"
    bool address = false;         // 0x or 0X and 40 more bytes: python's len == 42
    bool hex = false;             // 0x or not, then hex digits (one at least), nothing else
};
InputShape input_shape(std::string_view input);

// A text without the bytes up to 0x20 at its ends (what is read on
// standard input, as python's strip()).
std::string_view strip(std::string_view text);

}  // namespace pan::cli
