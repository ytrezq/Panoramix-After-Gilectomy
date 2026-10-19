// The simplifier's own helpers, shared by its files (not a public API).
#pragma once

#include <optional>
#include <span>

#include "core/base.hpp"
#include "core/context.hpp"
#include "core/memo.hpp"
#include "core/smallvec.hpp"
#include "core/value.hpp"

namespace pan::simplify {

// ---- expressions (exp.cpp) ------------------------------------------------------------

// where an expression stands: a word, a byte element (bytes: its width
// explicit), or either (a SIZED's or a SETMEM's value: a word is its low
// bytes, bytes are themselves)
enum class Pos : u8 { Word, Bytes, Any };
// the position of operand i of an expression or a line of op
Pos operand_pos(Op op, u32 i, u32 n);
Value simplify_word(Value e);
Value simplify_bytes(Value e);
Value simplify_at(Value e, Pos pos);
// x = MUL(c, y) zero exactly when y is: c odd (a bijection mod 2^256), or y
// below 2^(256 - the trailing zeros of c) - y then; nullopt otherwise
std::optional<Value> same_truth_factor(Value x);

// ---- lines (lines.cpp) ----------------------------------------------------------------

// what an operand of a line is
enum class Arg : u8 {
    Expr,     // an expression (word or bytes: operand_pos)
    Trace,    // a TRACE (IF's branches, WHILE's body)
    Setvars,  // a LIST of SETVAR lines (WHILE CONTINUE LABEL GOTO)
    Values,   // a LIST of word expressions (INTERNAL's arguments, LEAVE's values, ASM's stack)
    Raw,      // left as it is (ids, names, pcs, reasons)
};
Arg arg_kind(Op op, u32 i);

// the line with its expressions simplified (and the traces in it); NIL: it
// does nothing (dropped)
Value simplify_line(Value line);

// a line rebuilt with f applied to each expression operand (Expr operands,
// Setvars' values, Values' items): f(Value expr, Pos pos) -> Value; traces
// left to the caller (as they are). The line itself when nothing changes.
template <class F>
Value map_line_exprs(Value line, F&& f);

// what the run of simplify_trace says of its trace
struct RunFlags {
    bool msize = false;    // the trace reads MSIZE: memory reads and writes stay where they are
    bool dubious = false;  // SimplifyOptions::dubious
    Value entry_lines;     // SimplifyOptions::entry_lines
    bool fresh = false;    // SimplifyOptions::fresh_memory
};
RunFlags& run_flags();

// python exp_size (the tree's leaves and heads), counted up to cap
u32 exp_size(Value e, u32 cap);

// a trace from lines
Value make_trace(std::span<const Value> lines);

// e with the names from[i] replaced by to[i] (all at once)
Value substitute(Value e, std::span<const Value> from, std::span<const Value> to);
// the variables a line assigns and their values (all at once): a SETVAR's,
// the setvars of a CONTINUE / GOTO / LABEL (the WHILE's: setvars_of(l[3]));
// false when it assigns none that way
bool assignments(Value line, SmallVec<Value, 8>& names, SmallVec<Value, 8>& values);
void setvars_of(Value setvars, SmallVec<Value, 8>& names, SmallVec<Value, 8>& values);

// ---- template ---------------------------------------------------------------------------

Value mk_like_checked(Value orig, std::span<const Value> args);

template <class F>
Value map_line_exprs(Value line, F&& f) {
    if (!line.is_expr()) return line;
    const Op op = line.op();
    SmallVec<Value, 8> args;
    bool changed = false;
    for (u32 i = 0; i < line.size(); ++i) {
        Value a = line[i];
        Value n = a;
        switch (arg_kind(op, i)) {
            case Arg::Expr: n = f(a, operand_pos(op, i, line.size())); break;
            case Arg::Setvars:
            case Arg::Values: {
                if (!a.is_list()) break;
                SmallVec<Value, 8> items;
                bool ch = false;
                for (Value x : a.args()) {
                    Value y = x;
                    if (x.is(Op::SETVAR, 2)) {
                        Value e = f(x[1], Pos::Word);
                        if (e != x[1]) y = mk(Op::SETVAR, x[0], e);
                    } else if (arg_kind(op, i) == Arg::Values) {
                        y = f(x, Pos::Word);
                    }
                    if (y != x) ch = true;
                    items.push_back(y);
                }
                if (ch) n = mk_like(a, items.span());
                break;
            }
            case Arg::Trace:
            case Arg::Raw: break;
        }
        if (n != a) changed = true;
        args.push_back(n);
    }
    return changed ? mk_like_checked(line, args.span()) : line;
}

}  // namespace pan::simplify
