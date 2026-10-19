// The core as the front-ends see it (decompile.hpp): the driver's
// decompilation (lot 12, driver/pipeline.hpp), the decoder's texts (lot 1,
// evm/decoder.hpp). This replaces src/decompile_stub.cpp.
#include "decompile.hpp"
#include "driver/pipeline.hpp"
#include "evm/decoder.hpp"

namespace pan {

Decompilation decompile(std::span<const std::uint8_t> code, const DecompileOptions& options)
{
    return driver::decompile(code, options);
}

std::string disassemble(std::span<const std::uint8_t> code) { return evm::disassemble(code); }

std::string decode_report(std::span<const std::uint8_t> code) { return evm::decode_report(code); }

}  // namespace pan
