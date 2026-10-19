// SHA-256 (FIPS 180-4): the version of the signature dump the database was
// built from (its cache key), see sigdb.hpp.
//
// The block functions are sha256-simd's (github.com/libonomy/sha256-simd, a
// fork of minio/sha256-simd; cxx/third_party/sha256-simd): its x86-64 Go
// assembly translated into GNU as (sha256_shani.S, sha256_avx2.S,
// sha256_avx.S, sha256_ssse3.S) and its portable Go code into C++
// (sha256.cpp). The one used is chosen at run time as sha256-simd chooses it,
// from what the processor (cpuid) and the system (xgetbv) support.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

namespace pan::sha256 {

inline constexpr std::size_t digest_size = 32;
inline constexpr std::size_t block_size = 64;
using Digest = std::array<std::uint8_t, digest_size>;

// sha256-simd's implementations for x86-64, in the order of its choice.
enum class Impl : std::uint8_t {
    shani,    // the SHA extensions (with SSSE3 and SSE4.1)
    avx2,     // AVX2, with BMI1 and BMI2 (andn, rorx)
    avx,
    ssse3,
    generic,  // portable C++
};
inline constexpr std::array all_impls{Impl::shani, Impl::avx2, Impl::avx, Impl::ssse3,
                                      Impl::generic};

std::string_view name(Impl impl) noexcept;
// Whether this processor and system can run it (the generic one: always).
bool supported(Impl impl) noexcept;
// sha256-simd's choice: the first one supported.
Impl best() noexcept;

// An incremental hash: update() as many times as needed, then finish().
class Hasher {
public:
    // impl must be supported (see supported()).
    explicit Hasher(Impl impl = best()) noexcept;

    Hasher& update(std::span<const std::uint8_t> data) noexcept;
    Hasher& update(std::string_view data) noexcept;
    // The digest of what was given; the hasher starts again empty.
    Digest finish() noexcept;

private:
    void reset() noexcept;

    std::array<std::uint32_t, 8> state_;
    std::array<std::uint8_t, block_size> buffer_;  // a block's beginning
    std::size_t buffered_ = 0;
    std::uint64_t length_ = 0;                     // bytes given so far
    Impl impl_;
};

Digest hash(std::span<const std::uint8_t> data, Impl impl = best()) noexcept;
Digest hash(std::string_view data, Impl impl = best()) noexcept;

}  // namespace pan::sha256
