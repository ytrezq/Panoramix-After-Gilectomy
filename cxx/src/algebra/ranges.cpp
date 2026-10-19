// Value ranges: see ranges.hpp. (First version: trivially correct answers;
// the interval domain follows.)
#include "algebra/ranges.hpp"

#include "algebra/facts.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"

namespace pan::alg {

Range Range::word() { return Range{EvmInt(0), word_max()}; }

Range Range::bits(u32 n) {
    if (n >= 256) return word();
    return Range{EvmInt(0), EvmInt::pow2(n) - EvmInt(1)};
}

bool Range::is_word() const noexcept { return lo.sign() >= 0 && hi <= word_max(); }

std::optional<Range> Range::meet(const Range& o) const {
    const EvmInt& l = lo < o.lo ? o.lo : lo;
    const EvmInt& h = hi < o.hi ? hi : o.hi;
    if (h < l) return std::nullopt;
    return Range{l, h};
}

Range Range::hull(const Range& o) const { return Range{lo < o.lo ? lo : o.lo, hi < o.hi ? o.hi : hi}; }

Range Range::as_word() const {
    if (is_word()) return *this;
    EvmInt j = floordiv(lo, two_256());
    if (floordiv(hi, two_256()) != j) return word();
    EvmInt shift = j * two_256();
    return Range{lo - shift, hi - shift};
}

Range range(Value, Top, const Facts*) { return Range::word(); }

Range int_range(const Linear& l, Top, const Facts*) {
    EvmInt lo = l.constant_int(), hi = l.constant_int();
    for (usize i = 0; i < l.terms.size(); ++i) {
        EvmInt k = l.coeff_int(i);
        if (k.sign() > 0)
            hi += k * word_max();
        else
            lo += k * word_max();
    }
    return Range{lo, hi};
}

Range int_range(Value v, Top top, const Facts* facts) { return int_range(linear(v), top, facts); }

u32 range_bits(Value, Top, const Facts*) { return 256; }

bool is_word(Value v, Top top, const Facts* facts) { return int_range(v, top, facts).is_word(); }

std::optional<int> shift_sign(Value v) {
    if (v.is_small() && v.small_val() == 0) return 0;
    return std::nullopt;
}

void set_variables(std::span<const std::pair<Value, Value>>, std::span<const Value>) {}
void clear_variables() {}
void set_free_memory_pointer(bool) {}
bool free_memory_pointer() { return true; }
bool unchecked(Value) { return true; }

}  // namespace pan::alg
