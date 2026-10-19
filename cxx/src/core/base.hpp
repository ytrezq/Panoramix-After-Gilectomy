// The basics every file uses: the integer types and the compiler's hints.
// (The exceptions are in core/errors.hpp.)
#pragma once

#include <cstddef>
#include <cstdint>

#define PAN_LIKELY(x) __builtin_expect(!!(x), 1)
#define PAN_UNLIKELY(x) __builtin_expect(!!(x), 0)
#define PAN_NOINLINE __attribute__((noinline))
#define PAN_COLD __attribute__((cold, noinline))
#define PAN_ALWAYS_INLINE inline __attribute__((always_inline))
// the thread-local variables of the hot paths: one load from %fs (an
// executable, or a library loaded with the program - the python module is
// dlopen'ed, which the static TLS block has room for).
// Use: `inline thread_local T* name PAN_TLS = nullptr;`
#define PAN_TLS __attribute__((tls_model("initial-exec")))

namespace pan {

using u8 = std::uint8_t;
using i8 = std::int8_t;
using u16 = std::uint16_t;
using u32 = std::uint32_t;
using u64 = std::uint64_t;
using i16 = std::int16_t;
using i32 = std::int32_t;
using i64 = std::int64_t;
using usize = std::size_t;
using isize = std::ptrdiff_t;

}  // namespace pan
