// The symbolic VM's exploration (python VM.run): breadth first by rounds -
// run the nodes not run yet, find the loops (replace_loops), the recursive
// internal functions (replace_recursions), turn the loops into labels and
// gotos (continue_loops), merge the branches that meet again
// (merge_branches) - and the trace of the tree (make_trace).
#include <algorithm>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/platform.hpp"
#include "vm/vm_impl.hpp"

namespace pan::vm {

namespace {

Value small(i64 x) { return Value::small(x); }

bool is_jumpdest_int(const CodeMap& m, Value v) {
    return v.is_small() && v.small_val() >= 0 && m.is_jumpdest(u64(v.small_val()));
}

}  // namespace

// ---- the rounds ---------------------------------------------------------------------

bool Vm::should_quit() {
    if (quit_) return true;
    const u32 max_nodes = setup_.max_nodes ? setup_.max_nodes : limits::MAX_NODE_COUNT;
    if (node_count_ > max_nodes ||
        (node_count_ > limits::WIDE_NODE_COUNT && u64(16) * frontier_count_ > node_count_) ||
        (setup_.deadline_ns && platform::monotonic_ns() > setup_.deadline_ns))
        quit_ = true;
    return quit_;
}

void Vm::explore() {
    // python name_past: its own names past those of what it's given (the
    // dispatcher's, which another VM named)
    if (!setup_.given.nil()) {
        SmallVec<Value, 64> todo{setup_.given};
        while (!todo.empty()) {
            poll();
            Value v = todo.back();
            todo.pop_back();
            if (v.is_name()) {
                switch (v.name_kind()) {
                    case NameKind::TMP: counter_ = std::max(counter_, v.name_id()); break;
                    case NameKind::LOOP: next_loop_key_ = std::max(next_loop_key_, (v.name_id() >> 12) + 1); break;
                    case NameKind::PRECOMPILE: {
                        u32 a = v.name_id() >> 24, k = v.name_id() & 0xffffff;
                        u32 base = a == 3 ? 2 : a;
                        if (base < 9) precompile_count_[base] = std::max(precompile_count_[base], k);
                        break;
                    }
                    default: break;
                }
            }
            for (Value a : v.children()) todo.push_back(a);
        }
    }

    const u32 last_call = setup_.inside ? kAmbiguousCall : 0;
    NodeId func = new_node(setup_.start, true, setup_.stack, Value(true), setup_.known, last_call);
    root_ = new_node(setup_.start, true, setup_.stack, Value(true), setup_.known, last_call);
    {
        Node& r = nodes_[root_];
        r.jump = root_;
        r.dead = false;
        r.lines.assign(setup_.before.begin(), setup_.before.end());
        r.end = End::Jump;
        r.a = func;
    }
    set_prev(func, root_);

    dirty_ = true;
    for (u32 j = 0; j < limits::VM_ROUNDS; ++j) {
        for (u32 i = 0; i < limits::VM_ROUND_STEPS; ++i) {
            poll();
            refresh_frontier();
            expand_trace();
            replace_loops();
            replace_recursions();
            continue_loops();
            merge_branches();
            refresh_frontier();
            frontier_count_ = u32(frontier_.size());
            if (frontier_.empty() || should_quit()) break;
        }
        continue_loops();
        refresh_frontier();
        if (frontier_.empty() || should_quit()) break;
    }
}

void Vm::expand_trace() {
    // the nodes not run yet, run in the order of the tree; each run node's
    // place in the frontier taken by its children not run yet
    bool dispatch_only = false;
    if (setup_.just_fdests) {
        // the dispatcher first, a function's body with the nodes left once
        // it's done (explored with it, the default function's body took all
        // the nodes, and the functions past where the dispatcher was cut were
        // left to it)
        for (NodeId n : frontier_)
            if (in_dispatcher(n)) {
                dispatch_only = true;
                break;
            }
    }
    ++gen_;  // (the changes of this round, until the merges)
    std::pmr::vector<NodeId> next(res_), below(res_);
    next.reserve(frontier_.size() * 2);
    bool quit = false;
    for (NodeId n : frontier_) {
        if (!quit && nodes_[n].end == End::None && (!dispatch_only || in_dispatcher(n))) {
            // (one node's run can take long when the expressions get big)
            if (should_quit()) {
                quit = true;
            } else {
                poll();
                run_node(n);
            }
        }
        if (nodes_[n].end == End::None) {
            next.push_back(n);
        } else {
            find_nodes(n, [](const Node& x) { return x.end == End::None; }, below);
            next.insert(next.end(), below.begin(), below.end());
        }
    }
    frontier_.swap(next);
}

void Vm::fold_stacks(Value first, Value second, u32 key, Value& folded, std::pmr::vector<LoopVar>& vars) const {
    // the positions that differ between the stack at the loop's start and
    // after an iteration become the loop's variables (python fold_stacks)
    vars.clear();
    const u32 n = first.size();
    SmallVec<Value, 64> f(first.args());
    for (u32 idx = n; idx-- > 0;) {
        if (first[idx] != second[idx]) {
            Value var = Value::name(NameKind::LOOP, key << 12 | (n - idx));
            vars.push_back({var, first[idx], idx});
            f[idx] = var;
        }
    }
    folded = mk_list(f.span());
}

void Vm::stack_vars(Value first, std::span<const u32> positions, u32 key, Value& folded,
                    std::pmr::vector<LoopVar>& vars) const {
    vars.clear();
    const u32 n = first.size();
    SmallVec<Value, 64> f(first.args());
    SmallVec<u32, 16> pos(positions);
    std::sort(pos.begin(), pos.end(), std::greater<u32>());
    for (u32 idx : pos) {
        Value var = Value::name(NameKind::LOOP, key << 12 | (n - idx));
        vars.push_back({var, first[idx], idx});
        f[idx] = var;
    }
    folded = mk_list(f.span());
}

void Vm::replace_loops() {
    // the paths that get back to a jumpdest an ancestor started at, with the
    // same stack layout (the return addresses on it the same: not a
    // function's call), loop - the nearest such ancestor (python history)
    // among the nodes at the same jd
    new_loops_.clear();
    std::pmr::vector<NodeId> rest(res_);
    rest.reserve(frontier_.size());
    for (NodeId id : frontier_) {
        Node& n = nodes_[id];
        NodeId a = NO_NODE;
        if (n.stack.size() != 0) {
            const u32* head = jd_head_.find(n.jd);
            for (NodeId c = head ? *head - 1 : NO_NODE; c != NO_NODE; c = nodes_[c].same_jd) {
                const Node& x = nodes_[c];
                if (c == id || x.dead || x.depth >= n.depth) continue;
                if ((a == NO_NODE || x.depth > nodes_[a].depth) && below(id, c)) a = c;
            }
        }
        if (a == NO_NODE) {
            rest.push_back(id);
            continue;
        }
        new_loops_.push_back(id);
        Value folded;
        std::pmr::vector<LoopVar> vars(res_);
        fold_stacks(nodes_[a].stack, n.stack, loop_key(a), folded, vars);
        Node& m = nodes_[id];
        m.end = End::Loop;
        touch(id);
        m.dest = a;
        m.loop_stack = m.stack;
        m.loop_folded = folded;
        m.loop_vars.assign(vars.begin(), vars.end());
    }
    frontier_.swap(rest);
}

void Vm::set_label(NodeId self_id, NodeId dest_id, std::span<const LoopVar> vars, Value stack) {
    Node& self = nodes_[self_id];
    Node& dest = nodes_[dest_id];
    self.label = dest_id;
    dest.begin_vars.assign(vars.begin(), vars.end());
    if (self.stack.size() != stack.size()) throw InternalError("vm: a loop's stacks differ in length");
    self.stack = stack;
    // the iterations may differ in the call whose return data they have
    if (self.last_call != dest.last_call) self.last_call = kAmbiguousCall;
    dest.lines.clear();
    dest.end = End::Jump;
    dest.a = self_id;
    dest.cont = NO_NODE;
    cut(dest_id);
    set_prev(self_id, dest_id);
    became_unexpanded(self_id);
    // This node is now the body of a loop, executed for every iteration,
    // the first one included: what is known there is what was known before
    // the loop, not what the first iteration found out on its way here.
    // Except the code addresses in memory - where Vyper keeps the return
    // address of a private function - for as long as no iteration changes
    // them (see continue_loops).
    Node& s = nodes_[self_id];
    const Node& d = nodes_[dest_id];
    Facts known = d.known.forget(Forget::Volatile).without_memory();
    s.assumed_memory.clear();
    SmallVec<Fact, 32> v;
    d.known.to_vector(v);
    for (const Fact& f : v) {
        if (f.kind == FactKind::Mem && f.b == small(32) && is_jumpdest_int(map_, f.c) &&
            std::find(s.rejected_memory.begin(), s.rejected_memory.end(), f) == s.rejected_memory.end()) {
            s.assumed_memory.push_back(f);
            known = known.with(f);
        }
    }
    s.known = known;
}

bool Vm::continue_loops() {
    // the loops replace_loops just made - or, when the tree changed since or
    // an earlier round left some, all of them (python find_nodes)
    std::pmr::vector<NodeId> loops(res_);
    if (dirty_ || stale_loops_)
        find_nodes(root_, [](const Node& n) { return n.end == End::Loop; }, loops);
    else
        loops.assign(new_loops_.begin(), new_loops_.end());
    new_loops_.clear();
    stale_loops_ = true;  // (until all are done)
    for (NodeId id : loops) {
        poll();
        if (nodes_[id].end != End::Loop) continue;
        const NodeId dest = nodes_[id].dest;
        if (is_label(dest)) {
            Node& d = nodes_[dest];
            const Node& n = nodes_[id];
            SmallVec<Fact, 2> broken;
            for (const Fact& f : d.assumed_memory)
                if (!n.known.contains(f)) broken.push_back(f);
            if (!broken.empty()) {
                // an iteration changes what was assumed in memory at the start
                // of the loop: explored again without it
                SmallVec<Fact, 32> v, keep;
                d.known.to_vector(v);
                for (const Fact& f : v)
                    if (std::find(broken.begin(), broken.end(), f) == broken.end()) keep.push_back(f);
                d.known = Facts::from(keep.span());
                SmallVec<Fact, 2> still;
                for (const Fact& f : d.assumed_memory)
                    if (std::find(broken.begin(), broken.end(), f) == broken.end()) still.push_back(f);
                d.assumed_memory = still;
                for (const Fact& f : broken) d.rejected_memory.push_back(f);
                d.end = End::None;
                cut(dest);
                became_unexpanded(dest);
                return false;
            }
            // the iterations may differ in the call whose return data they
            // have: explored again with none known
            if (n.last_call != d.last_call && d.last_call != kAmbiguousCall) {
                d.last_call = kAmbiguousCall;
                d.end = End::None;
                cut(dest);
                became_unexpanded(dest);
                return false;
            }
            const Value old_stack = d.stack;
            const Value stack = n.loop_stack;
            const NodeId head = d.label;
            const auto& beginvars = nodes_[head].begin_vars;
            if (beginvars.empty()) {
                // (a loop of its own, from dest: see set_label)
                Value folded;
                std::pmr::vector<LoopVar> vars(res_);
                fold_stacks(old_stack, stack, loop_key(dest), folded, vars);
                if (!vars.empty()) {
                    nodes_[id].end = End::None;
                    set_label(id, dest, vars, folded);
                    continue;
                }
                // nothing on the stack changes from one iteration to the next
                // (the loop keeps what it changes in memory, as Vyper does):
                // back to the start, rather than a label again
                Node& m = nodes_[id];
                m.end = End::Goto;
                m.setvars = mk_trace({});
                touch(id);
                continue;
            }
            SmallVec<Value, 16> setvars;
            SmallVec<u32, 16> positions;
            for (const LoopVar& v : beginvars) {
                setvars.push_back(mk(Op::SETVAR, v.var, stack[v.pos]));
                positions.push_back(v.pos);
            }
            SmallVec<u32, 16> changed;
            for (u32 idx = 0; idx < old_stack.size(); ++idx)
                if (std::find(positions.begin(), positions.end(), idx) == positions.end() &&
                    old_stack[idx] != stack[idx])
                    changed.push_back(idx);
            if (!changed.empty()) {
                // The loop variables were found by comparing the stack before
                // and after the first iteration, and this one changes
                // something else (`s += i * i` leaves s at 0 the first time):
                // explored again, with a variable there too
                for (u32 c : changed) positions.push_back(c);
                Value folded;
                std::pmr::vector<LoopVar> vars(res_);
                stack_vars(nodes_[head].stack, positions.span(), loop_key(head), folded, vars);
                Node& dd = nodes_[dest];
                dd.end = End::None;
                cut(dest);
                set_label(dest, head, vars, folded);
                // (the other loops found in this pass may be in the part of
                // the tree just thrown away)
                return false;
            }
            Node& m = nodes_[id];
            m.end = End::Goto;
            m.setvars = mk_trace(setvars.span());
            touch(id);
            for (Value l : setvars) cx().pcs.note(l, m.start);
        } else {
            Node& m = nodes_[id];
            m.end = End::None;
            std::pmr::vector<LoopVar> vars(m.loop_vars.begin(), m.loop_vars.end(), res_);
            set_label(id, dest, vars, m.loop_folded);
        }
    }
    stale_loops_ = false;
    return true;
}

// ---- merges -----------------------------------------------------------------------------

bool Vm::ends_execution(u32 pc) const {
    // the block from pc can only end the execution
    const u32 size = map_.size();
    while (pc < size && map_.is_insn_start(pc)) {
        const u8 op = code_[pc];
        switch (kClass[op]) {
            case InsnClass::Halt:
            case InsnClass::Unknown:
                return true;
            case InsnClass::Jump:
            case InsnClass::JumpI:
                return false;
            default:
                break;
        }
        pc += 1 + kImm[op];
    }
    return false;
}

bool Vm::in_merged_branch(NodeId n, NodeId p) const {
    // n, below p, is in a branch of an IF between them whose paths were
    // merged: its path goes on in that IF's continuation, not after p's
    NodeId child = n;
    NodeId a = nodes_[n].prev;
    while (a != NO_NODE && a != p) {
        const Node& x = nodes_[a];
        if (x.end == End::If && x.cont != NO_NODE && (x.a == child || x.b == child)) return true;
        child = a;
        a = x.prev;
    }
    return false;
}

void Vm::merge_branches() {
    if (setup_.just_fdests) return;
    // The exits of a loop: where its exit condition and a break in its body
    // get to - too early to tell when they get there: tried again as the
    // paths get explored (python pending_merges), the oldest first.
    for (usize i = 0; i < pending_.size();) {
        auto [p, jd] = pending_[i];
        if (!attached(p) || merge_at(p, jd, true).has_value())
            pending_.erase(pending_.begin() + isize(i));
        else
            ++i;
    }
    refresh_frontier();
    if (!frontier_.empty()) {
        // (a copy: the merges change the tree)
        std::pmr::vector<NodeId> unexp(frontier_.begin(), frontier_.end(), res_);
        merge_unexpanded(unexp);
    }
}

void Vm::merge_unexpanded(std::pmr::vector<NodeId>& unexp) {
    // the live nodes at the jds of the unexpanded ones, in the order of the
    // tree, as the pass starts (python's by_jd)
    struct Group {
        u32 off, len;
    };
    std::pmr::vector<Group> groups(res_);
    std::pmr::vector<NodeId> members(res_), tmp(res_);
    Memo<Value, u32> index;  // jd -> 1 + its group
    for (NodeId node : unexp) {
        u32& g = index.slot(nodes_[node].jd);
        if (g) continue;
        same_jd(nodes_[node].jd, tmp);
        groups.push_back({u32(members.size()), u32(tmp.size())});
        members.insert(members.end(), tmp.begin(), tmp.end());
        g = u32(groups.size());
    }
    std::pmr::vector<std::pair<NodeId, u64>> tried(res_);

    for (NodeId node : unexp) {
        poll();
        const Node& x = nodes_[node];
        if (x.end != End::None) continue;  // merged into another during this pass
        if (x.switched) continue;          // a code switch's path: merged, what it copies wouldn't be known
        const Group grp = groups[*index.find(x.jd) - 1];
        if (grp.len < 2 || (x.sw == 0 && ends_execution(x.start))) continue;
        const Value jd = x.jd;
        for (u32 k = 0; k < grp.len; ++k) {
            const NodeId other = members[grp.off + k];
            if (other == node) continue;
            // the paths to node and other diverged at their closest common
            // ancestor: if it's an IF, that's where they could be merged
            NodeId p = common_ancestor(node, other);
            const Node& pn = nodes_[p];
            if (!(pn.end == End::If && pn.cont == NO_NODE)) continue;
            auto key = std::pair<NodeId, u64>(p, jd.raw());
            if (std::find(tried.begin(), tried.end(), key) != tried.end()) continue;
            tried.push_back(key);
            auto merged = merge_at(p, jd, false);
            if (merged && *merged) break;
            if (!merged && is_label(p)) {
                // at the head of a loop: its exits, maybe
                bool dup = false;
                for (auto& [pp, jj] : pending_) dup |= pp == p && jj == jd;
                if (!dup) pending_.push_back({p, jd});
            }
        }
    }
}

// Merge the paths going out of the IF node p at jd: true if done, nullopt
// when it can't be told yet (some paths not explored yet), false if not.
// loop_exit: only where jd is where the loop p heads goes on when it's left.
std::optional<bool> Vm::merge_at(NodeId p, Value jd, bool loop_exit) {
    {
        const Node& pn = nodes_[p];
        if (jd == pn.jd || !(pn.end == End::If && pn.cont == NO_NODE)) return false;
    }
    // the answer for p's subtree as it was, if it hasn't changed since (the
    // answer reads nothing else: asm's merge_visit stamps)
    const Key2 key{(u64(p) + 1) << 1 | u64(loop_exit), jd.raw()};
    if (const MergeMemo* m = merge_memo_.find(key); m && m->stamp == nodes_[p].stamp) {
        if (m->result == 0) return false;
        return std::nullopt;
    }
    auto memo = [&](std::optional<bool> r) {
        merge_memo_.put(key, MergeMemo{nodes_[p].stamp, i8(r ? 0 : 2)});
        return r;
    };
    std::pmr::vector<NodeId> hits(res_), continues(res_), todo(res_);
    const NodeId plabel = nodes_[p].label;

    // every path below start ends, reaches jd, or loops back: true; one
    // doesn't: false; too early to tell: nullopt
    auto visit = [&](NodeId start) -> std::optional<bool> {
        std::optional<bool> result = true;
        todo.clear();
        todo.push_back(start);
        while (!todo.empty()) {
            poll();
            NodeId n = todo.back();
            todo.pop_back();
            const Node& x = nodes_[n];
            if (x.merged) {
                // goes on in the continuation of the IF it was merged at,
                // visited as well if that's below p
                if (!below(x.merge_point, p)) return false;
                continue;
            }
            if (x.label != NO_NODE) {
                // the head of a loop: kept so
                if (x.jd == jd) return false;
            } else if (x.jd == jd && !in_merged_branch(n, p)) {
                hits.push_back(n);
                continue;
            }
            if (x.end == End::None) {
                result = std::nullopt;
                continue;
            }
            if (!x.next.empty()) {
                for (auto it = x.next.rbegin(); it != x.next.rend(); ++it) todo.push_back(*it);
                continue;
            }
            if (x.end == End::Goto) {
                if (x.dest == p || x.dest == plabel) continues.push_back(n);
                continue;
            }
            if (x.end == End::Halt || x.end == End::Merged) continue;
            // (a loop not turned into a label yet)
            result = std::nullopt;
        }
        return result;
    };

    const NodeId if_true = nodes_[p].a, if_false = nodes_[p].b;
    std::optional<bool> s1 = visit(if_true);
    if (s1 && !*s1) return memo(false);
    std::optional<bool> s2 = visit(if_false);
    if (s2 && !*s2) return memo(false);
    if (!s1 || !s2) return memo(std::nullopt);
    if (hits.size() < 2) return memo(false);
    if (loop_exit) {
        bool direct = false;
        for (NodeId h : hits) direct |= h == if_true || h == if_false;
        if (continues.empty() || !direct) return memo(false);
    }
    std::pmr::vector<NodeId> found(res_);
    for (NodeId h : hits) {
        // the path from h was merged with others further down, at an IF
        // above p: cut at h, it wouldn't get to that merge any more
        find_nodes(h, [&](const Node& m) { return m.merged && !below(m.merge_point, h); }, found);
        if (!found.empty()) return memo(false);
    }

    const u32 len = nodes_[hits[0]].stack.size();
    SmallVec<Value, 64> merged(nodes_[hits[0]].stack.args());
    std::vector<SmallVec<Value, 8>> setvars(hits.size());
    SmallVec<Value, 8> vals;
    for (u32 idx = 0; idx < len; ++idx) {
        vals.clear();
        for (NodeId h : hits) vals.push_back(nodes_[h].stack[idx]);
        if (std::all_of(vals.begin(), vals.end(), [&](Value v) { return v == vals[0]; })) continue;
        // what a path knows of a value it has of its own: the left of a `&&`
        // that stopped it is false there
        for (usize k = 0; k < hits.size(); ++k) vals[k] = nodes_[hits[k]].known.decided(vals[k]);
        if (std::all_of(vals.begin(), vals.end(), [&](Value v) { return v == vals[0]; })) {
            merged[idx] = vals[0];
            continue;
        }
        // (not a jump destination as a variable)
        for (Value v : vals)
            if (is_jumpdest_int(map_, v)) return memo(false);
        Value t = fresh_tmp();
        merged[idx] = t;
        for (usize k = 0; k < hits.size(); ++k) setvars[k].push_back(mk(Op::SETVAR, t, vals[k]));
    }

    // what's known at the merge point is what's known on every path, and
    // what only some of them wrote in memory isn't (not even that it's zero)
    SmallVec<Fact, 32> first, keep;
    nodes_[hits[0]].known.to_vector(first);
    for (const Fact& f : first) {
        bool all = true;
        for (usize k = 1; k < hits.size() && all; ++k) all = nodes_[hits[k]].known.contains(f);
        if (all) keep.push_back(f);
    }
    Facts known = Facts::from(keep.span());
    for (NodeId h : hits) {
        SmallVec<Fact, 32> v;
        nodes_[h].known.to_vector(v);
        for (const Fact& f : v) {
            if (f.kind != FactKind::Mem || known.contains(f)) continue;
            Fact u{FactKind::Mem, f.a, f.b, Value()};
            if (!known.contains(u)) known = known.with(u);
        }
    }
    u32 last_call = nodes_[hits[0]].last_call;
    for (NodeId h : hits)
        if (nodes_[h].last_call != last_call) last_call = kAmbiguousCall;

    ++gen_;  // (a merge: the memo's answers below p and above it no longer hold)
    for (usize k = 0; k < hits.size(); ++k) {
        Node& h = nodes_[hits[k]];
        h.lines.assign(setvars[k].begin(), setvars[k].end());
        for (Value l : setvars[k]) cx().pcs.note(l, h.start);
        h.end = End::Merged;
        cut(hits[k]);
        h.cont = NO_NODE;
        h.merged = true;
        h.merge_point = p;
    }
    const Node& h0 = nodes_[hits[0]];
    NodeId node = new_node(h0.start, h0.safe, mk_list(merged.span()), Value(true), known, last_call, h0.sw);
    set_prev(node, p);
    nodes_[p].cont = node;
    became_unexpanded(node);
    return true;
}

// ---- recursive internal functions ---------------------------------------------------------

const InternalEntry* Vm::internal_of(u32 start) const {
    for (const InternalEntry& e : internal_)
        if (e.entry == start) return &e;
    return nullptr;
}

bool Vm::internal_call_at(u32 start, Value stack) const {
    // start, with stack, is the call of a recursive internal function
    const InternalEntry* e = internal_of(start);
    if (!e) return false;
    if (stack.size() <= e->nargs) return false;
    Value ret = stack[stack.size() - e->nargs - 1];
    return is_jumpdest_int(map_, ret);
}

void Vm::internal_call(NodeId id) {
    // the call of the recursive internal function at start: INTERNAL(start,
    // its arguments, variables for its results), then where it returns, with
    // the state as a call may leave it (python internal_call)
    const u32 start = nodes_[id].start;
    const InternalEntry e = *internal_of(start);
    snapshot(Op::DELEGATECALL, Value(), start);
    const u32 n = e.nargs;
    const usize len = st_.size();
    SmallVec<Value, 16> args;
    for (usize i = len - n; i < len; ++i) args.push_back(st_[i]);
    Value ret = st_[len - n - 1];
    SmallVec<Value, 8> results;
    for (u32 i = 0; i < e.nresults; ++i) results.push_back(fresh_tmp());
    emit(mk(Op::INTERNAL, small(start), mk_list(args.span()), mk_list(results.span())), start);
    known_ = known_.forget(Forget::Volatile).without_memory();
    last_call_ = kAmbiguousCall;
    while (st_.size() > len - n - 1) st_.pop_back();
    for (Value r : results) st_.push_back(r);
    NodeId c = child_at(ret, false, condition_, known_, start);
    Node& x = nodes_[id];
    x.lines.assign(out_.begin(), out_.end());
    x.end = End::Jump;
    x.end_pc = start;
    x.a = c;
    link(id);
}

void Vm::call_entry(NodeId prev, u32 p, NodeId node, u32 q, u32& entry, u32& nargs, u32& frame) const {
    // where the function prev and node are the calls of starts: the
    // outermost node of prev's call that node's call has too (python
    // call_entry)
    auto within = [&](NodeId x, u32 k, Value stack) {
        Value s = nodes_[x].stack;
        if (s.size() <= k) return false;
        for (u32 i = 0; i <= k; ++i)
            if (s[i] != stack[i]) return false;
        return true;
    };
    const Value pstack = nodes_[prev].stack, nstack = nodes_[node].stack;
    SmallVec<NodeId, 32> outer, inner;
    for (NodeId x = prev; x != NO_NODE && within(x, p, pstack); x = nodes_[x].prev) outer.push_back(x);
    for (NodeId y = node; y != NO_NODE && within(y, q, nstack); y = nodes_[y].prev) inner.push_back(y);
    for (usize i = outer.size(); i-- > 0;) {
        const Node& x = nodes_[outer[i]];
        for (NodeId yi : inner) {
            const Node& y = nodes_[yi];
            if (y.start == x.start && y.stack.size() - q == x.stack.size() - p) {
                entry = x.start;
                nargs = x.stack.size() - p - 1;
                frame = y.stack.size() - x.stack.size();
                return;
            }
        }
    }
    entry = nodes_[prev].start;
    nargs = pstack.size() - p - 1;
    frame = nstack.size() - pstack.size();
}

std::optional<InternalEntry> Vm::recursion_of(NodeId id) {
    // node starts the call of an internal function in its own call: an
    // ancestor starts there too, with the address its call returns to (the
    // topmost on its stack) on node's stack, all below it the same, and
    // above it as many words as node has above its own (python recursion_of)
    const Node& node = nodes_[id];
    const u32 start = node.start;
    if (node.sw || !map_.is_jumpdest(start)) return std::nullopt;
    auto top_dest = [&](Value stack) -> std::optional<u32> {
        for (u32 i = stack.size(); i-- > 0;)
            if (is_jumpdest_int(map_, stack[i])) return i;
        return std::nullopt;
    };
    auto q = top_dest(node.stack);
    if (!q) return std::nullopt;
    const Value nstack = node.stack;
    std::optional<InternalEntry> rec;
    std::pmr::vector<NodeId> found(res_);
    for (NodeId prev = node.prev; prev != NO_NODE; prev = nodes_[prev].prev) {
        poll();
        const Node& pn = nodes_[prev];
        if (pn.start != start || pn.sw || pn.stack.size() >= nstack.size()) continue;
        auto p = top_dest(pn.stack);
        if (!p || *p >= *q || pn.stack.size() - *p != nstack.size() - *q) continue;
        bool same = true;
        for (u32 i = 0; i <= *p && same; ++i) same = pn.stack[i] == nstack[i];
        if (!same) continue;
        if (!rec) {
            InternalEntry e;
            call_entry(prev, *p, id, *q, e.entry, e.nargs, e.frame);
            rec = e;
        }
        // its results: where its call returns, the stack below the address
        // the same and the address gone
        const Value ret = pn.stack[*p];
        const u32 pp = *p;
        const Value pstack = pn.stack;
        find_nodes(
            prev,
            [&](const Node& x) {
                if (!(x.start == u64(ret.small_val()) && x.sw == 0 && x.stack.size() >= pp)) return false;
                for (u32 i = 0; i < pp; ++i)
                    if (x.stack[i] != pstack[i]) return false;
                return !(x.stack.size() > pp && x.stack[pp] == ret);
            },
            found);
        if (!found.empty()) {
            rec->nresults = nodes_[found[0]].stack.size() - pp;
            return rec;
        }
    }
    return std::nullopt;
}

void Vm::replace_recursions() {
    // where a node starts the call of an internal function in its own call,
    // the function is a recursive one: every call of it is a line - those of
    // the path explored, the first one included, explored again as such
    if (setup_.just_fdests) return;
    refresh_frontier();
    std::pmr::vector<NodeId> nodes(frontier_.begin(), frontier_.end(), res_), redo(res_);
    for (NodeId id : nodes) {
        poll();
        const Node& n = nodes_[id];
        if (n.end != End::None) continue;
        if (internal_call_at(n.start, n.stack)) continue;
        auto rec = recursion_of(id);
        if (!rec || internal_of(rec->entry)) continue;
        internal_.push_back(*rec);
        found_.push_back(*rec);
        const u32 entry = rec->entry;
        find_nodes(
            root_,
            [&](const Node& x) {
                return x.start == entry && x.sw == 0 && x.end != End::None && internal_call_at(x.start, x.stack);
            },
            redo);
        for (NodeId x : redo) {
            Node& m = nodes_[x];
            m.end = End::None;
            cut(x);
            m.lines.clear();
            m.cont = NO_NODE;
            became_unexpanded(x);
        }
        return;
    }
}

// ---- the trace --------------------------------------------------------------------------

u32 Vm::loop_id_of(NodeId label) {
    Node& x = nodes_[label];
    if (x.loop_id == 0) {
        x.loop_id = next_loop_id_++;
        loops_.push_back({x.loop_id, x.start});
    }
    return x.loop_id;
}

bool Vm::has_goto_to(NodeId label) const {
    const NodeId head = nodes_[label].label;
    std::pmr::vector<NodeId> found(res_);
    find_nodes(label, [&](const Node& x) { return x.end == End::Goto && (x.dest == label || x.dest == head); },
               found);
    return !found.empty();
}

void Vm::begin_trace(NodeId n, std::pmr::vector<Value>& out) {
    const Node& x = nodes_[n];
    if (x.end == End::None) {
        complete_ = false;
        Value l = mk(Op::UNDEFINED, small(i64(UndefinedReason::UNFINISHED)), small(x.start));
        cx().pcs.note(l, x.start);
        out.push_back(l);
        return;
    }
    if (x.label == NO_NODE) return;
    SmallVec<Value, 16> setvars;
    for (const LoopVar& v : nodes_[x.label].begin_vars) {
        Value l = mk(Op::SETVAR, v.var, v.val);
        cx().pcs.note(l, x.start);
        setvars.push_back(l);
    }
    if (has_goto_to(n)) {
        Value l = mk(Op::LABEL, Value::name(NameKind::LOOP_ID, loop_id_of(n)), mk_trace(setvars.span()));
        cx().pcs.note(l, x.start);
        out.push_back(l);
    } else {
        // nothing loops back here any more: a merge took the paths that did
        // to the continuation of an IF above, where the loop is found again;
        // what's left here is the first iteration
        for (Value l : setvars) out.push_back(l);
    }
}

void Vm::trace_into(NodeId n, std::pmr::vector<Value>& out) {
    check_stack();
    // the nodes form long chains (a jump at the end of each), walked in a
    // loop: the recursion is only as deep as the IFs are nested
    while (n != NO_NODE) {
        poll();
        begin_trace(n, out);
        const Node& x = nodes_[n];
        if (x.end == End::None) return;
        for (Value l : x.lines) out.push_back(l);
        switch (x.end) {
            case End::Jump:
                n = x.a;
                continue;
            case End::If: {
                Value t = make_trace_of(x.a);
                Value f = make_trace_of(x.b);
                Value l = mk(Op::IF, x.cond, t, f);
                cx().pcs.note(l, x.end_pc);
                out.push_back(l);
                n = x.cont;
                continue;
            }
            case End::Goto: {
                Value l = mk(Op::GOTO, Value::name(NameKind::LOOP_ID, loop_id_of(x.dest)), x.setvars);
                cx().pcs.note(l, x.start);
                out.push_back(l);
                return;
            }
            case End::Loop: {
                // (a loop the VM stopped before it was made one)
                complete_ = false;
                Value l = mk(Op::UNDEFINED, small(i64(UndefinedReason::UNFINISHED)), small(x.start));
                cx().pcs.note(l, x.start);
                out.push_back(l);
                return;
            }
            default:
                return;
        }
    }
}

Value Vm::make_trace_of(NodeId n) {
    std::pmr::vector<Value> out(res_);
    trace_into(n, out);
    return mk_trace(std::span<const Value>(out.data(), out.size()));
}

Value Vm::make_trace() { return make_trace_of(root_); }

std::vector<CallSite> Vm::calls_of(Value trace) const {
    // the calls whose lines are in the trace
    std::vector<u32> ids;
    SmallVec<Value, 64> todo{trace};
    while (!todo.empty()) {
        poll();
        Value v = todo.back();
        todo.pop_back();
        if (v.is_list()) {
            for (Value l : v.args()) todo.push_back(l);
            continue;
        }
        switch (v.op()) {
            case Op::CALL: case Op::CALLCODE: case Op::DELEGATECALL: case Op::STATICCALL:
            case Op::CREATE: case Op::CREATE2: case Op::PRECOMPILED:
                ids.push_back(u32(v[0].small_val()));
                break;
            case Op::IF:
                todo.push_back(v[1]);
                todo.push_back(v[2]);
                break;
            default:
                break;
        }
    }
    std::sort(ids.begin(), ids.end());
    std::vector<CallSite> res;
    for (const CallSite& c : calls_)
        if (std::binary_search(ids.begin(), ids.end(), c.id)) res.push_back(c);
    std::sort(res.begin(), res.end(), [](const CallSite& a, const CallSite& b) { return a.id < b.id; });
    return res;
}

std::vector<LoopInfo> Vm::loops() const { return loops_; }

}  // namespace pan::vm
