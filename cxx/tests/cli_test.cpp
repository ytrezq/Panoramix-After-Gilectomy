// cli.hpp: the command line as panasm reads it, and the other readings.
#include <doctest/doctest.h>

#include <cerrno>
#include <climits>
#include <cstdlib>
#include <initializer_list>
#include <random>
#include <string>
#include <string_view>
#include <vector>

#include "cli.hpp"

namespace cli = pan::cli;

namespace {

cli::Parsed parse(std::initializer_list<std::string_view> args)
{
    const std::vector<std::string_view> v(args);
    return cli::parse(v);
}

cli::Run run_of(std::initializer_list<std::string_view> args)
{
    const auto parsed = parse(args);
    REQUIRE(std::holds_alternative<cli::Run>(parsed));
    return std::get<cli::Run>(parsed);
}

template <class T>
bool is(std::initializer_list<std::string_view> args)
{
    return std::holds_alternative<T>(parse(args));
}

std::size_t threads_of(std::string_view value)
{
    return run_of({"decompile", "x", "-j", value}).options.threads;
}

}  // namespace

TEST_CASE("parse: too few arguments")
{
    CHECK(is<cli::Usage>({}));
    CHECK(is<cli::Usage>({"decompile"}));
    CHECK(is<cli::Usage>({"disasm"}));
    CHECK(is<cli::Usage>({"build-db"}));
    CHECK(is<cli::Usage>({""}));
}

TEST_CASE("parse: the commands")
{
    auto r = run_of({"decompile", "in.hex"});
    CHECK(r.command == cli::Command::decompile);
    CHECK(r.input == "in.hex");
    CHECK(r.options.threads == 0);
    CHECK(r.options.only_function.empty());
    CHECK(r.options.color);
    CHECK_FALSE(r.options.verbose);
    CHECK_FALSE(r.options.explain);
    CHECK_FALSE(r.options.repr);
    CHECK_FALSE(r.options.returns);
    CHECK_FALSE(r.options.json);
    CHECK_FALSE(r.log_level);
    CHECK(run_of({"disasm", "-"}).command == cli::Command::disasm);
    CHECK(run_of({"decode", "0x6000"}).command == cli::Command::decode);
    // the options are read for every command (and used by decompile only)
    CHECK(run_of({"decode", "x", "--json", "-j", "4"}).command == cli::Command::decode);
    // the input is argv[2], whatever it looks like
    CHECK(run_of({"decompile", "--json"}).input == "--json");
    CHECK_FALSE(run_of({"decompile", "--json"}).options.json);
    CHECK(run_of({"decompile", ""}).input.empty());
}

TEST_CASE("parse: an unknown command is refused after the options")
{
    CHECK(is<cli::Usage>({"foo", "x"}));
    CHECK(is<cli::Usage>({"decompiles", "x"}));
    CHECK(is<cli::Usage>({"Decompile", "x"}));
    CHECK(is<cli::Usage>({"foo", "x", "--json"}));
    CHECK(is<cli::BadLogLevel>({"foo", "x", "-v", "bogus"}));
    CHECK(is<cli::Usage>({"foo", "x", "--bad", "-v", "bogus"}));
}

TEST_CASE("parse: the options")
{
    auto r = run_of({"decompile", "in", "--no-color", "--verbose", "--repr", "--returns", "--json", "-j", "3",
                     "--function", "transfer", "-v", "debug"});
    CHECK_FALSE(r.options.color);
    CHECK(r.options.verbose);
    CHECK_FALSE(r.options.explain);
    CHECK(r.options.repr);
    CHECK(r.options.returns);
    CHECK(r.options.json);
    CHECK(r.options.threads == 3);
    CHECK(r.options.only_function == "transfer");
    CHECK(r.log_level == 10);
    auto x = run_of({"decompile", "in", "--explain"});
    CHECK(x.options.explain);
    CHECK(x.options.verbose);
    CHECK(run_of({"decompile", "in", "--threads", "5"}).options.threads == 5);
    // the last one counts
    CHECK(run_of({"decompile", "in", "-j", "2", "-j", "7"}).options.threads == 7);
    CHECK(run_of({"decompile", "in", "-v", "debug", "-v", "error"}).log_level == 40);
    // a value is the next argument, whatever it is
    auto f = run_of({"decompile", "in", "--function", "--json"});
    CHECK(f.options.only_function == "--json");
    CHECK_FALSE(f.options.json);
    CHECK(run_of({"decompile", "in", "--function", ""}).options.only_function.empty());
}

TEST_CASE("parse: mistakes, the first one decides")
{
    CHECK(is<cli::Usage>({"decompile", "in", "--bad"}));
    CHECK(is<cli::Usage>({"decompile", "in", "-J", "2"}));
    CHECK(is<cli::Usage>({"decompile", "in", "--no-color=1"}));
    CHECK(is<cli::Usage>({"decompile", "in", "-j"}));
    CHECK(is<cli::Usage>({"decompile", "in", "--function"}));
    CHECK(is<cli::Usage>({"decompile", "in", "-v"}));
    CHECK(is<cli::Usage>({"decompile", "in", "-j", "-1"}));
    CHECK(is<cli::Usage>({"decompile", "in", "-j", "-4", "-v", "bogus"}));
    CHECK(is<cli::BadLogLevel>({"decompile", "in", "-v", "bogus"}));
    CHECK(is<cli::BadLogLevel>({"decompile", "in", "-v", "bogus", "--bad"}));
    CHECK(is<cli::BadLogLevel>({"decompile", "in", "-v", "bogus", "-j", "-1"}));
    CHECK(is<cli::Usage>({"decompile", "in", "--bad", "-v", "bogus"}));
}

TEST_CASE("parse: -j as atol reads it")
{
    CHECK(threads_of("1") == 1);
    CHECK(threads_of("0") == 1);   // (0 asks for one, as panasm's)
    CHECK(threads_of("-0") == 1);
    CHECK(threads_of("abc") == 1);
    CHECK(threads_of("") == 1);
    CHECK(threads_of(" 12abc") == 12);
    CHECK(threads_of("+8") == 8);
    CHECK(threads_of("4611686018427387904") == 4611686018427387904ull);
    CHECK(threads_of("99999999999999999999") == static_cast<std::size_t>(LONG_MAX));
    CHECK(is<cli::Usage>({"decompile", "x", "-j", "-99999999999999999999"}));
    CHECK(is<cli::Usage>({"decompile", "x", "-j", " -2"}));
}

TEST_CASE("parse: -v, a number or a name")
{
    auto level = [](std::string_view value) { return run_of({"decompile", "x", "-v", value}).log_level; };
    CHECK(level("10") == 10);
    CHECK(level("20x") == 20);
    CHECK(level("0") == 0);
    CHECK(level("99999999999") == INT_MAX);
    CHECK(level("WARN") == 30);
    CHECK(level("Warning") == 30);
    CHECK(level("info") == 20);
    CHECK(level("ERROR") == 40);
    CHECK(level("Critical") == 50);
    CHECK(level("fatal") == 50);
    CHECK(is<cli::BadLogLevel>({"decompile", "x", "-v", ""}));
    CHECK(is<cli::BadLogLevel>({"decompile", "x", "-v", " 10"}));
    CHECK(is<cli::BadLogLevel>({"decompile", "x", "-v", "+10"}));
    CHECK(is<cli::BadLogLevel>({"decompile", "x", "-v", "debugx"}));
    CHECK(is<cli::BadLogLevel>({"decompile", "x", "-v", "notset"}));
}

TEST_CASE("parse: build-db and --version")
{
    auto db = std::get<cli::BuildDb>(parse({"build-db", "dump.xz"}));
    CHECK(db.dump == "dump.xz");
    CHECK(db.out.empty());
    db = std::get<cli::BuildDb>(parse({"build-db", "dump.xz", "out.bin"}));
    CHECK(db.dump == "dump.xz");
    CHECK(db.out == "out.bin");
    // what follows is not read (panasm doesn't)
    db = std::get<cli::BuildDb>(parse({"build-db", "d", "o", "x", "-v", "bogus", "-j", "-1"}));
    CHECK(db.out == "o");
    CHECK(std::get<cli::BuildDb>(parse({"build-db", "-v", "--json"})).dump == "-v");
    CHECK(is<cli::Version>({"--version"}));
    CHECK(is<cli::Version>({"--version", "x", "--bad"}));
    CHECK(is<cli::Usage>({"--versions", "x"}));
}

TEST_CASE("c_long: strtol's base 10")
{
    for (const char* s : {"", "0", "1", "-1", "+1", "  42", "\t\n\v\f\r 7x", "- 5", "--5", "+-5", "12 34", "x12",
                          "007", "-007", "9223372036854775807", "9223372036854775808", "-9223372036854775808",
                          "-9223372036854775809", "123456789012345678901234567890", "-0", "+", "-", " +12abc",
                          "18446744073709551620", "-18446744073709551620", "18446744073709551615",
                          "92233720368547758079", "1844674407370955162x", "99999999999999999999"}) {
        errno = 0;
        CHECK_MESSAGE(cli::c_long(s) == std::strtol(s, nullptr, 10), "\"", s, "\"");
    }
    std::mt19937 random(11);
    const std::string alphabet = " \t+-0123456789ax\n";
    for (int i = 0; i < 20000; ++i) {
        std::string s;
        for (int n = random() % 12; n > 0; --n)
            s += alphabet[random() % alphabet.size()];
        CHECK_MESSAGE(cli::c_long(s) == std::strtol(s.c_str(), nullptr, 10), "\"", s, "\"");
    }
    // numbers of 17 to 24 digits, around the limits
    for (int i = 0; i < 20000; ++i) {
        std::string s = random() % 2 ? "-" : "";
        s += static_cast<char>('1' + random() % 9);
        for (int n = 16 + random() % 8; n > 0; --n)
            s += static_cast<char>('0' + random() % 10);
        CHECK_MESSAGE(cli::c_long(s) == std::strtol(s.c_str(), nullptr, 10), "\"", s, "\"");
    }
}

TEST_CASE("log_level_from_name: names only, any case")
{
    CHECK(cli::log_level_from_name("debug") == 10);
    CHECK(cli::log_level_from_name("DEBUG") == 10);
    CHECK(cli::log_level_from_name("Info") == 20);
    CHECK(cli::log_level_from_name("warning") == 30);
    CHECK(cli::log_level_from_name("warn") == 30);
    CHECK(cli::log_level_from_name("error") == 40);
    CHECK(cli::log_level_from_name("critical") == 50);
    CHECK(cli::log_level_from_name("FATAL") == 50);
    CHECK_FALSE(cli::log_level_from_name("10"));
    CHECK_FALSE(cli::log_level_from_name(""));
    CHECK_FALSE(cli::log_level_from_name("warni"));
    CHECK_FALSE(cli::log_level_from_name("errors"));
    CHECK_FALSE(cli::log_level_from_name(" info"));
}

TEST_CASE("split_list: python's split(',')")
{
    using V = std::vector<std::string_view>;
    CHECK(cli::split_list("a") == V{"a"});
    CHECK(cli::split_list("a,b") == V{"a", "b"});
    CHECK(cli::split_list("a,,b") == V{"a", "", "b"});
    CHECK(cli::split_list(",") == V{"", ""});
    CHECK(cli::split_list("") == V{""});
    CHECK(cli::split_list("0x01,f.hex,-") == V{"0x01", "f.hex", "-"});
}

TEST_CASE("input_shape: stdin, an address, hex")
{
    const std::string forty(40, 'a');
    auto shape = cli::input_shape("-");
    CHECK(shape.standard_input);
    CHECK_FALSE(shape.address);
    CHECK_FALSE(shape.hex);
    CHECK_FALSE(cli::input_shape("--").standard_input);
    shape = cli::input_shape("0x" + forty);
    CHECK(shape.address);
    CHECK(shape.hex);
    CHECK_FALSE(shape.standard_input);
    shape = cli::input_shape("0x" + std::string(40, 'g'));  // (python's len == 42: fetched, then refused)
    CHECK(shape.address);
    CHECK_FALSE(shape.hex);
    CHECK(cli::input_shape("0X" + forty).address);
    CHECK_FALSE(cli::input_shape("0x" + forty + "a").address);
    CHECK(cli::input_shape("0x" + forty + "a").hex);
    CHECK_FALSE(cli::input_shape("1x" + forty).address);
    CHECK(cli::input_shape("6000").hex);
    CHECK(cli::input_shape("0x6").hex);  // (odd: hex, refused by the decoding)
    CHECK(cli::input_shape("0").hex);
    for (const char* none : {"", "0x", "60 00", "file.hex", "/dev/zero", "0x60g"}) {
        shape = cli::input_shape(none);
        CHECK_MESSAGE(!(shape.standard_input || shape.address || shape.hex), none);
    }
}

TEST_CASE("strip: the bytes up to 0x20 at the ends")
{
    CHECK(cli::strip("  a b \n") == "a b");
    CHECK(cli::strip("") == "");
    CHECK(cli::strip("\x01 \x20") == "");
    CHECK(cli::strip(std::string_view("\0ab\x1f", 4)) == "ab");
    CHECK(cli::strip("\xc3\xa9") == "\xc3\xa9");
    CHECK(cli::strip("x") == "x");
}
