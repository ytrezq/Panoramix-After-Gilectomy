// Identities proven, never sampled (lot 2's algebra): whether two word
// expressions have the same value for every value of what they read. The
// recognitions that rewrite on such an equality - SafeMath's abstraction of
// a site's checks (analysis/safemath.cpp), a storage form against the access
// it prints (storage/check.cpp) - accept only what this proves: false is
// "not proven", and the caller keeps what it had (the plain arithmetic and
// its checks, the raw slot), which is always sound.
#pragma once

#include "core/value.hpp"

namespace pan::alg {

// a and b have the same word for every value of their leaves (sound, not
// complete; on cx()): the same node, the same normal form (normalize: a
// constructor never changes a value - lot 2's property tests), or constants
// of the same word. What a pass rebuilt without renormalizing - a storage
// form or a SafeMath call put in a sum by mk_like, its terms in their old
// order - has the same normal form as the expression made again.
bool same_value(Value a, Value b);

}  // namespace pan::alg
