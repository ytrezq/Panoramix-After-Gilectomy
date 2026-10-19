// The check of the printed accesses (lot 9 only; check.cpp).
#pragma once

#include <memory>
#include <optional>
#include <vector>

#include "algebra/eval.hpp"
#include "storage/internal.hpp"
#include "storage/storage.hpp"

namespace pan::storage::detail {

// A world of random values for the symbols a slot is computed from: the
// words and bytes of expressions (storage::Eval) by python's rules (ev, evb).
class World final : public Eval, public alg::Env {
public:
    explicit World(u64 seed);
    ~World();
    World(const World&) = delete;
    World& operator=(const World&) = delete;

    Word256 word(Value e) override;
    void bytes(Value e, std::vector<u8>& out) override;
    std::optional<Word256> value(Value v, alg::Evaluator& ev) override;

private:
    Word256 sym(Value v) const noexcept;
    void random_bytes(Value v, std::vector<u8>& out) const;
    u64 seed_;
    alg::Evaluator ev_;
};

// python's four worlds (seeds 0 to 3), kept for the whole analysis
class Worlds {
public:
    Worlds();
    ~Worlds();
    // python checks(): f reads as the access a, in every world
    bool check(const StorageLayout& layout, Value f, const Access& a);
    u64 proven() const noexcept { return proven_; }    // by the linear forms
    u64 checked() const noexcept { return checked_; }  // by the worlds

private:
    std::vector<std::unique_ptr<World>> w_;
    u64 proven_ = 0, checked_ = 0;
};

}  // namespace pan::storage::detail
