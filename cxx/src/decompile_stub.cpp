// A stand-in for the core (decompile.hpp) until it exists: placeholder text
// that says what it was given - the code's size and a hash of it, the
// options -, so that the front-ends' tests can see their bytes and their
// options reach the core. A code that begins with de ad be ef fails as a
// decompilation that python's raises out of does (the front-ends' error
// paths). The core replaces this file whole.
#include <algorithm>
#include <cstdint>
#include <format>
#include <iterator>

#include "decompile.hpp"
#include "evm/decoder.hpp"
#include "hex.hpp"

namespace pan {

namespace {

// FNV-1a, 64 bits: the code's bytes as the stub received them
std::uint64_t fingerprint(std::span<const std::uint8_t> code)
{
    std::uint64_t h = 0xcbf29ce484222325;
    for (const std::uint8_t b : code)
        h = (h ^ b) * 0x100000001b3;
    return h;
}

bool asks_to_fail(std::span<const std::uint8_t> code)
{
    constexpr std::uint8_t trigger[] = {0xde, 0xad, 0xbe, 0xef};
    return code.size() >= 4 && std::equal(std::begin(trigger), std::end(trigger), code.begin());
}

}  // namespace

Decompilation decompile(std::span<const std::uint8_t> code, const DecompileOptions& options)
{
    Decompilation d;
    if (options.explain)
        d.explain = std::format("(stub) what --explain prints, for {} bytes of code\n", code.size());
    if (asks_to_fail(code))
        throw DecompileError("decompilation failed: (stub) the code asked for a failure", d.explain);
    const std::string_view gray = options.color ? "\033[38;5;8m" : "";
    const std::string_view endc = options.color ? "\033[0m" : "";
    d.text = std::format(
        "{}# Palkeoramix decompiler. {}\n\n"
        "# (stub: the C++ core isn't there yet)\n"
        "# {} bytes of code, fnv1a64 {:016x}\n"
        "# threads={} function='{}' color={:d} verbose={:d} explain={:d} repr={:d} returns={:d} json={:d} asm_lines={:d}",
        gray, endc, code.size(), fingerprint(code), options.threads, hex::escape(options.only_function),
        options.color, options.verbose, options.explain, options.repr, options.returns, options.json,
        options.asm_lines);
    if (options.json)
        d.json = std::format(R"({{"stub": true, "bytes": {}, "fnv1a64": "{:016x}", "problems": {{}}, "functions": []}})",
                             code.size(), fingerprint(code));
    if (options.asm_lines)
        d.asm_lines.push_back(std::format("(stub) {} bytes of code", code.size()));
    return d;
}

// the decoder's (lot 1, src/evm/)
std::string disassemble(std::span<const std::uint8_t> code) { return evm::disassemble(code); }

std::string decode_report(std::span<const std::uint8_t> code) { return evm::decode_report(code); }

}  // namespace pan
