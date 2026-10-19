// The validation's tests: Words and Bytes printed by doctest in hex.
#pragma once

#include "validate/effects.hpp"

#include <ostream>

#include <doctest/doctest.h>

namespace doctest
{
template <>
struct StringMaker<validate::Word>
{
    static String convert(const validate::Word& w) { return validate::hex(w).c_str(); }
};

template <>
struct StringMaker<validate::Bytes>
{
    static String convert(const validate::Bytes& b) { return validate::hex(b).c_str(); }
};
}  // namespace doctest
