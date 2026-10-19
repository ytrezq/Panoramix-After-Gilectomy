// The storage analysis (storage.hpp): stub until the implementation lands.
#include "core/errors.hpp"
#include "storage/storage.hpp"

namespace pan::storage {

std::shared_ptr<const StorageLayout> analyse(std::span<FunctionInfo> functions, std::span<FunctionInfo> internals,
                                             const ContractShared& shared, const Options& opts) {
    (void)functions;
    (void)internals;
    (void)shared;
    (void)opts;
    throw Unsupported("storage: not yet");
}

std::shared_ptr<const StorageLayout> rewrite_raw(std::span<FunctionInfo> functions, std::span<FunctionInfo> internals,
                                                 Lang lang) {
    (void)functions;
    (void)internals;
    (void)lang;
    throw Unsupported("storage: not yet");
}

}  // namespace pan::storage
