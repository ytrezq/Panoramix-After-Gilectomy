// Identities proven (identity.hpp).
#include "algebra/identity.hpp"

#include <optional>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "core/errors.hpp"

namespace pan::alg {

bool same_value(Value a, Value b) {
    if (a == b) return true;
    try {
        const Value na = normalize(a), nb = normalize(b);
        if (na == nb) return true;
        // (constants: their words - True is 1)
        const std::optional<Word256> ca = eval_const(na);
        if (!ca) return false;
        const std::optional<Word256> cb = eval_const(nb);
        return cb && *ca == *cb;
    } catch (const SizeLimit&) {  // (a normal form past the caps: not proven)
        return false;
    } catch (const DepthLimit&) {
        return false;
    }
}

}  // namespace pan::alg
