// pancxx, the command line: the asm's panasm's commands, options, messages
// and exit codes, over the core's interface (decompile.hpp).
//   pancxx disasm <input>        the disassembly, like Loader.disasm()
//   pancxx decode <input>        what the decoder finds in the code
//   pancxx decompile <input[,input...]> [options]
//                                the decompilation, like `python -m panoramix`
//   pancxx build-db <abi_dump.xz> [out.bin]   the signature database
//   pancxx --version
// Options (after the input, as panasm's): -j N / --threads N (default: one
// per CPU), --function NAME (only the functions whose name starts with it),
// --no-color, --json (python's decompilation.json instead of the text), -v
// LEVEL (the log level, a number or a name, as python -m panoramix's),
// --verbose, --explain, --repr, --returns (python's).
// An input is "-" (the bytecode on stdin, or an address), an address (0x
// and 40 hex digits: its code fetched from a node, as python's
// decompile_address does - fetch.hpp), the bytecode itself in hex (as
// python -m panoramix takes it), or else a file holding the bytecode in hex
// - tried in that order: a server running `pancxx decompile <what it was
// sent>` never opens a path it was sent as bytecode. A comma-separated
// list of them (that isn't a readable file's name) is decompiled one after
// the other, as python -m panoramix does.
// Exit codes: 0, 1 (an input couldn't be had, a decompilation failed), 2
// (the usage).
#include <format>
#include <new>
#include <optional>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

#include "cli.hpp"
#include "decompile.hpp"
#include "fetch.hpp"
#include "hex.hpp"
#include "io.hpp"
#include "sigdb.hpp"
#include "version.hpp"

namespace {

using namespace pan;

constexpr std::string_view no_memory = "out of memory: the system gave no more";

// A line on stderr: a message of ours, then text from outside (escaped,
// `max` bytes of it at most: an argument, a file's path, standard input)
void error_line(std::string_view message, std::string_view outside = {}, std::size_t max = 0)
{
    io::write_all(io::Stream::err, std::string(message) + hex::escape(outside, max) + "\n");
}

// The code at an address, or nullopt with the reason on stderr
std::optional<std::vector<std::uint8_t>> fetched(std::string_view address)
{
    try {
        return fetch::code_at(address);
    } catch (const fetch::NotHex&) {
        error_line("not a valid hex file: ", address, 200);
    } catch (const fetch::Error& e) {
        error_line(e.what());  // (made of escaped parts already)
    } catch (const std::bad_alloc&) {
        error_line(no_memory);
    }
    return std::nullopt;
}

// The bytecode of an input, or nullopt with the reason on stderr. The hex
// it comes as is made bytes here, before anything else sees it.
std::optional<std::vector<std::uint8_t>> input_code(std::string_view input)
{
    std::string read;          // a file's or standard input's text
    std::string_view text;     // the hex
    std::string_view named;    // what "not a valid hex file" names
    std::size_t named_max = 200;
    const cli::InputShape shape = cli::input_shape(input);
    if (shape.standard_input) {
        auto in = io::read_standard_input(io::max_input);
        if (!in) {
            error_line("the standard input is longer than 256 MiB");
            return std::nullopt;
        }
        read = std::move(*in);
        text = named = cli::strip(read);  // (python's .strip(): an address?)
        if (cli::input_shape(text).address)
            return fetched(text);
    } else if (shape.address) {  // (an address is hex too: python takes a
        return fetched(input);   // 42-character argument for one)
    } else if (shape.hex) {
        text = named = input;
    } else {
        // a regular file of 256 MiB at most: the argument may be anybody's
        // (a fifo, /dev/zero read without end)
        auto file = io::read_regular_file(std::string(input), io::max_input);
        if (!file) {
            error_line("can't read the file: ", input, 4096);
            return std::nullopt;
        }
        read = std::move(*file);
        text = read;
        named = input;  // (a path: whole, not an excerpt)
        named_max = 4096;
    }
    auto code = hex::decode(text);
    if (!code) {
        error_line("not a valid hex file: ", named, named_max);
        return std::nullopt;
    }
    return std::move(*code);
}

// disasm, decode: the text of the input's code
int show(cli::Command command, std::string_view input)
{
    const auto code = input_code(input);
    if (!code)
        return 1;
    try {
        io::write_all(io::Stream::out, command == cli::Command::decode ? decode_report(*code) : disassemble(*code));
        return 0;
    } catch (const std::bad_alloc&) {
        error_line("the code couldn't be read: ", no_memory, 200);
    } catch (const std::exception& e) {
        error_line("the code couldn't be read: ", e.what(), 200);
    }
    return 1;
}

// decompile an input: --explain's text first, then the text (or the json)
// on stdout; or the message on stderr, 1
int decompile_one(std::string_view input, const DecompileOptions& options)
{
    const auto code = input_code(input);
    if (!code)
        return 1;
    try {
        Decompilation d = decompile(*code, options);
        if (options.explain)
            io::write_all(io::Stream::out, d.explain);
        std::string out = options.json ? std::move(d.json) : std::move(d.text);
        out += '\n';  // (python's print)
        io::write_all(io::Stream::out, out);
        return 0;
    } catch (const DecompileError& e) {
        if (options.explain)  // (printed along the way, as python does)
            io::write_all(io::Stream::out, e.explain());
        io::write_all(io::Stream::err, std::string(e.what()) + "\n");
    } catch (const std::bad_alloc&) {
        error_line(no_memory);
    } catch (const std::exception& e) {
        io::write_all(io::Stream::err, std::string("decompilation failed: ") + e.what() + "\n");
    }
    return 1;
}

int run(const cli::Run& run)
{
    if (run.log_level)
        set_log_level(*run.log_level);
    if (run.command != cli::Command::decompile)
        return show(run.command, run.input);
    // a list separated by commas (unless it is a file's name): each in
    // turn, as python -m panoramix does
    const auto parts = cli::split_list(run.input);
    if (parts.size() < 2 || io::readable(run.input))
        return decompile_one(run.input, run.options);
    int status = 0;
    for (const std::string_view part : parts)
        status |= decompile_one(part, run.options);
    return status;
}

int version()
{
    const auto& build = panoramix::build_info();
    io::write_all(io::Stream::out, std::format("pancxx {} ({}; {})\n{}\n", build.version, build.variant,
                                               build.compiler, build.flags));
    return 0;
}

template <class... F>
struct overloaded : F... {
    using F::operator()...;
};

}  // namespace

int main(int argc, char** argv)
{
    // the text written to a pipe closed early is an error (EPIPE), as it was
    io::ignore_broken_pipe();
    // (the signature database's messages: the log's)
    sigdb::set_log_sink(&pan::log);
    try {
        const std::vector<std::string_view> args(argv + (argc > 0), argv + argc);
        return std::visit(overloaded{
                              [](const cli::Usage&) {
                                  io::write_all(io::Stream::err, cli::usage);
                                  return 2;
                              },
                              [](const cli::BadLogLevel&) {
                                  io::write_all(io::Stream::err, cli::bad_log_level);
                                  return 1;
                              },
                              [](const cli::Version&) { return version(); },
                              [](const cli::BuildDb& db) { return build_signature_db(db.dump, db.out); },
                              [](const cli::Run& r) { return run(r); },
                          },
                          cli::parse(args));
    } catch (const std::bad_alloc&) {  // (what the decompilations' handlers don't take)
        error_line(no_memory);
    } catch (const std::exception& e) {
        error_line(e.what());
    }
    return 1;
}
