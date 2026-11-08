// The free-memory floors along a walk of a trace (docs/alloc-floor.md, part
// 1): for a word at a constant address A that the code writes, an
// expression F of values available at the point with word(mem[A]) >=
// word(F) on every run reaching it. They live in the path facts
// (alg::FactKind::Floor), where the decisions about positions read them
// (alg::floored: mem[A] as F + d, d >= 0). Nothing here presumes what the
// word is for: no compiler's conventions, only the trace's writes.
//
// The walks that keep path facts (the forward memory pass, the loops' copy
// conversion) move them with these, so they can't disagree:
//  - floor_transfer after each line;
//  - floor_join where an IF's branches meet;
//  - floor_loop at a loop's head.
// Soundness, by induction on the trace: a floor is only made equal to a
// value the word was given (or a value proven below it); it is kept only
// across lines that provably don't change the word nor what the floor
// reads; at a join it is lowered to a value proven at most both branches'.
#pragma once

#include "algebra/facts.hpp"
#include "core/value.hpp"

namespace pan::simplify {

// The facts after `line` ran (its reads as the line has them, evaluated
// before it): the floors it may change dropped, a word written at a
// constant address given its new floor, a variable set to a floored word
// (plus what it adds) the floor of that (_12 = mem[64]: _12 >= F, for as
// long as _12 and what F reads stay); the other facts as they are (the
// caller forgets those).
alg::Facts floor_transfer(const alg::Facts& facts, Value line);

// Where two paths meet (an IF whose branches both go on): `into` with the
// floors that hold on both, each the first of F_then, F_else, F_before that
// is proven at most both branches' floors (alg::le, Top::Memory, each
// branch's facts); `into`'s own floors dropped first.
alg::Facts floor_join(const alg::Facts& into, const alg::Facts& before, const alg::Facts& then_facts,
                      const alg::Facts& else_facts);

// At the head of a loop (WHILE, LABEL, LOOP_PATH), for every iteration: the
// floors none of its iterations may change on the paths that go on (its
// summary's cont_writes, decided with the floors before it) - they hold at
// the head, throughout those paths, and after the loop. The other facts
// must hold in every iteration (what the loop may change forgotten first).
alg::Facts floor_loop(const alg::Facts& facts, Value loop_line);
// The same over every path of the loop, those that end in it too (its
// summary's mem_writes): the floors that hold at every point of the loop.
alg::Facts floor_loop_all(const alg::Facts& facts, Value loop_line);
// The head's floors (floor_loop's, or floor_loop_all's) with those of the
// variables the loop's body sets - each at least its floor wherever the
// iteration set it, none read before it's set, the floor made of what the
// loop doesn't change: for the decisions about what the loop's lines write
// (its summary, whose ranges read them after they're set), not past it.
alg::Facts floor_loop_inside(const alg::Facts& facts, Value loop_line, bool all_paths = false);

// The floors that hold at every point of `line` (before it and within it):
// the decisions about what a compound line (an IF, a loop) writes - its
// summary - are made with them. A plain line's are the facts' (it reads
// before it writes); a WHILE's floor_loop_all's; an IF's those none of its
// writes may change (a TRACE's alike); none for a LABEL or a LOOP_PATH.
alg::Facts floors_through(const alg::Facts& facts, Value line);

// The floors after `v` (a line, or a TRACE / LIST of lines) ran from facts:
// floor_transfer line by line, an IF's branches walked and joined (one that
// ends left out), a loop's head floors after it (floor_loop). The facts
// other than floors as given; they must hold before `v`, and serve its
// first line only: an IF's branches are walked with the floors alone (no
// line forgets the others here).
alg::Facts floor_walk(const alg::Facts& facts, Value v);

// base with its floors replaced by those of src
alg::Facts floors_from(const alg::Facts& base, const alg::Facts& src);

// The facts but the conditions `line` may change (what they read: python's
// forget, by the effect summaries); the other facts as they are. Remembered
// per line and facts (the walks of a loop's body meet the same ones).
alg::Facts kept_conditions(const alg::Facts& facts, Value line);

// The words whose floors may decide something in a pass over `trace` (a
// function's): floored() reads a word's floor only where an expression
// reads the word, and the walks decide about the trace's expressions (and
// floors made of them) - so while the scope lives, floors are made only for
// the words the trace reads at a constant address (fewer facts: as sound).
// Outside every scope (the tests), every word's.
class FloorScope {
public:
    explicit FloorScope(Value trace);
    ~FloorScope();
    FloorScope(const FloorScope&) = delete;
    FloorScope& operator=(const FloorScope&) = delete;
};

}  // namespace pan::simplify
