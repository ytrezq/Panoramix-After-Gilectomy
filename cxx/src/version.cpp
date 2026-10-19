#include "version.hpp"

// cxx/Makefile writes build_info.h into the object directory of each build
// (rewritten only when its contents change, so that only this file is
// recompiled): PANORAMIX_VARIANT and PANORAMIX_FLAGS, string literals.
#if __has_include("build_info.h")
#include "build_info.h"
#endif

// The version: bump it here.
#define PANORAMIX_VERSION "0.1.0"

#ifndef PANORAMIX_VARIANT
#define PANORAMIX_VARIANT "unknown"
#endif
#ifndef PANORAMIX_FLAGS
#define PANORAMIX_FLAGS ""
#endif

#if defined(__clang__)
#define PANORAMIX_COMPILER "clang++ " __clang_version__
#elif defined(__GNUC__)
#define PANORAMIX_COMPILER "g++ " __VERSION__
#else
#define PANORAMIX_COMPILER "unknown"
#endif

namespace panoramix {

namespace {

constexpr BuildInfo kBuildInfo{
    PANORAMIX_VERSION,
    PANORAMIX_VARIANT,
    PANORAMIX_COMPILER,
    PANORAMIX_FLAGS,
};

}  // namespace

const BuildInfo& build_info() noexcept { return kBuildInfo; }

}  // namespace panoramix
