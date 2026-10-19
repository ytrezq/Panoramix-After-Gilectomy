// Effect summaries (effects.hpp).
#include "simplify/effects.hpp"

#include <deque>
#include <memory_resource>

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/linear.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/evmint.hpp"
#include "core/intops.hpp"
#include "core/memo.hpp"
#include "core/order.hpp"
#include "mem/memory.hpp"

namespace pan::simplify {

namespace {

const EffectSummary kEmpty{};

struct EffectsState final : ModuleState {
    Memo<Value, u32> index;  // node -> 1 + its position in sums
    std::pmr::deque<EffectSummary> sums;
    EffectsState() : sums(cx().budget.resource()) {}
    // summaries are structural: nothing to forget when the algebra changes
};

// ---- places: sorted (compare()) lists without duplicates ------------------------

using Places = SmallVec<Value, 16>;

// a and b merged (both sorted); false when past kMaxPlaces
bool merge_places(Value a, Value b, Places& out) {
    out.clear();
    std::span<const Value> x = a.nil() ? std::span<const Value>{} : a.args();
    std::span<const Value> y = b.nil() ? std::span<const Value>{} : b.args();
    usize i = 0, j = 0;
    while (i < x.size() || j < y.size()) {
        Value v;
        if (j == y.size()) {
            v = x[i++];
        } else if (i == x.size()) {
            v = y[j++];
        } else {
            int c = compare(x[i], y[j]);
            if (c < 0) {
                v = x[i++];
            } else if (c > 0) {
                v = y[j++];
            } else {
                v = x[i++];
                j++;
            }
        }
        out.push_back(v);
        if (out.size() > kMaxPlaces) return false;
    }
    return true;
}

// the union of the places of class c of a and b into r (with the any bits
// already merged into r's *_any): r's list, or the any bit past the cap
void union_places(Value a, Value b, u32 c, u32& any, Value& out) {
    if (any & c) {
        out = Value();
        return;
    }
    if (a.nil()) {
        out = b;
        return;
    }
    if (b.nil() || a == b) {
        out = a;
        return;
    }
    Places p;
    if (!merge_places(a, b, p)) {
        any |= c;
        out = Value();
        return;
    }
    out = mk_list(p.span());
}

// one place added to a summary's list of class c
void add_place(EffectSummary& s, bool write, u32 c, Value place) {
    u32& any = write ? s.writes_any : s.reads_any;
    (write ? s.writes : s.reads) |= c;
    if (any & c) return;
    Value* list = nullptr;
    switch (c) {
        case S_MEM: list = write ? &s.mem_writes : &s.mem_reads; break;
        case S_STORAGE: list = write ? &s.stor_writes : &s.stor_reads; break;
        case S_TRANSIENT: list = write ? &s.tr_writes : &s.tr_reads; break;
        case S_VARS: list = write ? &s.var_writes : &s.var_reads; break;
        case S_CALLRES: list = write ? &s.call_writes : &s.call_reads; break;
        default: return;
    }
    Value one = mk_list({place});
    union_places(*list, one, c, any, *list);
}

void add_any(EffectSummary& s, bool write, u32 classes) {
    if (write) {
        s.writes |= classes;
        s.writes_any |= classes;
    } else {
        s.reads |= classes;
        s.reads_any |= classes;
    }
    // the lists of the classes now anywhere are dropped
    auto drop = [&](u32 c, Value& r, Value& w) {
        if (classes & c) (write ? w : r) = Value();
    };
    drop(S_MEM, s.mem_reads, s.mem_writes);
    drop(S_STORAGE, s.stor_reads, s.stor_writes);
    drop(S_TRANSIENT, s.tr_reads, s.tr_writes);
    drop(S_VARS, s.var_reads, s.var_writes);
    drop(S_CALLRES, s.call_reads, s.call_writes);
}

// ---- the summaries ------------------------------------------------------------------

EffectSummary compute(Value v);

const EffectSummary& memo_summary(Value v) {
    EffectsState& st = cx().state<EffectsState>();
    if (const u32* i = st.index.find(v)) return st.sums[*i - 1];
    EffectSummary s = compute(v);
    st.sums.push_back(s);
    st.index.put(v, u32(st.sums.size()));
    return st.sums.back();
}

// the summary of v's operands from `from` on, in sequence (expression reads)
EffectSummary operands(Value v, u32 from = 0) {
    EffectSummary s;
    if (!v.is_expr() && !v.is_list()) return s;
    for (u32 i = from; i < v.size(); ++i) {
        const EffectSummary& a = summary(v[i]);
        if (a.reads | a.writes | a.control) s = combine(s, a, true);
    }
    return s;
}

EffectSummary leaf_summary(Value v) {
    EffectSummary s;
    const Op op = v.op();
    switch (op) {
        case Op::MSIZE: s.reads = S_MSIZE; break;
        case Op::GAS: s.reads = S_GAS; break;
        case Op::CALL_SUCCESS:
        case Op::CREATE_ADDRESS:
            add_place(s, false, S_CALLRES, Value::small(i64(v.leaf_n())));
            break;
        case Op::RETURNDATASIZE:
            // id 0: before any call of the run, the constant 0
            if (v.leaf_n() != 0) add_place(s, false, S_CALLRES, Value::small(i64(v.leaf_n())));
            break;
        case Op::SELFBALANCE: s.reads = S_ACCOUNT; break;
        case Op::CALLDATASIZE: s.reads = S_CALLDATA; break;
        default:
            if (has(op, R_CTX)) s.reads = S_CTX;
            break;
    }
    return s;
}

EffectSummary name_summary(Value v) {
    EffectSummary s;
    switch (v.name_kind()) {
        case NameKind::TMP:
        case NameKind::LOOP:
        case NameKind::MSIZE_VAR:
        case NameKind::PRECOMPILE:
        case NameKind::SAFEMATH_PARAM:
            add_place(s, false, S_VARS, v);
            break;
        case NameKind::PARAM: s.reads = S_CALLDATA; break;
        default: break;
    }
    return s;
}

// the writes of a LIST of SETVAR lines (WHILE, CONTINUE, LABEL, GOTO) and their reads
EffectSummary setvars_summary(Value list) {
    EffectSummary s;
    if (!list.is_list()) return s;
    for (Value line : list.args()) {
        poll();
        s = combine(s, summary(line), true);
    }
    return s;
}

// the region of a slot's bits: a LENGTH(key) slot is the word at key (the
// length decoded from it), a LOC(n) the slot n
Value region(Value size, Value off, Value slot) {
    if (slot.is(Op::LENGTH, 1)) return mk(Op::STORAGE, Value::small(256), Value::small(0), region(Value::small(256), Value::small(0), slot[0])[2]);
    if (slot.is(Op::LOC, 1)) slot = slot[0];
    return mk(Op::STORAGE, size, off, slot);
}

EffectSummary storage_region_read(Value region, Value operands_of) {
    EffectSummary s = operands(operands_of);
    add_place(s, false, S_STORAGE, region);
    return s;
}

// what a line that touches memory does to msize
void touch(EffectSummary& s) {
    if ((s.reads | s.writes) & S_MEM) s.writes |= S_MSIZE;
}

EffectSummary expr_summary(Value v) {
    const Op op = v.op();
    EffectSummary s;
    switch (op) {
        // ---- expressions ----
        case Op::MEM: {
            s = operands(v);
            if (v[0].is(Op::RANGE, 2))
                add_place(s, false, S_MEM, v[0]);
            else
                add_any(s, false, S_MEM);
            return s;
        }
        case Op::STORAGE: return storage_region_read(region(v[0], v[1], v[2]), v);
        case Op::LENGTH: return storage_region_read(region(Value::small(256), Value::small(0), v[0]), v);
        case Op::SBYTES:
        case Op::SALL:
        case Op::ST:
            s = operands(v);
            add_any(s, false, S_STORAGE);
            return s;
        case Op::TLOAD:
            s = operands(v);
            add_place(s, false, S_TRANSIENT, v[0]);
            return s;
        case Op::BALANCE:
        case Op::EXTCODESIZE:
        case Op::EXTCODEHASH:
        case Op::EXTCODE_BYTES:
            s = operands(v);
            s.reads |= S_ACCOUNT;
            return s;
        case Op::BLOCKHASH:
        case Op::BLOBHASH:
            s = operands(v);
            s.reads |= S_CTX;
            return s;
        case Op::CALLDATALOAD:
        case Op::CALLDATA_BYTES:
            s = operands(v);
            s.reads |= S_CALLDATA;
            return s;
        case Op::RETURNDATA_BYTES: {
            s = operands(v, 1);
            if (v[0].is_small() && v[0].small_val() == 0) return s;
            if (v[0].is_small())
                add_place(s, false, S_CALLRES, v[0]);
            else
                add_any(s, false, S_CALLRES);
            return s;
        }
        case Op::SAFEMATH:
            s = operands(v);
            s.control |= C_FAILS;
            return s;

        // ---- lines ----
        case Op::SETVAR:
            s = operands(v, 1);
            add_place(s, true, S_VARS, v[0]);
            return s;
        case Op::SETMEM:
            s = operands(v);
            if (v[0].is(Op::RANGE, 2))
                add_place(s, true, S_MEM, v[0]);
            else
                add_any(s, true, S_MEM);
            touch(s);
            return s;
        case Op::STORE: {
            s = operands(v);
            add_place(s, true, S_STORAGE, region(v[0], v[1], v[2]));
            touch(s);
            return s;
        }
        case Op::SET:
            s = operands(v);
            add_any(s, true, S_STORAGE);
            touch(s);
            return s;
        case Op::TSTORE:
            s = operands(v);
            add_place(s, true, S_TRANSIENT, v[0]);
            touch(s);
            return s;
        case Op::LOG0:
        case Op::LOG1:
        case Op::LOG2:
        case Op::LOG3:
        case Op::LOG4:
            s = operands(v);
            s.writes |= S_LOG;
            touch(s);
            return s;
        case Op::CALL:
        case Op::CALLCODE:
        case Op::DELEGATECALL:
        case Op::CREATE:
        case Op::CREATE2:
            s = operands(v, 1);
            add_any(s, true, S_STORAGE | S_TRANSIENT);
            s.writes |= S_ACCOUNT | S_LOG;
            if (v[0].is_small())
                add_place(s, true, S_CALLRES, v[0]);
            else
                add_any(s, true, S_CALLRES);
            touch(s);
            return s;
        case Op::STATICCALL:
            s = operands(v, 1);
            if (v[0].is_small())
                add_place(s, true, S_CALLRES, v[0]);
            else
                add_any(s, true, S_CALLRES);
            touch(s);
            return s;
        case Op::PRECOMPILED:
            s = operands(v, 2);
            if (v[0].is_small())
                add_place(s, true, S_CALLRES, v[0]);
            else
                add_any(s, true, S_CALLRES);
            if (v[1].is_name()) add_place(s, true, S_VARS, v[1]);
            touch(s);
            return s;
        case Op::SELFDESTRUCT:
            s = operands(v);
            s.writes |= S_ACCOUNT;
            s.control |= C_HALTS | C_ENDS;
            return s;
        case Op::INTERNAL: {
            s = operands(v[1]);
            add_any(s, false, S_MEM | S_STORAGE | S_TRANSIENT | S_CALLRES);
            s.reads |= S_ACCOUNT | S_GAS | S_CALLDATA | S_CTX | S_MSIZE;
            add_any(s, true, S_MEM | S_STORAGE | S_TRANSIENT | S_CALLRES);
            s.writes |= S_ACCOUNT | S_LOG | S_MSIZE;
            if (Value results = v[2]; results.is_list())
                for (Value n : results.args())
                    if (n.is_name()) add_place(s, true, S_VARS, n);
            s.control |= C_CALLS_OUT;
            return s;
        }
        case Op::LEAVE:
            s = operands(v);
            add_any(s, false, S_MEM);  // the caller goes on with the memory
            s.control |= C_LEAVES | C_ENDS;
            touch(s);
            return s;
        case Op::UNDEFINED:
            s.control |= C_UNDEFINED | C_ENDS;
            return s;
        case Op::STOP:
            s.control |= C_HALTS | C_ENDS;
            return s;
        case Op::RETURN:
            s = operands(v);
            s.control |= C_HALTS | C_ENDS;
            touch(s);
            return s;
        case Op::REVERT:
            s = operands(v);
            s.control |= C_FAILS | C_ENDS;
            touch(s);
            return s;
        case Op::INVALID:
            s.control |= C_FAILS | C_ENDS;
            return s;
        case Op::IF:
        case Op::MERGED_IF: {
            s = summary(v[0]);
            EffectSummary t = summary(v[1]);
            EffectSummary e = v.size() > 2 ? summary(v[2]) : kEmpty;
            // an empty branch goes on: it doesn't end
            s = combine(s, combine(t, e, false), true);
            touch(s);
            return s;
        }
        case Op::WHILE: {
            // the setvars, then the condition and the body zero times or more
            s = setvars_summary(v[3]);
            EffectSummary body = combine(summary(v[0]), summary(v[1]), true);
            body.control &= ~C_ENDS;
            s = combine(s, body, true);
            s.control &= ~C_ENDS;
            touch(s);
            return s;
        }
        case Op::CONTINUE:
        case Op::GOTO:
            s = setvars_summary(v[1]);
            s.control |= C_JUMPS | C_ENDS;
            return s;
        case Op::LABEL:
            s = setvars_summary(v[1]);
            s.control |= C_JUMPS;
            s.control &= ~C_ENDS;
            return s;
        case Op::BREAK:
            s.control |= C_JUMPS | C_ENDS;
            return s;
        case Op::REQUIRE:
        case Op::ASSERT:
            s = operands(v);
            s.control |= C_FAILS;
            touch(s);
            return s;
        case Op::LOOP_PATH:
            s = summary(v[0]);
            s.control |= C_JUMPS;
            return s;
        case Op::ASM:
            // a --verbose comment line: what its stack reads
            s = operands(v);
            return s;
        default:
            s = operands(v);
            if (has(op, LINE)) touch(s);
            return s;
    }
}

EffectSummary compute(Value v) {
    check_stack();
    if (v.is_leaf()) return leaf_summary(v);
    if (v.is_name()) return name_summary(v);
    if (v.is_list()) {
        // a trace: its lines in order; a list of values: their reads
        EffectSummary s;
        for (Value x : v.args()) {
            poll();
            const EffectSummary& a = summary(x);
            if (a.reads | a.writes | a.control) s = combine(s, a, true);
        }
        return s;
    }
    if (v.is_expr()) return expr_summary(v);
    return EffectSummary{};
}

// ---- comparisons of places ------------------------------------------------------------

bool is_hash(Value x) {
    if (x.is(Op::SHA3)) return true;
    if (x.is(Op::ADD))
        for (Value t : x.args())
            if (t.is(Op::SHA3)) return true;
    return false;
}

// the bits [lo, hi) a region covers; nullopt: all of them (or unknown)
struct Bits {
    i64 lo, hi;
};
std::optional<Bits> region_bits(Value r) {
    if (!r.is(Op::STORAGE, 3)) return std::nullopt;
    if (!r[0].is_small() || !r[1].is_small()) return std::nullopt;
    i64 size = r[0].small_val(), off = r[1].small_val();
    if (size <= 0 || off < 0 || off + size > 256) return std::nullopt;
    return Bits{off, off + size};
}

Tri slots_may_alias(Value a, Value b) {
    if (a == b) return Tri::True;
    if (a.is_int() && b.is_int()) return tri(alg::word_int(a) == alg::word_int(b));
    // a slot of a mapping or a dynamic array (a hash) isn't a small one
    for (int k = 0; k < 2; ++k) {
        Value x = k ? b : a, y = k ? a : b;
        if (x.is_small() && x.small_val() >= 0 && is_hash(y)) return Tri::False;
    }
    // slots a constant apart
    if (auto d = alg::const_diff(a, b)) return tri(int_sign(*d) == 0);
    return Tri::None;
}

bool mem_may_overlap(Value w, Value r) { return mem::overlaps(w, r) != Tri::False; }

bool key_may_alias(Value a, Value b) {
    if (a == b) return true;
    if (a.is_int() && b.is_int()) return alg::word_int(a) == alg::word_int(b);
    if (auto d = alg::const_diff(a, b)) return int_sign(*d) == 0;
    return true;
}

// may a place of class c in xs meet one in ys
bool lists_meet(u32 c, Value xs, Value ys) {
    if (xs.nil() || ys.nil()) return false;
    for (Value x : xs.args())
        for (Value y : ys.args()) {
            poll();
            switch (c) {
                case S_MEM:
                    if (mem_may_overlap(x, y)) return true;
                    break;
                case S_STORAGE:
                    if (storage_may_alias(x, y) != Tri::False) return true;
                    break;
                case S_TRANSIENT:
                    if (key_may_alias(x, y)) return true;
                    break;
                default:  // vars, call ids: the same place
                    if (x == y) return true;
                    break;
            }
        }
    return false;
}

Value w_list(const EffectSummary& s, u32 c) {
    switch (c) {
        case S_MEM: return s.mem_writes;
        case S_STORAGE: return s.stor_writes;
        case S_TRANSIENT: return s.tr_writes;
        case S_VARS: return s.var_writes;
        case S_CALLRES: return s.call_writes;
        default: return Value();
    }
}
Value r_list(const EffectSummary& s, u32 c) {
    switch (c) {
        case S_MEM: return s.mem_reads;
        case S_STORAGE: return s.stor_reads;
        case S_TRANSIENT: return s.tr_reads;
        case S_VARS: return s.var_reads;
        case S_CALLRES: return s.call_reads;
        default: return Value();
    }
}

// may places of `a` (classes ca, lists la) meet places of `b`
bool classes_meet(u32 ca, u32 any_a, bool a_writes, const EffectSummary& a, u32 cb, u32 any_b, bool b_writes,
                  const EffectSummary& b) {
    u32 common = ca & cb;
    if (!common) return false;
    // the classes without places: any
    if (common & ~S_PLACED) return true;
    for (u32 c : {S_MEM, S_STORAGE, S_TRANSIENT, S_VARS, S_CALLRES}) {
        if (!(common & c)) continue;
        if ((any_a | any_b) & c) return true;
        if (lists_meet(c, a_writes ? w_list(a, c) : r_list(a, c), b_writes ? w_list(b, c) : r_list(b, c)))
            return true;
    }
    return false;
}

}  // namespace

// ---- the API ------------------------------------------------------------------------------

const EffectSummary& summary(Value v) {
    if (v.nil() || v.is_int() || v.is_bool() || v.is_none() || v.is_bytes()) return kEmpty;
    return memo_summary(v);
}

EffectSummary combine(const EffectSummary& a, const EffectSummary& b, bool seq) {
    EffectSummary r;
    r.reads = a.reads | b.reads;
    r.writes = a.writes | b.writes;
    r.reads_any = a.reads_any | b.reads_any;
    r.writes_any = a.writes_any | b.writes_any;
    u32 ends = seq ? ((a.control | b.control) & C_ENDS) : (a.control & b.control & C_ENDS);
    r.control = ((a.control | b.control) & ~C_ENDS) | ends;
    union_places(a.mem_reads, b.mem_reads, S_MEM, r.reads_any, r.mem_reads);
    union_places(a.mem_writes, b.mem_writes, S_MEM, r.writes_any, r.mem_writes);
    union_places(a.stor_reads, b.stor_reads, S_STORAGE, r.reads_any, r.stor_reads);
    union_places(a.stor_writes, b.stor_writes, S_STORAGE, r.writes_any, r.stor_writes);
    union_places(a.tr_reads, b.tr_reads, S_TRANSIENT, r.reads_any, r.tr_reads);
    union_places(a.tr_writes, b.tr_writes, S_TRANSIENT, r.writes_any, r.tr_writes);
    union_places(a.var_reads, b.var_reads, S_VARS, r.reads_any, r.var_reads);
    union_places(a.var_writes, b.var_writes, S_VARS, r.writes_any, r.var_writes);
    union_places(a.call_reads, b.call_reads, S_CALLRES, r.reads_any, r.call_reads);
    union_places(a.call_writes, b.call_writes, S_CALLRES, r.writes_any, r.call_writes);
    return r;
}

bool changes(const EffectSummary& w, const EffectSummary& r) {
    return classes_meet(w.writes, w.writes_any, true, w, r.reads, r.reads_any, false, r);
}

bool affects(const EffectSummary& line, Value expr) {
    if (!line.writes) return false;
    const EffectSummary& e = summary(expr);
    if (!(line.writes & e.reads)) return false;
    return changes(line, e);
}

bool affects(Value line, Value expr) { return affects(summary(line), expr); }

bool independent(Value a, Value b) {
    const EffectSummary& sa = summary(a);
    const EffectSummary& sb = summary(b);
    if ((sa.control | sb.control) & C_MAY_END) return false;
    if (changes(sa, sb) || changes(sb, sa)) return false;
    // both write the same place: their order is seen
    return !classes_meet(sa.writes, sa.writes_any, true, sa, sb.writes, sb.writes_any, true, sb);
}

Tri storage_may_alias(Value a, Value b) {
    Value sa = a.is(Op::STORAGE, 3) ? a[2] : a;
    Value sb = b.is(Op::STORAGE, 3) ? b[2] : b;
    Tri t = slots_may_alias(sa, sb);
    if (t != Tri::True) return t;
    // the same slot: fields that share no bit don't meet
    if (sa == sb || t == Tri::True) {
        auto ba = region_bits(a), bb = region_bits(b);
        if (ba && bb && (ba->hi <= bb->lo || bb->hi <= ba->lo)) return Tri::False;
    }
    return Tri::True;
}

}  // namespace pan::simplify
