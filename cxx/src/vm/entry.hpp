// What the discovery hands each function (lot 5 only): the VM's entry state
// in EntryCondition::vm_state - LIST(the stack, LIST of facts (kind, a, b,
// c), None for no value) - and the VM's deadlines.
#pragma once

#include "core/value.hpp"
#include "vm/facts.hpp"

namespace pan::vm {

Value encode_state(Value stack, const PathFacts& known);
// false when state isn't one (then stack and known are left as they were)
bool decode_state(Value state, Value& stack, PathFacts& known);
// the monotonic deadline of a VM run: timeout_ns, else base scaled by
// PANORAMIX_TIMEOUT; 0: none
i64 vm_deadline(i64 timeout_ns, i64 base_ns);

}  // namespace pan::vm
