// Whether a getter's name can name its storage variable (lot 9 only;
// names.rl, python storage.good_name and the "get" of getBalance): the
// signature database's names are raw bytes - Ragel machines over them.
#pragma once

#include <span>

#include "core/base.hpp"

namespace pan::storage::detail {

struct GetterName {
    bool good = false;   // it names the variable
    bool strip = false;  // without its "get", the next letter lowercased (getBalance -> balance)
};

// python: name = f.name.split("(")[0]; getX... -> x...; good_name(name)
GetterName getter_name(std::span<const u8> name) noexcept;

// python good_name: an identifier (ASCII), not unknown..., not _..., not a
// word of the output (stor, mem, msg, address, max...), not one of the
// default names (uintN intN bytesN storN storXXXX storN_M)
bool good_name(std::span<const u8> name) noexcept;

}  // namespace pan::storage::detail
