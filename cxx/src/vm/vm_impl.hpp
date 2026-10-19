// The symbolic VM's insides (lot 5 only): the tree of nodes explored breadth
// first by rounds (python VM.run), a node's block run by the exec machine
// with the handlers below (python VM._run, apply_stack, handle_jumps), the
// loops (replace_loops, continue_loops), the merges of branches
// (merge_branches), the recursive internal functions (replace_recursions,
// recursion_of, internal_call) and the trace (make_trace).
#pragma once

#include <deque>
#include <memory_resource>
#include <optional>
#include <span>
#include <vector>

#include "core/base.hpp"
#include "core/contract.hpp"
#include "core/smallvec.hpp"
#include "core/value.hpp"
#include "evm/decoder.hpp"
#include "vm/facts.hpp"
#include "vm/vm.hpp"

namespace pan::vm {

using NodeId = u32;
inline constexpr NodeId NO_NODE = ~u32{0};

// an internal function's return address on its own stack (python
// RETURN_ADDRESS): a jump to it is the function's LEAVE. A private leaf of
// the VM's range (0x1e0..), never in a trace but by a contract's mistake.
inline constexpr Op kOpReturnAddress = Op(0x1e0);
inline constexpr Value kReturnAddress = Value::leaf(kOpReturnAddress);

// the last call of a path when it depends on the path (merged paths, a loop's
// head, after an internal call)
inline constexpr u32 kAmbiguousCall = ~u32{0};

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

struct Node {
    // --- where, and with what (python Node.__init__) ---
    u32 start = 0;      // the pc
    u32 sw = 0;         // a code switch's case node: 1 + k (python start ("switch", pc, k))
    bool safe = false;  // reached by a fall-through: no JUMPDEST check
    Value stack;        // LIST, bottom first
    Value condition;    // the condition it's reached under (True: none)
    PathFacts known;
    u32 last_call = 0;  // the call whose return data the path has (0: none yet)
    Value jd;           // LIST (start, sw, stack length, the jumpdests on the stack)

    // --- the tree ---
    NodeId prev = NO_NODE;
    u32 depth = 0;
    NodeId jump = NO_NODE;  // skew-binary jump pointer (O(log n) ancestors)
    std::pmr::vector<NodeId> next;

    // --- the trace ---
    End end = End::None;
    std::pmr::vector<Value> lines;
    u32 end_pc = 0;           // the pc of the instruction that ended the block
    Value cond;               // If
    NodeId a = NO_NODE;       // Jump: the child; If: the true branch
    NodeId b = NO_NODE;       // If: the false branch
    NodeId cont = NO_NODE;    // If: the continuation of the merged paths
    NodeId dest = NO_NODE;    // Loop, Goto: the node looped back to
    Value loop_stack;         // Loop: the stack it arrived with
    Value loop_folded;        // Loop: the folded stack (variables)
    std::pmr::vector<LoopVar> loop_vars;  // Loop: the variables
    Value setvars;            // Goto: TRACE of SETVAR lines

    // --- loops ---
    NodeId label = NO_NODE;  // python node.label: the head whose loop this node is the body of
    std::pmr::vector<LoopVar> begin_vars;  // (on a head) python begin_vars
    u32 loop_key = 0;        // python loop_key (0: none yet)
    u32 loop_id = 0;         // the LOOP_ID of its LABEL (0: none yet)
    SmallVec<Fact, 2> assumed_memory, rejected_memory;
    bool has_assumed = false;

    // --- merges ---
    bool merged = false;
    NodeId merge_point = NO_NODE;
    bool switched = false;

    // --- discovery ---
    i8 dispatch = -1;  // in_dispatcher, memoized
    u32 fsel = 0;      // FuncCall: the selector
    i64 ftarget = 0;   // FuncCall: where the function starts (-1: an invalid jump)

    explicit Node(std::pmr::memory_resource* r) : next(r), lines(r), loop_vars(r), begin_vars(r) {}
};

// what a run is for
struct RunSetup {
    u32 start = 0;
    Value stack;               // LIST
    PathFacts known;           // at start
    std::vector<Value> before; // lines before the function (python `before`: the fmp)
    bool just_fdests = false;  // discovery
    bool inside = false;       // an internal function's body
    bool verbose = false;
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
    NodeId root() const noexcept { return root_; }
    const CodeMap& map() const noexcept { return map_; }
    Value make_trace_of(NodeId n);  // the trace from n (a branch)
    bool is_dispatch(Value cond) const;

    // --- the exec machine's handlers (vm_exec: called by the block's run) ---
    // each returns false when the block ends there
    bool plain(u8 op, u32 pc);
    void push(const Insn& in);
    void dup(u32 n, u32 pc);
    void swap(u32 n, u32 pc);
    void jump(u32 pc);
    void jumpi(u32 pc, u32 next);
    void halt(u8 op, u32 pc);
    void unknown(u8 op, u32 pc);
    void split(u32 pc);     // a JUMPDEST in the middle: the next node starts there
    void fell_off(u32 pc);  // the end of the code: STOP
    bool underflow(u8 op, u32 pc);  // fewer words than op takes: INVALID, true
    void asm_line(const Insn& in);  // --verbose

private:
    friend struct BlockRun;
    // --- nodes ---
    NodeId new_node(u32 start, bool safe, Value stack, Value condition, const PathFacts& known, u32 last_call,
                    u32 sw = 0);
    Value jd_of(u32 start, u32 sw, Value stack) const;
    void set_prev(NodeId child, NodeId parent);
    NodeId ancestor_at(NodeId n, u32 depth) const;
    NodeId common_ancestor(NodeId a, NodeId b) const;
    bool below(NodeId n, NodeId p) const;  // n is p or under it
    bool attached(NodeId n) const;
    template <class F>
    void find_nodes(NodeId from, F&& f, std::pmr::vector<NodeId>& out) const;
    void unexpanded(std::pmr::vector<NodeId>& out) const;
    bool is_label(NodeId n) const { return nodes_[n].label != NO_NODE; }
    u32 loop_key(NodeId head);

    // --- a node's run (python Node.run, VM._run) ---
    void run_node(NodeId id);
    void exec_block(u32 start);
    void finish_halt(Value line, u32 pc);
    NodeId child_at(Value target, bool safe, Value condition, const PathFacts& known, u32 pc);
    void link(NodeId id);

    // --- effects ---
    void emit(Value line, u32 pc);
    Value pop() { Value v = st_.back(); st_.pop_back(); return v; }
    void push_value(Value v, u32 pc);
    Value fresh_tmp() { return Value::name(NameKind::TMP, ++counter_); }
    void snapshot(Op op, Value target, u32 pc);
    Value returndatasize(u32 pc);
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
    NodeId root_ = NO_NODE;

    // counters (python's, per VM)
    u32 counter_ = 0;        // TMP names
    u32 call_ids_ = 0;       // call ids
    u32 gas_reads_ = 0;      // GAS leaves (each read its own)
    u32 next_loop_key_ = 1;  // loop keys
    u32 next_loop_id_ = 1;   // LOOP_IDs
    u32 precompile_count_[9] = {};
    u32 node_count_ = 0;
    u32 frontier_ = 0;
    bool quit_ = false;
    bool complete_ = true;

    std::vector<InternalEntry> internal_;  // known and found (python self.internal)
    std::vector<InternalEntry> found_;
    std::vector<CallSite> calls_;
    std::vector<LoopInfo> loops_;
    // pending merges at loop heads (python pending_merges): (p, jd)
    std::vector<std::pair<NodeId, Value>> pending_;

    // --- the block being run ---
    NodeId cur_ = NO_NODE;
    SmallVec<Value, 64> st_;
    PathFacts known_;
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
    std::pmr::vector<NodeId> todo(res_);
    todo.push_back(from);
    while (!todo.empty()) {
        poll();
        NodeId n = todo.back();
        todo.pop_back();
        const Node& x = nodes_[n];
        if (f(x)) out.push_back(n);
        for (auto it = x.next.rbegin(); it != x.next.rend(); ++it) todo.push_back(*it);
    }
}

// python simplify_bool: the condition of a JUMPI without its BOOL
Value simplify_bool(Value e);
// python exp_size: the size of v as a tree, counted up to cap
u32 exp_size(Value v, u32 cap);

}  // namespace pan::vm
