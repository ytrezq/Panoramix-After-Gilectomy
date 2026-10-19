// Lot 6's own helpers, shared by its files (not a public API).
#pragma once

#include <optional>
#include <span>

#include "core/base.hpp"
#include "core/context.hpp"
#include "core/memo.hpp"
#include "core/smallvec.hpp"
#include "core/value.hpp"
#include "simplify/effects.hpp"

namespace pan::loops::detail {

// ---- what a trace does ------------------------------------------------------------------

// a GOTO or CONTINUE of the loop `id` somewhere in v (a line or a trace, any
// depth: IF branches, WHILE bodies)
bool has_jump_to(Value v, Value id);
// a path of the trace may get to its end (python whiles.falls_through): its
// last line may go on (an IF: one of its branches may; not a halt, LEAVE,
// UNDEFINED, GOTO, CONTINUE, BREAK)
bool falls_through(Value trace);
// the line may go on to the line after it
bool line_falls_through(Value line);
// every path through the branch ends in it (a halt, a failure...) and it
// holds no loop control: an IF with such a branch is a check on the way
bool is_check_branch(Value branch);

// the names of a LIST of SETVAR lines, and their values (in order)
void setvar_names(Value setvars, SmallVec<Value, 8>& out);
void setvar_values(Value setvars, SmallVec<Value, 8>& out);
// the value a LIST of SETVARs gives the name, NIL when it gives none
Value setvar_of(Value setvars, Value name);

// v reads the variable `name` (a SETVAR's target is not a read)
bool reads_name(Value v, Value name);
// v reads one of the names
bool reads_any(Value v, std::span<const Value> names);
// the lines of v (any depth) that set `name`: SETVAR lines and setvars of
// WHILE / CONTINUE / LABEL / GOTO, PRECOMPILED and INTERNAL results
bool sets_name(Value v, Value name);
// the nodes of v, counted up to cap
u32 node_count(Value v, u32 cap);

// ---- rewriting ---------------------------------------------------------------------------

// a name and what it becomes (SmallVec holds trivially copyable values)
struct NamePair {
    Value name, value;
};

// The reads of variables replaced by expressions, all at once (python
// replace_vars): SETVAR targets left as they are; the pure operations made
// over again through the algebra's constructors (normal forms), the rest
// with mk_like; lines keep their pcs. One memo per Subst.
class Subst {
public:
    Subst() = default;
    void add(Value name, Value value) { map_.push_back(NamePair{name, value}); }
    bool empty() const { return map_.empty(); }
    Value operator()(Value v);

private:
    const Value* find(Value name) const;
    SmallVec<NamePair, 8> map_;
    Memo<Value, Value> memo_;
};

// The names renamed everywhere: their reads and the places that set them
// (SETVAR targets, setvars, results). A rename of a name is the same name
// for every occurrence; lines keep their pcs.
class Renamer {
public:
    void add(Value from, Value to) { map_.push_back(NamePair{from, to}); }
    bool empty() const { return map_.empty(); }
    Value operator()(Value v);

private:
    SmallVec<NamePair, 4> map_;
    Memo<Value, Value> memo_;
};

// a new trace from lines
inline Value trace_of(std::span<const Value> lines) { return mk_trace(lines); }

// ---- what an iteration moves ----------------------------------------------------------------

// the loop's effects but its own variables' writes (what the induction
// accounts for); ok false when they can't be told apart (names anywhere)
simplify::EffectSummary but_vars(const simplify::EffectSummary& e, std::span<const Value> names, bool& ok);
// e with the loop's variables (names) replaced by the values setvars gives
// them (all at once; those it doesn't give left as they are)
Value at(Value e, std::span<const Value> names, Value setvars);
// what an expression made of the loop's variables and of what the loop
// doesn't change (others: but_vars' effects) moves by at a CONTINUE whose
// setvars these are: an int, when it moves by a constant
std::optional<Value> move_of(Value p, std::span<const Value> names, Value cont_setvars,
                             const simplify::EffectSummary& others);

}  // namespace pan::loops::detail
