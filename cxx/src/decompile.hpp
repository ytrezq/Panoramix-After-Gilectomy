// The decompiler as its front-ends see it: the command line (main.cpp) and
// the python module (pymod.cpp) ask the core for these, and nothing else.
// The code they hand over is always raw bytecode: hex text is turned into
// bytes before it gets here (hex.hpp), whatever it came from.
//
// Until the core exists, decompile_stub.cpp implements the decompilation
// with placeholder text; the logging (log.cpp) is real.
#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace pan {

// What a decompilation is asked for: python's decompile_bytecode and its
// command line's options (python reads --verbose, --explain, --repr and
// --returns from sys.argv: they are options here).
struct DecompileOptions {
    // the functions decompiled at once: 0 for one per CPU; the core caps
    // what no machine has (the asm: 1024) - the text is the same at any count
    std::size_t threads = 0;
    // only the functions whose name starts with it (empty: all of them)
    std::string only_function;
    // the terminal's color codes in the text and in the explanation
    bool color = true;
    // --verbose: the instructions the symbolic execution ran, and the stack
    // before each, as comments of the text
    bool verbose = false;
    // --explain: every stage's trace of each function and the traits found
    // of it, as python prints them along the way (implies verbose)
    bool explain = false;
    // python's hidden --repr and --returns: after each function, its trace
    // as prettify.pprint_repr prints it, and its returns
    bool repr = false;
    bool returns = false;
    // Decompilation::json and Decompilation::asm_lines made (they cost: a
    // decompilation that doesn't need them leaves them empty)
    bool json = false;
    bool asm_lines = false;
};

struct Decompilation {
    // the contract as `python -m panoramix` prints it, without print()'s
    // newline at the end
    std::string text;
    // with options.asm_lines: the disassembly, an instruction a line (no
    // newline), as disassemble() makes it
    std::vector<std::string> asm_lines;
    // with options.json: python's decompilation.json (the problems, the
    // storage definitions, the functions...) as JSON text - its format is
    // the core's; the python module makes python's objects of it
    std::string json;
    // with options.explain: what --explain printed, in the order python
    // prints it (before the text)
    std::string explain;
};

// A decompilation that failed where python's raises out of
// decompile_bytecode (a function that fails is a problem reported in the
// text instead, as python does). what() is the line the command line
// prints on stderr: "decompilation failed: <why>".
class DecompileError : public std::runtime_error {
public:
    explicit DecompileError(const std::string& message, std::string explain = {})
        : std::runtime_error(message), explain_(std::move(explain))
    {
    }
    // what --explain had printed when it failed (printed all the same)
    const std::string& explain() const noexcept { return explain_; }

private:
    std::string explain_;
};

// The decompilation of the code. Calls may run at once, from any threads.
// The core's own limits bound it (PANORAMIX_MAX_MEMORY: a function's
// memory, PANORAMIX_TIMEOUT: its time...). Throws DecompileError, and
// std::bad_alloc when the system has no more memory.
Decompilation decompile(std::span<const std::uint8_t> code, const DecompileOptions& options);

// The disassembly, one instruction a line as panoramix's Loader.disasm()
// ("0x0, push1, 0x80\n"). Throws std::bad_alloc (or a std::exception
// whose what() says why the code couldn't be read).
std::string disassemble(std::span<const std::uint8_t> code);

// `pancxx decode`: what the decoder finds in the code, a fact a line (its
// size, instructions and jumpdests, solidity's free memory pointer, a push
// the end cuts, the bytes that aren't opcodes, the jumps, the selectors of
// solc's dispatcher). Throws as disassemble().
std::string decode_report(std::span<const std::uint8_t> code);

// --- Logging ---
// python's logging levels; a line on stderr in coloredlogs' format:
//   2026-09-27 21:17:30,527 host panoramix.loader[pid] INFO message
// colored when stderr is a terminal. The level is INFO until set_log_level,
// or $PANORAMIX_LOG's (a name: debug, info, warning, error...) - the python
// module sets WARNING when it is imported, unless $PANORAMIX_LOG is set.
// Text from outside (a node's answer, an argument) is escaped by whoever
// puts it in a message (hex::escape): log() writes the bytes it is given.
enum LogLevel : int {
    log_debug = 10,
    log_info = 20,
    log_warning = 30,
    log_error = 40,
    log_critical = 50,
};
void set_log_level(int level) noexcept;
int log_level() noexcept;
// whether a message of that level would be written
bool log_enabled(int level) noexcept;
// a line of the logger (e.g. "panoramix.loader"), whole: the lines of
// threads don't mix. The signature of sigdb's LogSink: pass &pan::log.
void log(int level, std::string_view logger, std::string_view message) noexcept;

// The signature database (function names): panoramix's abi_dump.xz made
// into the file the decompilations read. out_path empty: the default one
// (the cache directory). Logs as it goes; returns the exit code of
// `pancxx build-db`: 0 built, 1 failed, -1 not a dump it can read.
// (Declared here until the sigdb worker's src/sigdb.hpp links.)
int build_signature_db(const std::string& dump_path, const std::string& out_path);

}  // namespace pan
