// The getters (lot 9 only; getters.cpp).
#pragma once

#include <memory>
#include <optional>
#include <span>

#include "analysis/traits.hpp"
#include "exec/machine.hpp"
#include "storage/internal.hpp"

namespace pan::storage::detail {

// python getter_access: what a getter returns - an access (a read of a
// variable, or of it as its type makes it: a cast, left-aligned, sign
// extended, a bool) - or the root of a struct (kitties)
struct GetterAccess {
    bool root = false;  // the members of a struct at `slot`
    Word256 slot{};
    Access access{};
};
// g: lot 8's getter_of; narrowed: g.value with the reads narrowed (python's
// replace_f(word(returns[0][1]), narrow))
std::optional<GetterAccess> getter_access(const traits::Getter& g, Value narrowed);

// python bytes_tail: a function's trace with what's after a first part of it
// (its checks of the params, say) replaced by the return of the bytes at the
// slot key, ABI-encoded - RETURN(DATA(ARR(STORAGE(256, 0, LENGTH(key)),
// SALL(SR(key))))) - when running both on the storage worlds says it is the
// same: python's (bytes as solidity keeps them, short and long, of the
// lengths the code may treat apart), and those words with garbage past the
// bytes, and encodings no solc makes (SALL is what solc's copy makes of
// anything: the rewrite holds on any storage); NIL else.
class BytesTail {
public:
    BytesTail(const FunctionInfo& fn, std::span<const FunctionInfo> internals, const ContractShared* shared);
    ~BytesTail();
    BytesTail(const BytesTail&) = delete;
    BytesTail& operator=(const BytesTail&) = delete;
    Value find(Value trace, Value key);

private:
    FunctionInfo fn_;
    StorageLayout layout_;  // (none of its own: the tail's SR forms only)
    exec::Program program_;
    std::unique_ptr<exec::Machine> machine_;
};

}  // namespace pan::storage::detail
