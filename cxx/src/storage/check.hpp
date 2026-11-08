// The check of the printed accesses (lot 9 only; check.cpp).
#pragma once

#include "core/memo.hpp"
#include "storage/internal.hpp"
#include "storage/storage.hpp"

namespace pan::storage::detail {

// python checks(): whether a form reads as the access it prints - proven to
// denote the slot and the bits the access reads for every value of what
// they are computed from, else refused (the access is then printed raw).
// One per analysis: the canonical expressions are memoized.
class Checker {
public:
    bool check(const StorageLayout& layout, Value f, const Access& a);
    u64 proven() const noexcept { return proven_; }
    u64 refused() const noexcept { return refused_; }

private:
    Value canon(Value v);        // a word
    Value bytes_canon(Value v);  // what may be bytes
    bool same(Value a, Value b);
    bool refuse() noexcept {
        ++refused_;
        return false;
    }
    Memo<Value, Value> canon_, bytes_;
    u64 proven_ = 0, refused_ = 0;
};

}  // namespace pan::storage::detail
