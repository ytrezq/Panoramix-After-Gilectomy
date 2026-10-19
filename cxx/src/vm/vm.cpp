// The symbolic VM's entry points (stub until the VM lands).
#include "vm/vm.hpp"

#include "core/errors.hpp"

namespace pan::vm {

std::vector<FunctionInfo> discover(const ContractShared&, Budget&) { throw Unsupported("vm: not yet"); }

VmResult run_function(const ContractShared&, const FunctionInfo&, const VmOptions&) {
    throw Unsupported("vm: not yet");
}

}  // namespace pan::vm
