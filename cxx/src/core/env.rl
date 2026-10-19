// The environment's settings (rule 2: Ragel machines, ragel 6.10 -G2; rule
// 4: no floating point): PANORAMIX_TIMEOUT, a decimal factor as strtod reads
// its prefix, in fixed point (thousandths); PANORAMIX_MAX_MEMORY and
// PANORAMIX_COMPACT_MIB as strtoull(s, 0, 10) reads them (MiB). Read once.
#include <cstdint>
#include <limits>
#include <mutex>

#include "core/budget.hpp"
#include "core/platform.hpp"

// ragel -G2's goto code falls from a case into the next state's label
#pragma GCC diagnostic ignored "-Wimplicit-fallthrough"

namespace pan::env {

namespace {
constexpr u64 MANT_CAP = 100000000000000000ull;  // 1e17: mant stays below 1e18 (no digit separators: ragel reads them as quotes)
constexpr i64 EXP_CAP = 100000;
constexpr i64 MILLI_MAX = std::numeric_limits<i64>::max();

u64 pow10(i64 e) {
    u64 r = 1;
    while (e-- > 0) r *= 10;
    return r;
}
}  // namespace

%%{
    machine factor;
    write data noerror nofinal noentry;
}%%

i64 parse_factor_milli(const char* s) noexcept {
    if (!s) return 0;
    const char* p = s;
    const char* pe = s;
    while (*pe) ++pe;
    int cs;
    bool neg = false, eneg = false, inf = false;
    u64 mant = 0;
    i64 frac = 0, drop = 0, ex = 0;
    %%{
        action neg { neg = true; }
        action int_digit {
            if (mant < MANT_CAP) mant = mant * 10 + u64(fc - '0');
            else ++drop;
        }
        action frac_digit {
            if (mant < MANT_CAP) {
                mant = mant * 10 + u64(fc - '0');
                ++frac;
            }
        }
        action exp_neg { eneg = true; }
        action exp_digit { if (ex < EXP_CAP) ex = ex * 10 + (fc - '0'); }
        action inf { inf = true; }

        ws = [ \t\n\v\f\r];
        exponent = [eE] ('+' | '-' @exp_neg)? digit+ $exp_digit;
        number = (digit+ $int_digit ('.' digit* $frac_digit)? | '.' digit+ $frac_digit) exponent?;
        main := ws* ('+' | '-' @neg)? (number | /inf/i @inf /inity/i? | /nan/i) any*;

        write init;
        write exec;
    }%%
    (void)cs;
    i64 milli;
    if (inf) {
        milli = MILLI_MAX;
    } else if (!mant) {
        milli = 0;  // no number, 0, or nan
    } else {
        i64 e10 = (eneg ? -ex : ex) + drop - frac + 3;
        if (e10 >= 0) {
            if (e10 > 18) {
                milli = MILLI_MAX;
            } else {
                unsigned __int128 v = static_cast<unsigned __int128>(mant) * pow10(e10);
                milli = v > static_cast<unsigned __int128>(MILLI_MAX) ? MILLI_MAX : static_cast<i64>(v);
            }
        } else {
            milli = -e10 > 18 ? 0 : static_cast<i64>(mant / pow10(-e10));
            if (!milli) milli = 1;  // positive: a limit, the smallest
        }
    }
    return neg ? -milli : milli;
}

%%{
    machine decimal;
    write data noerror nofinal noentry;
}%%

u64 parse_u64(const char* s) noexcept {
    if (!s) return 0;
    const char* p = s;
    const char* pe = s;
    while (*pe) ++pe;
    int cs;
    bool neg = false, over = false;
    u64 v = 0;
    %%{
        action neg { neg = true; }
        action digit {
            u64 d = u64(fc - '0');
            if (v > (std::numeric_limits<u64>::max() - d) / 10) over = true;
            else v = v * 10 + d;
        }

        ws = [ \t\n\v\f\r];
        main := ws* ('+' | '-' @neg)? digit+ $digit any*;

        write init;
        write exec;
    }%%
    (void)cs;
    if (over) return std::numeric_limits<u64>::max();
    return neg ? u64(0) - v : v;
}

const Settings& settings() {
    static Settings s;
    static std::once_flag once;
    std::call_once(once, [] {
        if (const char* t = platform::env("PANORAMIX_TIMEOUT")) s.timeout_milli = parse_factor_milli(t);
        if (const char* m = platform::env("PANORAMIX_MAX_MEMORY")) {
            u64 mib = parse_u64(m);  // MiB to bytes, saturated (asm: 2^44 and more)
            s.max_memory_set = true;
            s.max_memory = (mib >> 44) ? std::numeric_limits<usize>::max() : usize(mib << 20);
        }
        if (const char* c = platform::env("PANORAMIX_COMPACT_MIB")) s.compact_bytes = usize(parse_u64(c) << 20);
    });
    return s;
}

}  // namespace pan::env
