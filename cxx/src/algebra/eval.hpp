// Concrete evaluation of expressions (python arithmetic.eval, runtrace's
// word expressions): the EVM value of an expression, a Word256.
//
//  - eval_const(v): the value of an expression made only of constants and
//    pure operations (memoized per context); nullopt when it reads anything.
//  - Evaluator / eval(v, env): any expression, the environment giving the
//    value of what isn't a pure operation of its operands (leaves, names,
//    calldataload, mem, storage, sha3...).
//  - eval_op: one operation on concrete words - the single definition of
//    the decompiler's word operations (mask_shl, bool, le, ge, max...) that
//    the constructors (construct.hpp) and the trace machine (lot 11) share.
//
// Semantics (ir.md 4.3): every operation is on words, mod 2^256; an int
// Value is the word it is mod 2^256 (-1 is 2^256 - 1); True/False are 1/0.
// MASK_SHL(size, off, shl, x): see mask_shl_word.
#pragma once

#include <optional>
#include <span>

#include "core/evmint.hpp"
#include "core/memo.hpp"
#include "core/value.hpp"

namespace pan::alg {

// ---- ints as words ----------------------------------------------------------

// the representative of an int Value mod 2^256 in [0, 2^256) (a standalone
// constant), and in [-2^255, 2^255) (a constant or coefficient in a sum)
Value word_int(Value int_value);
Value signed_int(Value int_value);
// an int Value (or True/False) mod 2^256 as a word, and back (on cx()):
// no GMP allocation (the big ints' limbs are read and written in place)
Word256 word_of(Value int_value) noexcept;
Value value_of(const Word256& w);         // in [0, 2^256)
Value signed_value_of(const Word256& w);  // in [-2^255, 2^255)
// x as a signed 256-bit integer clamped to [-4096, 4096]: the reading of a
// mask's size/offset/shift (fields past +-4096 behave as +-4096)
i64 clamp_field(const Word256& x) noexcept;

// ---- one operation on words -------------------------------------------------

// whether eval_op computes op: its value is a function of its operands'
// values only (ADD..CLZ but SHA3, the decompiler's MASK_SHL BOOL LE GE SLE
// SGE MAX MIN LAND LOR)
bool is_pure(Op op) noexcept;

// op on concrete operands (the IR's operand order: EVM stack order for the
// EVM ops - SHL(shift, x), BYTE(i, x), SIGNEXTEND(b, x), SUB(a, b) = a - b);
// nullopt when !is_pure(op) or the operand count is wrong
std::optional<Word256> eval_op(Op op, std::span<const Word256> args) noexcept;

// MASK_SHL on words: size, off, shl read as signed (clamp_field), then
//   off < 0: size += off, off = 0 (no bits below 0);
//   v = x & bits [off, off + size) (none when size <= 0);
//   |shl| >= 256: 0; else v << shl (shl >= 0) or v >> -shl, mod 2^256.
Word256 mask_shl_word(const Word256& size, const Word256& off, const Word256& shl, const Word256& x) noexcept;
Word256 mask_shl_word(i64 size, i64 off, i64 shl, const Word256& x) noexcept;
// the bits [off, off + size) of a word set (python mask_to_int, clipped to the word)
Word256 mask_word(i64 size, i64 off) noexcept;

// ---- constant expressions ---------------------------------------------------

// the value of v when it is made only of ints, True/False and pure ops
// (memoized per context); nullopt otherwise
std::optional<Word256> eval_const(Value v);

// ---- any expression, with an environment ---------------------------------------

class Evaluator;

// What the evaluator can't compute: a leaf, a name, a node whose op isn't
// pure (calldataload, mem, storage, sha3, call results...), a MASK_SHL of a
// value wider than a word (masks.hpp may_be_wide: its bits past 256 are no
// Word256's). Its operands through ev(...). nullopt: unknown (the
// evaluation fails).
class Env {
public:
    virtual std::optional<Word256> value(Value v, Evaluator& ev) = 0;

protected:
    ~Env() = default;
};

// Evaluates expressions against an env, each distinct node once (a memo per
// evaluator: hash-consed DAGs never blow up); forget() when the env changes.
class Evaluator {
public:
    explicit Evaluator(Env& env) : env_(env) {}
    Evaluator(const Evaluator&) = delete;
    Evaluator& operator=(const Evaluator&) = delete;

    // Unsupported when the env doesn't know something v reads
    Word256 operator()(Value v);
    // nullopt instead
    std::optional<Word256> try_eval(Value v);
    void forget() noexcept { memo_.clear(); }
    Env& env() noexcept { return env_; }

private:
    struct Slot {
        Word256 w;
        u32 state;  // 0 never (absent), 1 known, 2 unknown
    };
    std::optional<Word256> run(Value v);
    Env& env_;
    Memo<Value, Slot> memo_;
};

// one evaluation (Unsupported when the env doesn't know something v reads)
Word256 eval(Value v, Env& env);

// Values for testing: every leaf, name and non-pure node a word made from
// (seed, its structural hash) - the same in every context and run; one in
// four an edge value (0, 1, 2, 2^255, 2^256 - 1, 2^255 - 1, small, 2^k,
// 2^k - 1, 2^160 - 1...). Ints of non-pure nodes' operands are not looked at.
class RandomEnv final : public Env {
public:
    explicit RandomEnv(u64 seed) noexcept : seed_(seed) {}
    std::optional<Word256> value(Value v, Evaluator& ev) override;
    // a word for (seed, k): what value() gives a value of hash k
    static Word256 word_for(u64 seed, u64 k) noexcept;

private:
    u64 seed_;
};

// Values given one by one (tests): set(v, w); anything else unknown, or from
// the fallback env when one is given.
class MapEnv final : public Env {
public:
    explicit MapEnv(Env* fallback = nullptr) noexcept : fallback_(fallback) {}
    void set(Value v, const Word256& w) { map_.put(v, w); }
    std::optional<Word256> value(Value v, Evaluator& ev) override;

private:
    Memo<Value, Word256> map_;
    Env* fallback_;
};

}  // namespace pan::alg
