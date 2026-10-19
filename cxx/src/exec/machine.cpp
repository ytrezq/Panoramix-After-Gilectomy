// The trace machine (machine.hpp): stub until the implementation lands.
#include "exec/machine.hpp"

#include "core/errors.hpp"

namespace pan::exec {

struct Machine::Impl {
    Program program;
    MachineLimits limits;
};

Machine::Machine(const Program& program, MachineLimits limits) : impl_(std::make_unique<Impl>(Impl{program, limits})) {}
Machine::~Machine() = default;

Outcome Machine::call(Host&, std::optional<u32>) {
    Outcome o;
    o.status = Status::Unsupported;
    o.note = "exec: not yet";
    return o;
}

Outcome Machine::run(Host&, const FunctionInfo&, Value, bool) {
    Outcome o;
    o.status = Status::Unsupported;
    o.note = "exec: not yet";
    return o;
}

const Program& Machine::program() const noexcept { return impl_->program; }
const MachineLimits& Machine::limits() const noexcept { return impl_->limits; }
void Machine::set_limits(const MachineLimits& l) noexcept { impl_->limits = l; }

const char* status_name(Status s) noexcept {
    switch (s) {
        case Status::Stop: return "stop";
        case Status::Return: return "return";
        case Status::Revert: return "revert";
        case Status::Invalid: return "invalid";
        case Status::Exhausted: return "exhausted";
        case Status::Undefined: return "undefined";
        case Status::Unsupported: return "unsupported";
        case Status::Bug: return "bug";
    }
    return "?";
}

}  // namespace pan::exec
