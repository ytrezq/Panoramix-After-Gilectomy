// The decompiler's version and how this build was made: for `pancxx
// --version` and the python module's __version__.
#pragma once

#include <string_view>

namespace panoramix {

struct BuildInfo {
    std::string_view version;   // the decompiler's version: "0.1.0"
    std::string_view variant;   // the Makefile's build: "release", "pgo",
                                // "pgo-instrumented", "debug" (or "unknown"
                                // when built outside cxx/Makefile)
    std::string_view compiler;  // "g++ 14.2.0"
    std::string_view flags;     // the compiler's flags for the library, one
                                // line ("-std=gnu++23 -march=native ...")
};

// Constants of the build (cxx/Makefile writes the variant and the flags).
const BuildInfo& build_info() noexcept;

}  // namespace panoramix
