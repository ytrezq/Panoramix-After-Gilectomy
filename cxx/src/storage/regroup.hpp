// The stores of whole variables (lot 9 only; regroup.cpp, python Regroup).
#pragma once

#include <optional>
#include <span>
#include <vector>

#include "core/memo.hpp"
#include "storage/internal.hpp"

namespace pan::storage::detail {

// python slot_class(): what the slots of the same place of a variable have
// in common - the steps to them without their keys and indexes
struct ClassStep {
    enum class Kind : u8 { Map, Data, Off };
    Kind kind = Kind::Off;
    bool bytes_key = false;  // Map
    EvmInt stride, c;        // Off: linear(offset)'s stride and constant
    bool operator==(const ClassStep& o) const {
        return kind == o.kind && bytes_key == o.bytes_key && stride == o.stride && c == o.c;
    }
};
struct SlotClass {
    Word256 root{};
    std::vector<ClassStep> steps;
    bool operator==(const SlotClass&) const = default;
};

class Regroup {
public:
    // the classes of the accesses, the variables of each class whose accesses
    // are all at known bits
    Regroup(const Accesses& accesses, Parser& parser);
    // the trace with its stores per variable (python Regroup.trace)
    Value trace(Value t);

private:
    static constexpr u32 NO_CLASS = ~u32(0);
    struct Store {
        u32 cls;
        i64 size, off;
        Value val, idx, line;
    };
    u32 class_id(const SlotClass& c);
    std::optional<u32> class_of(const Access& a) const noexcept;  // NO_CLASS: none
    bool has_fields(u32 id) const noexcept;
    std::optional<Store> store(Value line) const;
    std::vector<Value> run(std::span<const Value> lines);

    std::vector<SlotClass> classes_;
    std::vector<std::vector<RootAccess>> accs_;  // per class: (size, off, written)
    std::vector<std::vector<Range>> fields_;     // per class with fields
    std::vector<u32> has_fields_;
    Memo<Key3, u32> cls_;  // access -> class + 1 (NO_CLASS + 1 = 0: none... see class_of)
    Memo<Value, Value> memo_;
};

}  // namespace pan::storage::detail
