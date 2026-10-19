// The symbolic VM's insides (lot 5 only): the tree of nodes explored breadth
// first by rounds (python VM.run), a node's block run by the exec machine
// with the handlers below (python VM._run, apply_stack, handle_jumps), the
// loops (replace_loops, continue_loops), the merges of branches
// (merge_branches), the recursive internal functions (replace_recursions,
// recursion_of, internal_call) and the trace (make_trace).
#pragma once

#include <algorithm>
#include <deque>
#include <memory_resource>
#include <optional>
#include <span>
#include <vector>

#include "core/base.hpp"
#include "core/contract.hpp"
#include "core/memo.hpp"
#include "core/smallvec.hpp"
#include "core/value.hpp"
#include "evm/decoder.hpp"
#include "algebra/facts.hpp"
#include "vm/vm.hpp"

namespace pan::vm {

// the path facts are lot 3's (algebra/facts.hpp)
using alg::Fact;
using alg::FactKind;
using alg::Facts;
using alg::Forget;

using NodeId = u32;
inline constexpr NodeId NO_NODE = ~u32{0};

// an internal function's return address on its own stack (python
// RETURN_ADDRESS): a jump to it is the function's LEAVE. A private leaf of
// the VM's range (0x1e0..), never in a trace but by a contract's mistake.
inline constexpr Op kOpReturnAddress = Op(0x1e0);
inline constexpr Value kReturnAddress = Value::leaf(kOpReturnAddress);

// the last call of a path when it depends on the path in a way the VM can't
// tell (a loop's head, after an internal call)
inline constexpr u32 kAmbiguousCall = ~u32{0};
// the last call of merged paths that differ in it: kMergedCall | the index
// of the merge's record (Vm::call_merges_)
inline constexpr u32 kMergedCall = u32{1} << 31;
inline bool is_merged_call(u32 c) noexcept { return c != kAmbiguousCall && (c & kMergedCall); }

// A merge of paths whose last calls differ (merge_at): each path's hit and
// last call (0: none yet, a call's id, another merge's); the variables the
// reads of the return data after the merge take, set at the end of each
// path - made at the first read (most merges are never read after)
struct CallPath {
    NodeId hit;
    u32 call;
};
struct CallMerge {
    std::vector<CallPath> paths;
    Value size;  // TMP: the return data's size (NIL: none made yet)
    Value id;    // TMP: the call's id, for the copies (NIL: none made yet)
};

// the EVM's stack: 1024 words at most (a push past it halts)
inline constexpr usize kStackLimit = 1024;
// INVALID's reason for it
inline constexpr InvalidReason kStackOverflow = InvalidReason::STACK_OVERFLOW;

// a subtree's summary (Link::sum_mask, Vm::summarize): its labels' jds as
// bits of their hash below these flags
inline constexpr u64 kSumMerged = u64{1} << 62;   // a merged node in it
inline constexpr u64 kSumUnknown = u64{1} << 63;  // more than kSumRoom merge points outside it
inline constexpr u32 kSumJdBits = 62;
inline constexpr u32 kSumRoom = 3;
inline u64 sum_jd_bit(Value jd) {
    u32 b = u32((jd.raw() * 0x9e3779b97f4a7c15ull) >> 58);
    if (b >= kSumJdBits) b -= kSumJdBits;
    return u64{1} << b;
}

// how a node's trace ends (python's last line of node.trace)
enum class End : u8 {
    None,      // not run yet (python trace None)
    Halt,      // its lines end with a halting line
    Jump,      // goes on at the child a (python ("jump", node))
    If,        // IF(cond, a, b); then the merge's continuation `cont`, if any
    Loop,      // python ("loop", dest, stack, folded, vars): reached an ancestor's jd
    Goto,      // python ("goto", dest, setvars)
    Merged,    // its lines are a merge's setvars: the path goes on after merge_point's IF
    FuncCall,  // discovery: a selector test taken (python ("funccall", hash, target, stack))
};

// a loop variable (python's ("var", id, value, stack position))
struct LoopVar {
    Value var;  // Name(LOOP, key << 12 | position from the top)
    Value val;  // its value in the first iteration
    u32 pos;    // its index in the stack (bottom first)
};

// A node's place in the tree, apart from the node: the walks up (common
// ancestors, below, touch) and the summaries' checks read nothing else - a
// contiguous array of these, a few hundred KB for the 20000 nodes of a
// run, where the nodes are hundreds of bytes each.
struct Link {
    NodeId prev = NO_NODE;  // the parent
    u32 depth = 0;
    NodeId jump = NO_NODE;  // skew-binary jump pointer (O(log n) ancestors)
    u32 stamp = 0;          // the generation of the last change in its subtree (touch)
    // the subtree's summary for merge_at's walks (summarize): good while
    // sum_stamp is stamp + 1 (0: none) - the jds of its labels (kSumJdBits
    // bits of a hash), whether it holds merged nodes, too many merge points
    // outside it (kSumUnknown)
    u32 sum_stamp = 0;
    // (copies of the node's, which never change: what recursion_of's walk
    // up compares)
    u32 start = 0;
    u64 sum_mask = 0;
    u16 sw = 0;
    u16 nstack = 0;  // the stack's length
    u32 unused = 0;
};
static_assert(sizeof(Link) == 40);

struct Node {
    // --- what the walks of the tree read: first (one cache line) ---
    u32 start = 0;          // the pc
    u32 sw = 0;             // a code switch's case node: 1 + k (python start ("switch", pc, k))
    NodeId same_jd = NO_NODE;  // the node made before it at the same jd (the jd's list)
    NodeId label = NO_NODE;    // python node.label: the head whose loop this node is the body of
    Value stack;            // LIST, bottom first
    Value jd;               // LIST (start, sw, stack length, the jumpdests on the stack)
    // its children (python node.next), in order: the first, the last, and
    // each one's next one (a list through the nodes: what the walks down
    // read is in the line they read anyway)
    NodeId first = NO_NODE;
    NodeId last = NO_NODE;
    NodeId sibling = NO_NODE;  // the next child of its parent
    NodeId dest = NO_NODE;     // Loop, Goto: the node looped back to
    bool dead = true;       // not in the tree (python: not attached): until linked (below a
                            // node in it), once cut
    bool safe = false;      // reached by a fall-through: no JUMPDEST check
    bool merged = false;    // its paths go on at merge_point's continuation
    bool switched = false;  // a code switch's path (never merged)
    End end = End::None;    // how its trace ends (None: not run yet)
    // (its place in the tree: Vm::links_)

    // --- where, and with what (python Node.__init__) ---
    Value condition;    // the condition it's reached under (True: none)
    Facts known;
    u32 last_call = 0;  // the call whose return data the path has (0: none yet)

    // --- the trace ---
    std::pmr::vector<Value> lines;
    u32 end_pc = 0;           // the pc of the instruction that ended the block
    Value cond;               // If
    NodeId a = NO_NODE;       // Jump: the child; If: the true branch
    NodeId b = NO_NODE;       // If: the false branch
    NodeId cont = NO_NODE;    // If: the continuation of the merged paths
    Value loop_stack;         // Loop: the stack it arrived with
    Value loop_folded;        // Loop: the folded stack (variables)
    std::pmr::vector<LoopVar> loop_vars;  // Loop: the variables
    Value setvars;            // Goto: TRACE of SETVAR lines

    // --- loops ---
    std::pmr::vector<LoopVar> begin_vars;  // (on a head) python begin_vars
    u32 loop_key = 0;        // python loop_key (0: none yet)
    u32 loop_id = 0;         // the LOOP_ID of its LABEL (0: none yet)
    SmallVec<Fact, 2> assumed_memory, rejected_memory;
    bool has_assumed = false;

    // --- merges ---
    NodeId merge_point = NO_NODE;
    // (the summary's merge points of merged nodes in the subtree that
    // aren't in it: kSumRoom at most)
    u8 sum_en = 0;
    NodeId sum_e[3] = {};

    // --- discovery ---
    i8 dispatch = -1;  // in_dispatcher, memoized
    u32 fsel = 0;      // FuncCall: the selector
    i64 ftarget = 0;   // FuncCall: where the function starts (-1: an invalid jump)

    explicit Node(std::pmr::memory_resource* r) : lines(r), loop_vars(r), begin_vars(r) {}
    bool has_children() const noexcept { return first != NO_NODE; }
};

// what a run is for
struct RunSetup {
    u32 start = 0;
    Value stack;               // LIST
    Facts known;           // at start
    std::vector<Value> before; // lines before the function (python `before`: the fmp)
    bool just_fdests = false;  // discovery
    bool inside = false;       // an internal function's body
    bool verbose = false;
    bool explain = false;      // + the control flow's ASM lines (python: --explain only)
    u32 max_nodes = 0;
    i64 deadline_ns = 0;       // 0: none
    std::vector<InternalEntry> internal;  // known recursive functions
    Value given;               // the values handed over (python name_past): a LIST
};

class Vm {
public:
    Vm(const ContractShared& contract, const RunSetup& setup);
    Vm(const Vm&) = delete;
    Vm& operator=(const Vm&) = delete;

    // the exploration (python VM.run without make_trace)
    void explore();
    // the raw trace of the explored tree
    Value make_trace();

    // the results
    bool complete() const noexcept { return complete_; }
    u32 node_count() const noexcept { return node_count_; }
    const std::vector<InternalEntry>& found() const noexcept { return found_; }
    std::vector<CallSite> calls_of(Value trace) const;
    std::vector<LoopInfo> loops() const;

    // --- for the discovery (discover.cpp) ---
    const Node& node(NodeId id) const { return nodes_[id]; }
    NodeId parent(NodeId id) const { return links_[id].prev; }
    NodeId root() const noexcept { return root_; }
    const CodeMap& map() const noexcept { return map_; }
    Value make_trace_of(NodeId n);  // the trace from n (a branch)
    bool is_dispatch(Value cond) const;

    // --- the exec machine's handlers (vm_exec: called by the block's run) ---
    // each returns false when the block ends there
    bool plain(u8 op, u32 pc);
    bool push(const Insn& in);
    bool dup(u32 n, u32 pc);
    void swap(u32 n, u32 pc);
    void jump(u32 pc);
    void jumpi(u32 pc, u32 next);
    void halt(u8 op, u32 pc);
    void unknown(u8 op, u32 pc);
    void split(u32 pc);     // a JUMPDEST in the middle: the next node starts there
    void fell_off(u32 pc);  // the end of the code: STOP
    bool underflow(u8 op, u32 pc);  // fewer words than op takes: INVALID, true
    bool overflow(u8 op, u32 pc);   // more words than the EVM's 1024 after op: INVALID, true
    void asm_line(const Insn& in);  // --verbose

private:
    friend struct BlockRun;
    // --- nodes ---
    NodeId new_node(u32 start, bool safe, Value stack, Value condition, const Facts& known, u32 last_call,
                    u32 sw = 0);
    NodeId add_node();  // a node and its link, blank
    Value jd_of(u32 start, u32 sw, Value stack) const;
    void set_prev(NodeId child, NodeId parent);
    NodeId ancestor_at(NodeId n, u32 depth) const;
    NodeId common_ancestor(NodeId a, NodeId b) const;
    bool below(NodeId n, NodeId p) const;  // n is p or under it
    bool attached(NodeId n) const;
    template <class F>
    void find_nodes(NodeId from, F&& f, std::pmr::vector<NodeId>& out) const;
    // x's children on a walk's stack, the first on top (popped first)
    void push_children(const Node& x, std::pmr::vector<NodeId>& todo) const {
        const usize base = todo.size();
        for (NodeId c = x.first; c != NO_NODE; c = nodes_[c].sibling) todo.push_back(c);
        std::reverse(todo.begin() + isize(base), todo.end());
    }
    void unexpanded(std::pmr::vector<NodeId>& out) const;
    // the node's children cut off the tree: its subtree dead (python's
    // node.next = [])
    void cut(NodeId n);
    // frontier_ brought up to date after the tree changed elsewhere than
    // in the nodes run: the nodes dead or run dropped, those that became
    // unexpanded (became_unexpanded) put at their place in the tree's order
    void refresh_frontier();
    void became_unexpanded(NodeId n) { reborn_.push_back(n); }
    // x changed (its trace, its children, its label, merged): its stamp,
    // and its ancestors', the current generation - merge_at's memo and the
    // summaries hold while the stamp of their node does. A new generation
    // begins at the first change after one was made (visited_); a node
    // already of the current one has its ancestors of it too.
    void touch(NodeId x) {
        if (visited_) {
            ++gen_;
            visited_ = false;
        }
        for (; x != NO_NODE && links_[x].stamp != gen_; x = links_[x].prev) links_[x].stamp = gen_;
    }
    // n's subtree summarized (Node::sum_mask), unless it is already: over
    // the whole subtree, as python's walk would go if nothing stopped it
    // (but at a merged node, as it does)
    void summarize(NodeId n);
    // nothing in n's subtree can make merge_at's walk from p false: no
    // merged node whose merge point isn't below p, no loop at jd
    bool can_skip(NodeId n, NodeId p, Value jd);
    // n's live nodes at jd, in the order of the tree (python by_jd's)
    void same_jd(Value jd, std::pmr::vector<NodeId>& out) const;
    // u before v in the tree's depth first order (python find_nodes')
    bool dfs_less(NodeId u, NodeId v) const;
    bool is_label(NodeId n) const { return nodes_[n].label != NO_NODE; }
    u32 loop_key(NodeId head);

    // --- a node's run (python Node.run, VM._run) ---
    void run_node(NodeId id);
    void run_block(NodeId id);
    void exec_block(u32 start);
    void finish_halt(Value line, u32 pc);
    NodeId child_at(Value target, bool safe, Value condition, const Facts& known, u32 pc);
    void link(NodeId id);

    // --- effects ---
    void emit(Value line, u32 pc);
    Value pop() { Value v = st_.back(); st_.pop_back(); return v; }
    void push_value(Value v, u32 pc);
    Value fresh_tmp() { return Value::name(NameKind::TMP, ++counter_); }
    void snapshot(Op op, Value target, u32 pc);
    Value returndatasize(u32 pc);
    // the variables of a merge's return data (kMergedCall | index), made on
    // the merged paths at the first read
    Value merged_size(u32 call);
    Value merged_id(u32 call);
    void merged_ids(u32 call, SmallVec<u32, 8>& out) const;  // the ids it may be (0: none)
    void merged_copy(Value dst, Value src, Value n, u32 pc);  // a RETURNDATACOPY of it
    void handle_call(u8 op, u32 pc);
    void output_write(u32 id, Value ret_start, Value ret_len, u32 pc);
    std::pair<Value, Value> call_data(Value arg_start, Value arg_len);
    bool code_switch(u32 pc);
    Value code_bytes(Value pos, Value len) const;

    // --- the rounds ---
    bool should_quit();
    void expand_trace();
    void replace_loops();
    void replace_recursions();
    bool continue_loops();
    void merge_branches();
    void merge_unexpanded(std::pmr::vector<NodeId>& unexp);
    std::optional<bool> merge_at(NodeId p, Value jd, bool loop_exit);
    // python's visit (in _merge_at): from start, a branch of the IF p; the
    // walk skips what can't make it false once only a false would count
    // (skips: false_only - the other branch too early to tell - or once
    // this one is)
    std::optional<bool> merge_visit(NodeId start, NodeId p, Value jd, bool false_only, bool skips,
                                    std::pmr::vector<NodeId>& hits, std::pmr::vector<NodeId>& continues);
    bool in_merged_branch(NodeId n, NodeId p) const;
    bool ends_execution(u32 pc) const;
    void set_label(NodeId self, NodeId loop_dest, std::span<const LoopVar> vars, Value stack);
    void fold_stacks(Value first, Value second, u32 key, Value& folded, std::pmr::vector<LoopVar>& vars) const;
    void stack_vars(Value first, std::span<const u32> positions, u32 key, Value& folded,
                    std::pmr::vector<LoopVar>& vars) const;

    // --- recursion ---
    bool internal_call_at(u32 start, Value stack) const;
    const InternalEntry* internal_of(u32 start) const;
    void internal_call(NodeId id);
    std::optional<InternalEntry> recursion_of(NodeId n);
    void call_entry(NodeId prev, u32 p, NodeId node, u32 q, u32& entry, u32& nargs, u32& frame) const;

    // --- discovery ---
    bool in_dispatcher(NodeId n);
    std::optional<std::pair<u32, bool>> selector_test(Value cond) const;

    // --- the trace ---
    void trace_into(NodeId n, std::pmr::vector<Value>& out);
    void begin_trace(NodeId n, std::pmr::vector<Value>& out);
    u32 loop_id_of(NodeId label);
    bool has_goto_to(NodeId label) const;

    const ContractShared& contract_;
    const CodeMap& map_;
    std::span<const u8> code_;
    RunSetup setup_;
    std::pmr::memory_resource* res_;
    std::pmr::deque<Node> nodes_;
    std::pmr::vector<Link> links_;  // nodes_[i]'s place in the tree
    NodeId root_ = NO_NODE;
    // the last node made at each jd (+ 1): the head of the jd's list
    Memo<Value, u32> jd_head_;
    // the nodes not run yet, in the order of the tree (python's
    // find_nodes(root, unexpanded)), kept up to date as the nodes run, made
    // again by a walk when the tree's shape changes elsewhere (dirty_)
    std::pmr::vector<NodeId> frontier_;
    bool dirty_ = true;
    std::pmr::vector<NodeId> reborn_;  // nodes unexpanded again or new, outside the runs
    // the generation of the changes (touch); merge_at's answers that merged
    // nothing, by (IF node, jd, loop_exit), with the IF node's stamp then
    u32 gen_ = 1;
    bool visited_ = false;  // a memo answer or a summary made in this generation
    mutable std::pmr::vector<u64> sum_walk_;  // summarize's (node << 1 | its children done)
    struct MergeMemo {
        u32 stamp;
        i8 result;  // 0: false, 2: too early to tell
    };
    Memo<Key2, MergeMemo> merge_memo_;
    // PANORAMIX_VM_CHECK: the incremental frontier and the merge memo
    // checked against python's walks (InternalError on a difference)
    bool check_ = false;
    // PANORAMIX_VM_STATS: what the rounds did, on stderr at the end
    struct Stats {
        u64 rounds = 0, passes = 0, pairs = 0, merge_calls = 0, memo_hits = 0, visit_pops = 0, skips = 0,
            summarized = 0, merged_branch_steps = 0, recursion_steps = 0, merges = 0;
    };
    mutable Stats stats_;
    bool stats_on_ = false;
    void check_frontier() const;
    // the loops replace_loops made this round, in the order of the tree; and
    // whether some of an earlier round's are left (a walk finds them)
    std::pmr::vector<NodeId> new_loops_;
    bool stale_loops_ = false;
    // scratch of the walks (never two at once), and merge_visit's
    mutable std::pmr::vector<NodeId> walk_;
    std::pmr::vector<NodeId> visit_walk_;

    // counters (python's, per VM)
    u32 counter_ = 0;        // TMP names
    u32 call_ids_ = 0;       // call ids
    u32 gas_reads_ = 0;      // GAS leaves (each read its own)
    u32 next_loop_key_ = 1;  // loop keys
    u32 next_loop_id_ = 1;   // LOOP_IDs
    u32 precompile_count_[9] = {};
    u32 node_count_ = 0;
    u32 frontier_count_ = 0;
    bool quit_ = false;
    bool complete_ = true;

    std::vector<InternalEntry> internal_;  // known and found (python self.internal)
    std::vector<InternalEntry> found_;
    std::vector<CallSite> calls_;
    std::vector<LoopInfo> loops_;
    // pending merges at loop heads (python pending_merges): (p, jd)
    std::vector<std::pair<NodeId, Value>> pending_;
    // the merges of paths whose last calls differ (kMergedCall)
    std::vector<CallMerge> call_merges_;

    // --- the block being run ---
    NodeId cur_ = NO_NODE;
    SmallVec<Value, 64> st_;
    Facts known_;
    u32 last_call_ = 0;
    Value condition_;
    std::pmr::vector<Value> out_;
    bool halted_ = false;
    bool rdzero_ = false;  // RETURNDATASIZE is 0 (python RETURNDATASIZE_ZERO known)
};

// the nodes below `from` (itself included) where f is true, depth first, the
// children in order (python find_nodes)
template <class F>
void Vm::find_nodes(NodeId from, F&& f, std::pmr::vector<NodeId>& out) const {
    out.clear();
    std::pmr::vector<NodeId>& todo = walk_;
    todo.clear();
    todo.push_back(from);
    while (!todo.empty()) {
        poll();
        NodeId n = todo.back();
        todo.pop_back();
        const Node& x = nodes_[n];
        if (f(x)) out.push_back(n);
        push_children(x, todo);
    }
}

// python simplify_bool: the condition of a JUMPI without its BOOL
Value simplify_bool(Value e);
// python exp_size: the size of v as a tree, counted up to cap
u32 exp_size(Value v, u32 cap);

}  // namespace pan::vm
