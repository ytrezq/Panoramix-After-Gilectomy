// The discovery of the functions (python loader.py Loader.run, its
// selector_test, is_dispatch, entry_paths, reverts, common_entry,
// apply_entry, entry_known and vm.py's entry_memory, in_dispatcher): the VM
// on the dispatcher alone, then a walk of its tree - each selector test
// taken is a function, the paths to it give its entry (the memory written,
// the checks whose other branch reverts), the default function is where the
// dispatcher goes when no selector matches if that's always the same place.
#include <algorithm>

#include "algebra/construct.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/intops.hpp"
#include "core/order.hpp"
#include "vm/entry.hpp"
#include "vm/vm_impl.hpp"

namespace pan::vm {

namespace {

// v reads the selector word: CALLDATALOAD(0) anywhere in it (python's
// str(("cd", 0)) in str(v))
bool contains_cd0(Value v) {
    check_stack();
    if (!v.has_flags(F_CALLDATA)) return false;
    if (v.is(Op::CALLDATALOAD, 1) && v[0] == Value::small(0)) return true;
    for (Value a : v.children())
        if (contains_cd0(a)) return true;
    return false;
}

// a comparison of calldatasize with 3 or 4 (python: its leaves among
// calldatasize, 3, 4 and the ops lt gt le ge iszero bool)
bool size_test(Value v) {
    check_stack();
    if (v.is_bool() || v.is_none()) return true;
    if (v.is_int()) return v == Value::small(3) || v == Value::small(4);
    if (v.is_leaf()) return v.op() == Op::CALLDATASIZE && v.leaf_n() == 0;
    if (!v.is_expr()) return false;
    switch (v.op()) {
        case Op::LT: case Op::GT: case Op::LE: case Op::GE: case Op::ISZERO: case Op::BOOL:
            for (Value a : v.args())
                if (!size_test(a)) return false;
            return true;
        default:
            return false;
    }
}

// the selector word itself: (cd[0] >> 224) as a 32-bit field
bool is_selector_word(Value v) {
    return v.is(Op::MASK_SHL, 4) && v[0] == Value::small(32) && v[1] == Value::small(224) &&
           (v[2] == Value::small(0) || v[2] == Value::small(-224)) && v[3].is(Op::CALLDATALOAD, 1) &&
           v[3][0] == Value::small(0);
}

std::optional<u32> hash_of(Value v) {
    // a 4-byte number (a number past 4 bytes is no hash: a comparison of
    // more of the calldata)
    if (!v.is_small()) return std::nullopt;
    i64 x = v.small_val();
    if (x < 0 || x >= (i64(1) << 32)) return std::nullopt;
    return u32(x);
}

}  // namespace

bool Vm::is_dispatch(Value cond) const { return contains_cd0(cond) || size_test(cond); }

// (hash, taken) if cond compares the selector with a function's hash, taken
// being whether it holds when they're equal (python selector_test). The
// dispatcher jumps to a function when the selector equals its hash, or past
// it when they differ: a difference, zero if they're equal (a sub, a xor).
std::optional<std::pair<u32, bool>> Vm::selector_test(Value cond) const {
    check_stack();
    if (cond.is(Op::ISZERO, 1)) {
        auto r = selector_test(cond[0]);
        if (r) r->second = !r->second;
        return r;
    }
    // the selector itself, its being not 0: of the hash 0 (solc's optimizer
    // tests iszero(selector) for selector == 0)
    if (is_selector_word(cond)) return std::pair<u32, bool>{0, false};
    if (cond.is(Op::AND) || cond.is(Op::OR)) {
        // the selector is the hash and something else holds (Vyper from
        // 0.3.10: calldatasize > 3), or, negated, it isn't or something else
        // doesn't
        const bool taken = cond.is(Op::AND);
        std::optional<std::pair<u32, bool>> one;
        u32 count = 0;
        for (Value a : cond.args()) {
            auto t = selector_test(a);
            if (t && t->second == taken) {
                if (!one) one = t;
                ++count;
            }
        }
        return count == 1 ? one : std::nullopt;
    }
    if ((cond.is(Op::EQ, 2) || cond.is(Op::XOR, 2))) {
        for (int k = 0; k < 2; ++k) {
            Value num = cond[k], other = cond[1 - k];
            if (auto h = hash_of(num); h && contains_cd0(other)) return std::pair<u32, bool>{*h, cond.is(Op::EQ)};
        }
    }
    if (cond.is(Op::ADD, 2) && cond[0].is_int() && contains_cd0(cond[1])) {
        Value other = cond[1];
        Value num;
        if (other.is(Op::MUL, 2) && cond[1][0] == Value::small(-1)) {
            // num - selector
            num = cond[0];
            other = other[1];
        } else {
            // selector - (-num)
            num = Word256::from_value(int_neg(cond[0])).to_value();
        }
        if (auto h = hash_of(num); h && contains_cd0(other)) return std::pair<u32, bool>{*h, false};
    }
    return std::nullopt;
}

// every branch on the way to n is one of the dispatcher's: on the selector
// or on calldatasize - not one of a function's body
bool Vm::in_dispatcher(NodeId n) {
    SmallVec<NodeId, 64> chain;
    NodeId x = n;
    while (x != NO_NODE && nodes_[x].dispatch < 0) {
        chain.push_back(x);
        x = links_[x].prev;
    }
    bool res = x == NO_NODE || nodes_[x].dispatch > 0;
    for (usize i = chain.size(); i-- > 0;) {
        Node& m = nodes_[chain[i]];
        Value c = m.condition;
        bool own = c.is_bool() || c.is_int() || is_dispatch(c);
        res = res && own;
        m.dispatch = res ? 1 : 0;
    }
    return res;
}

namespace {

// an item of a function's entry (python's entry tuples): a SETMEM line, or
// a check ("check", cond, taken, other)
struct EntryItem {
    bool check = false;
    Value line;   // SETMEM
    Value cond;   // check
    bool taken = false;
    Value other;  // check: the trace of the branch not taken (it reverts)
    bool operator==(const EntryItem&) const = default;
};
using EntryPath = std::vector<EntryItem>;

struct Found {
    u32 sel;
    i64 target;
    Value stack;
};

class Discovery {
public:
    Discovery(Vm& vm, const ContractShared& c) : vm_(vm), contract_(c) {}

    std::vector<FunctionInfo> run();

private:
    const Node& node(NodeId n) const { return vm_.node(n); }
    // the lines of the chain from n, its last node
    NodeId chain_end(NodeId n) const {
        while (node(n).end == End::Jump) n = node(n).a;
        return n;
    }
    bool reverts(NodeId n) const;
    bool has_funccall(NodeId n) const;
    bool has_marker(NodeId n) const;
    template <class Leaf>
    void entry_paths(Leaf&& is_leaf, std::vector<std::pair<EntryPath, NodeId>>& out);
    Value other_trace(NodeId n);
    FunctionInfo make(FunctionInfo::Kind kind, u32 sel, i64 target, Value stack,
                      const std::vector<EntryPath>& paths, const std::vector<Value>& fallback_known);

    Vm& vm_;
    const ContractShared& contract_;
    std::vector<std::pair<NodeId, Value>> traces_;  // other_trace's memo
};

// python reverts: every path of the trace from n ends in REVERT or INVALID,
// without a function on the way
bool Discovery::reverts(NodeId start) const {
    SmallVec<NodeId, 16> todo{start};
    while (!todo.empty()) {
        poll();
        NodeId n = todo.back();
        todo.pop_back();
        // the trace of the branch: the lines of its chain, then how it ends;
        // its last line decides
        bool if_line = false;
        NodeId x = n;
        for (;;) {
            const Node& m = node(x);
            for (Value l : m.lines) if_line |= l.is(Op::IF);
            if (m.end == End::Jump) {
                x = m.a;
                continue;
            }
            break;
        }
        const Node& last = node(x);
        switch (last.end) {
            case End::If:
                // (no merge in the discovery: the IF is the last line)
                if (last.cont != NO_NODE) return false;
                todo.push_back(last.b);
                todo.push_back(last.a);
                continue;
            case End::Halt: {
                // REVERT or INVALID, without an IF before it
                Value l = last.lines.back();
                if (if_line || !(l.is(Op::REVERT) || l.is(Op::INVALID))) return false;
                continue;
            }
            default:
                // a function, a loop, what the VM didn't run: not a revert
                return false;
        }
    }
    return true;
}

bool Discovery::has_funccall(NodeId n) const {
    SmallVec<NodeId, 32> todo{n};
    while (!todo.empty()) {
        poll();
        NodeId x = todo.back();
        todo.pop_back();
        const Node& m = node(x);
        if (m.end == End::FuncCall) return true;
        for (NodeId c : m.next) todo.push_back(c);
    }
    return false;
}

// python _begin_trace's ("jd", pc, stack) marker of the discovery: a node at
// a JUMPDEST, or one whose trace starts with a jump (not a lone revert)
bool Discovery::has_marker(NodeId n) const {
    const Node& m = node(n);
    if (m.end == End::None) return false;
    if (m.sw == 0 && vm_.map().is_jumpdest(m.start)) return true;
    if (m.end == End::Halt && m.lines.size() == 1 && m.lines[0] == mk(Op::REVERT, Value::none())) return false;
    return m.lines.empty() && m.end == End::Jump;
}

Value Discovery::other_trace(NodeId n) {
    for (auto& [k, v] : traces_)
        if (k == n) return v;
    Value t = vm_.make_trace_of(n);
    traces_.push_back({n, t});
    return t;
}

// python entry_paths: (entry, leaf) for every node of the trace for which
// is_leaf, the entry being the SETMEMs and the checks on the way
template <class Leaf>
void Discovery::entry_paths(Leaf&& is_leaf, std::vector<std::pair<EntryPath, NodeId>>& out) {
    struct Todo {
        NodeId n;
        EntryPath entry;
    };
    std::vector<Todo> todo;
    todo.push_back({vm_.root(), {}});
    while (!todo.empty()) {
        poll();
        Todo t = std::move(todo.back());
        todo.pop_back();
        NodeId n = t.n;
        EntryPath entry = std::move(t.entry);
        while (n != NO_NODE) {
            const Node& m = node(n);
            if (is_leaf(n)) out.push_back({entry, n});
            if (m.end == End::None) break;
            // (the SETVARs too, unlike python: a variable of the dispatcher's
            // may be on the stack the function starts with)
            for (Value l : m.lines)
                if (l.is(Op::SETMEM, 2) || l.is(Op::SETVAR, 2)) entry.push_back(EntryItem{false, l, {}, false, {}});
            if (m.end == End::Jump) {
                n = m.a;
                continue;
            }
            if (m.end == End::If) {
                // its branches, the one taken first, then what follows it
                if (m.cont != NO_NODE) todo.push_back({m.cont, entry});
                for (int taken = 0; taken < 2; ++taken) {
                    NodeId branch = taken ? m.a : m.b;
                    NodeId other = taken ? m.b : m.a;
                    EntryPath be = entry;
                    if (!vm_.is_dispatch(m.cond) && reverts(other))
                        be.push_back(EntryItem{true, {}, m.cond, taken == 1, other_trace(other)});
                    todo.push_back({branch, std::move(be)});
                }
            }
            break;
        }
    }
}

FunctionInfo Discovery::make(FunctionInfo::Kind kind, u32 sel, i64 target, Value stack,
                             const std::vector<EntryPath>& paths, const std::vector<Value>& fallback_known) {
    FunctionInfo f;
    f.kind = kind;
    f.selector = kind == FunctionInfo::Kind::Selector ? sel : 0;
    f.entry_pc = target >= 0 && target < i64(0xffffffff) ? u32(target) : 0xffffffffu;
    if (kind == FunctionInfo::Kind::Selector) f.entry.selector = sel;

    // what all the paths to it start with (python common_entry)
    EntryPath common;
    if (!paths.empty()) {
        for (usize i = 0;; ++i) {
            bool same = i < paths[0].size();
            for (usize k = 1; k < paths.size() && same; ++k) same = i < paths[k].size() && paths[k][i] == paths[0][i];
            if (!same) break;
            common.push_back(paths[0][i]);
        }
    }
    // the entry lines: python apply_entry, flattened (the other branch of a
    // check halts)
    SmallVec<Value, 16> lines, checks;
    for (const EntryItem& it : common) {
        if (!it.check) {
            lines.push_back(it.line);
            continue;
        }
        Value empty = mk_trace({});
        Value l = it.taken ? mk(Op::IF, it.cond, empty, it.other) : mk(Op::IF, it.cond, it.other, empty);
        lines.push_back(l);
        checks.push_back(it.taken ? it.cond : alg::iszero(it.cond));
    }
    f.entry.entry_lines = mk_trace(lines.span());

    // what's known of the memory: what every path wrote, in a memory of
    // zeroes (python entry_memory)
    std::vector<Fact> res;
    std::vector<Fact> every;
    bool first = true;
    for (const EntryPath& p : paths) {
        Facts k = Facts().with_fresh();
        for (const EntryItem& it : p)
            if (!it.check && it.line.is(Op::SETMEM, 2))
                k = k.write_memory(it.line[0][0], it.line[0][1], alg::fact_value(it.line[1]));
        SmallVec<Fact, 32> v;
        k.to_vector(v);
        for (const Fact& x : v)
            if (std::find(every.begin(), every.end(), x) == every.end()) every.push_back(x);
        if (first) {
            res.assign(v.begin(), v.end());
            first = false;
        } else {
            std::erase_if(res, [&](const Fact& x) { return std::find(v.begin(), v.end(), x) == v.end(); });
        }
    }
    if (!res.empty()) {
        for (const Fact& x : every) {
            if (x.kind != FactKind::Mem || std::find(res.begin(), res.end(), x) != res.end()) continue;
            Fact u{FactKind::Mem, x.a, x.b, Value()};
            if (std::find(res.begin(), res.end(), u) == res.end()) res.push_back(u);
        }
        std::sort(res.begin(), res.end(), [](const Fact& a, const Fact& b) {
            if (a.kind != b.kind) return a.kind < b.kind;
            if (int c = compare(a.a, b.a)) return c < 0;
            if (int c = compare(a.b, b.b)) return c < 0;
            return compare(a.c, b.c) < 0;
        });
    } else {
        res.clear();
    }

    // the VM's facts at entry (python VM.run with an entry)
    std::vector<Value> conds = fallback_known;
    for (Value c : checks) conds.push_back(c);
    f.entry.checks = mk_list(std::span<const Value>(conds.data(), conds.size()));
    Facts known;
    for (Value c : conds) known = known.with_cond(c);
    if (target == 0 && common.empty()) known = known.with_fresh();
    for (const Fact& x : res)
        if (!known.contains(x)) known = known.with(x);
    // no call was made yet (the dispatcher makes none): no data returned
    known = known.with_rdzero();
    f.entry.vm_state = encode_state(stack, known);
    return f;
}

std::vector<FunctionInfo> Discovery::run() {
    // the functions, in the order of the trace (python find_f_list over it:
    // the true branch of an IF first)
    std::vector<Found> funcs;
    std::vector<Value> fallback_known;
    std::vector<std::optional<std::pair<u32, Value>>> starts;
    {
        SmallVec<NodeId, 64> todo{vm_.root()};
        while (!todo.empty()) {
            poll();
            NodeId n = todo.back();
            todo.pop_back();
            while (n != NO_NODE) {
                const Node& m = node(n);
                if (m.end == End::FuncCall) {
                    funcs.push_back({m.fsel, m.ftarget, m.stack});
                    break;
                }
                if (m.end == End::Jump) {
                    n = m.a;
                    continue;
                }
                if (m.end == End::If) {
                    // the conditions known in the default function: no
                    // selector matched (python selector_checks)
                    NodeId lt = chain_end(m.a), lf = chain_end(m.b);
                    if (node(lt).end == End::FuncCall)
                        fallback_known.push_back(alg::iszero(m.cond));
                    else if (node(lf).end == End::FuncCall)
                        fallback_known.push_back(m.cond);
                    // where the dispatch's branches without a function start
                    // (python default_starts)
                    if (vm_.is_dispatch(m.cond)) {
                        for (NodeId b : {m.a, m.b}) {
                            if (has_funccall(b)) continue;
                            if (has_marker(b))
                                starts.push_back(std::pair<u32, Value>{node(b).start, node(b).stack});
                            else
                                starts.push_back(std::nullopt);
                        }
                    }
                    if (m.cont != NO_NODE) todo.push_back(m.cont);
                    todo.push_back(m.b);
                    todo.push_back(m.a);
                }
                break;
            }
        }
    }

    // one per selector, in the order found (the last target found wins, as
    // python's dict)
    std::vector<Found> uniq;
    for (const Found& f : funcs) {
        auto it = std::find_if(uniq.begin(), uniq.end(), [&](const Found& g) { return g.sel == f.sel; });
        if (it == uniq.end())
            uniq.push_back(f);
        else
            *it = f;
    }
    std::vector<std::pair<EntryPath, NodeId>> leaves;
    entry_paths([&](NodeId n) { return node(n).end == End::FuncCall; }, leaves);

    std::vector<FunctionInfo> res;
    for (const Found& f : uniq) {
        std::vector<EntryPath> paths;
        for (const auto& [p, n] : leaves)
            if (node(n).fsel == f.sel) paths.push_back(p);
        res.push_back(make(FunctionInfo::Kind::Selector, f.sel, f.target, f.stack, paths, {}));
    }

    // the default function: where the dispatcher goes when no function
    // matches, if it's always the same place; else all of the dispatcher
    std::optional<std::pair<u32, Value>> deflt;
    if (!funcs.empty() && !starts.empty() && starts[0]) {
        bool same = true;
        for (const auto& s : starts) same = same && s && s->first == starts[0]->first;
        if (same) deflt = starts[0];
    }
    if (deflt) {
        const u32 target = deflt->first;
        std::vector<std::pair<EntryPath, NodeId>> fl;
        entry_paths([&](NodeId n) { return node(n).start == target && node(n).sw == 0 && has_marker(n); }, fl);
        std::vector<EntryPath> paths;
        for (auto& [p, n] : fl) paths.push_back(p);
        res.push_back(make(FunctionInfo::Kind::Fallback, 0, target, deflt->second, paths, {}));
    } else {
        res.push_back(make(FunctionInfo::Kind::Fallback, 0, 0, mk_list({}), {EntryPath{}}, fallback_known));
    }
    return res;
}

}  // namespace

std::vector<FunctionInfo> discover(const ContractShared& contract, Budget&) {
    if (!contract.map) throw Unsupported("vm: no code map");
    RunSetup s;
    s.start = 0;
    s.stack = mk_list({});
    s.known = Facts().with_fresh().with_rdzero();
    s.just_fdests = true;
    s.max_nodes = limits::MAX_FDESTS_NODE_COUNT;
    s.deadline_ns = vm_deadline(0, limits::LOADER_TIMEOUT_NS);
    try {
        Vm vm(contract, s);
        vm.explore();
        Discovery d(vm, contract);
        return d.run();
    } catch (const Unsupported&) {
    } catch (const InternalError&) {
    }
    // a dispatcher the VM can't read: the fallback alone, all of the code
    // (its entry unknown)
    FunctionInfo f;
    f.kind = FunctionInfo::Kind::Fallback;
    f.entry.checks = mk_list({});
    f.entry.entry_lines = mk_trace({});
    return {f};
}

}  // namespace pan::vm
