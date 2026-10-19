// The symbolic VM: nodes, a node's run, the handlers of the exec machine and
// the effects (python vm.py Node, VM._run, handle_jumps, apply_stack,
// snapshot, handle_call, output_write, call_data, code_switch).
#include <algorithm>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/intops.hpp"
#include "core/platform.hpp"
#include "vm/vm_impl.hpp"

namespace pan::vm {

// ---- helpers --------------------------------------------------------------------

Value simplify_bool(Value e) {
    check_stack();
    if (e.is(Op::ISZERO, 1)) {
        Value in = simplify_bool(e[0]);
        if (in.is(Op::ISZERO, 1)) return in[0];
        return alg::iszero(in);
    }
    if (e.is(Op::BOOL, 1)) return e[0];
    return e;
}

u32 exp_size(Value v, u32 cap) {
    // python's: every element of the tuples (heads included), as a tree
    SmallVec<Value, 32> todo{v};
    u32 n = 0;
    while (!todo.empty() && n <= cap) {
        Value x = todo.back();
        todo.pop_back();
        if (x.is_expr()) {
            ++n;
            for (Value a : x.args()) todo.push_back(a);
        } else if (x.is_list()) {
            for (Value a : x.args()) todo.push_back(a);
        } else {
            ++n;
        }
    }
    return n;
}

namespace {

Value small(i64 x) { return Value::small(x); }

Value range(Value start, Value len) { return mk(Op::RANGE, start, len); }
Value mem(Value start, Value len) { return mk(Op::MEM, range(start, len)); }

bool is_zero_int(Value v) { return v.is_int() && int_sign(v) == 0; }

// a substitution's pair (SmallVec holds plain values)
struct Subst {
    Value from, to;
};
// a code switch's case
struct Case {
    Value cond;
    NodeId n;
};

// x rebuilt with the values of `map` in place of the subterms they key (the
// outermost ones), normal again (python replace_f_stop + simplify)
template <class Map>
Value substitute(Value x, const Map& map) {
    check_stack();
    for (const auto& [from, to] : map)
        if (x == from) return to;
    if (!x.is_expr()) return x;
    SmallVec<Value, 8> args;
    bool changed = false;
    for (Value a : x.args()) {
        Value b = substitute(a, map);
        changed |= b != a;
        args.push_back(b);
    }
    if (!changed) return x;
    return alg::apply(x.op(), args.span());
}

// the state reads python's state_read knows: storage, tload, account
enum class ReadKind : u8 { None, Storage, Tload, Account };
ReadKind read_kind(Value e) {
    switch (e.op()) {
        case Op::STORAGE: return ReadKind::Storage;
        case Op::TLOAD: return ReadKind::Tload;
        case Op::BALANCE:
        case Op::EXTCODESIZE:
        case Op::EXTCODEHASH:
            return ReadKind::Account;
        default:
            return ReadKind::None;
    }
}

// python may_alias: two slots (or keys) that may be the same
bool may_alias(Value a, Value b) {
    if (a == b) return true;
    if (a.is_int() && b.is_int()) return false;
    return true;
}

// python changed_by: exp, a read of the state, may change with op (target:
// the slot / key written). The call results are numbered: never changed.
bool changed_by(Value e, Op op, Value target) {
    ReadKind k = read_kind(e);
    if (k == ReadKind::None) return false;
    switch (op) {
        case Op::SSTORE: return k == ReadKind::Storage && may_alias(e[2], target);
        case Op::TSTORE: return k == ReadKind::Tload && may_alias(e[0], target);
        case Op::STATICCALL: return false;
        case Op::CALL:
        case Op::CALLCODE:
        case Op::DELEGATECALL:
        case Op::CREATE:
        case Op::CREATE2:
            return true;
        default:
            return false;
    }
}

// python changed_reads: the reads in e that op may change, outermost first
void changed_reads(Value e, Op op, Value target, SmallVec<Value, 8>& out) {
    check_stack();
    if (!e.has_flags(F_STORAGE | F_STATE)) return;
    if (changed_by(e, op, target)) {
        if (std::find(out.begin(), out.end(), e) == out.end()) out.push_back(e);
        return;
    }
    for (Value a : e.children()) changed_reads(a, op, target, out);
}

// the precompiles python names (helpers.precompiled; 4, identity, apart)
bool is_precompile(u64 a) { return a == 1 || a == 2 || a == 3 || (a >= 5 && a <= 8); }

}  // namespace

// ---- the VM -----------------------------------------------------------------------

Vm::Vm(const ContractShared& contract, const RunSetup& setup)
    : contract_(contract),
      map_(*contract.map),
      code_(contract.code),
      setup_(setup),
      res_(cx().budget.resource()),
      nodes_(std::pmr::polymorphic_allocator<Node>(res_)),
      out_(res_) {
    internal_ = setup.internal;
}

Value Vm::jd_of(u32 start, u32 sw, Value stack) const {
    SmallVec<Value, 16> items{small(start), small(sw), small(stack.size())};
    for (Value v : stack.args())
        if (v.is_small() && v.small_val() >= 0 && map_.is_jumpdest(u64(v.small_val()))) items.push_back(v);
    return mk_list(items.span());
}

NodeId Vm::new_node(u32 start, bool safe, Value stack, Value condition, const PathFacts& known, u32 last_call,
                    u32 sw) {
    ++node_count_;
    NodeId id = NodeId(nodes_.size());
    Node& n = nodes_.emplace_back(res_);
    n.start = start;
    n.sw = sw;
    n.safe = safe;
    n.stack = stack;
    n.condition = condition;
    n.known = known;
    n.last_call = last_call;
    n.jd = jd_of(start, sw, stack);
    return id;
}

void Vm::set_prev(NodeId child, NodeId parent) {
    Node& c = nodes_[child];
    Node& p = nodes_[parent];
    c.prev = parent;
    c.depth = p.depth + 1;
    // skew-binary jump pointers (Myers): ancestors in O(log n)
    NodeId pj = p.jump;
    NodeId pjj = nodes_[pj].jump;
    if (p.depth - nodes_[pj].depth == nodes_[pj].depth - nodes_[pjj].depth && pj != parent)
        c.jump = pjj;
    else
        c.jump = parent;
    p.next.push_back(child);
}

NodeId Vm::ancestor_at(NodeId n, u32 depth) const {
    while (nodes_[n].depth > depth) {
        NodeId j = nodes_[n].jump;
        n = nodes_[j].depth >= depth ? j : nodes_[n].prev;
    }
    return n;
}

NodeId Vm::common_ancestor(NodeId a, NodeId b) const {
    u32 d = std::min(nodes_[a].depth, nodes_[b].depth);
    a = ancestor_at(a, d);
    b = ancestor_at(b, d);
    while (a != b) {
        NodeId ja = nodes_[a].jump, jb = nodes_[b].jump;
        if (ja != jb) {
            a = ja;
            b = jb;
        } else {
            a = nodes_[a].prev;
            b = nodes_[b].prev;
        }
    }
    return a;
}

bool Vm::below(NodeId n, NodeId p) const {
    if (nodes_[n].depth < nodes_[p].depth) return false;
    return ancestor_at(n, nodes_[p].depth) == p;
}

bool Vm::attached(NodeId n) const {
    while (n != root_) {
        poll();
        NodeId parent = nodes_[n].prev;
        if (parent == NO_NODE) return false;
        const auto& nx = nodes_[parent].next;
        if (std::find(nx.begin(), nx.end(), n) == nx.end()) return false;
        n = parent;
    }
    return true;
}

void Vm::unexpanded(std::pmr::vector<NodeId>& out) const {
    find_nodes(root_, [&](const Node& n) { return n.end == End::None; }, out);
}

u32 Vm::loop_key(NodeId head) {
    Node& h = nodes_[head];
    if (h.loop_key == 0) h.loop_key = next_loop_key_++;
    return h.loop_key;
}

// ---- a node's run --------------------------------------------------------------------

void Vm::run_node(NodeId id) {
    cur_ = id;
    Node& n = nodes_[id];
    st_.clear();
    for (Value v : n.stack.args()) st_.push_back(v);
    known_ = n.known;
    last_call_ = n.last_call;
    condition_ = n.condition;
    out_.clear();
    halted_ = false;
    n.lines.clear();
    n.next.clear();
    n.cont = NO_NODE;

    if (!internal_.empty() && internal_call_at(n.start, n.stack)) {
        internal_call(id);
        return;
    }
    const u32 size = map_.size();
    if (n.start >= size || !map_.is_insn_start(n.start)) {
        if (n.safe && n.start == size)
            finish_halt(mk(Op::STOP), n.start);
        else
            finish_halt(mk(Op::INVALID, small(i64(InvalidReason::JUMPDEST)), small(n.start)), n.start);
        return;
    }
    if (!n.safe && !map_.is_jumpdest(n.start)) {
        finish_halt(mk(Op::INVALID, small(i64(InvalidReason::JUMP)), small(n.start)), n.start);
        return;
    }
    exec_block(n.start);
}

void Vm::emit(Value line, u32 pc) {
    out_.push_back(line);
    cx().pcs.note(line, pc);
    if (line.is(Op::SETMEM, 2)) known_ = known_.write_memory(line[0][0], line[0][1], line[1]);
}

void Vm::finish_halt(Value line, u32 pc) {
    emit(line, pc);
    Node& n = nodes_[cur_];
    n.lines.assign(out_.begin(), out_.end());
    n.end = End::Halt;
    n.end_pc = pc;
    halted_ = true;
}

void Vm::link(NodeId id) {
    // python Node.run's end: the children go on from the node (link_if
    // through the ifs made in between: a code switch)
    Node& n = nodes_[id];
    switch (n.end) {
        case End::Jump:
            set_prev(n.a, id);
            break;
        case End::If:
            for (NodeId c : {n.a, n.b}) {
                set_prev(c, id);
                if (nodes_[c].end == End::If) link(c);
            }
            break;
        default:
            break;
    }
}

// a node for a jump to target (or the fall-through when safe): one already
// run when the jump can't go there (python makes it and runs it at once)
NodeId Vm::child_at(Value target, bool safe, Value condition, const PathFacts& known, u32 pc) {
    Value stack = mk_list(st_.span());
    auto done = [&](Value line, u32 at) {
        ++node_count_;
        NodeId id = NodeId(nodes_.size());
        Node& n = nodes_.emplace_back(res_);
        n.start = at;
        n.safe = safe;
        n.stack = stack;
        n.condition = condition;
        n.known = known;
        n.last_call = last_call_;
        n.jd = mk_list({small(-1), small(id)});  // (its own: never a loop's, nor a merge's)
        n.lines.push_back(line);
        cx().pcs.note(line, pc);
        n.end = End::Halt;
        n.end_pc = pc;
        return id;
    };
    const u32 size = map_.size();
    if (target.is_small() && target.small_val() >= 0) {
        i64 t = target.small_val();
        if (t < i64(size) && map_.is_insn_start(u64(t))) {
            if (safe || map_.is_jumpdest(u64(t)))
                return new_node(u32(t), safe, stack, condition, known, last_call_);
            return done(mk(Op::INVALID, small(i64(InvalidReason::JUMP)), target), u32(t));
        }
        if (safe && t == i64(size)) return done(mk(Op::STOP), u32(t));
        return done(mk(Op::INVALID, small(i64(InvalidReason::JUMPDEST)), target), pc);
    }
    if (target.is_int()) return done(mk(Op::INVALID, small(i64(InvalidReason::JUMPDEST)), target), pc);
    return done(mk(Op::UNDEFINED, small(i64(UndefinedReason::COMPUTED_JUMP)), small(pc)), pc);
}

// ---- the handlers ------------------------------------------------------------------------

bool Vm::underflow(u8 op, u32 pc) {
    if (st_.size() >= kStackIn[op]) return false;
    // fewer words than the instruction takes: it halts, as an invalid one
    finish_halt(mk(Op::INVALID, small(i64(InvalidReason::STACK_UNDERFLOW)), small(pc)), pc);
    return true;
}

void Vm::asm_line(const Insn& in) {
    Value imm = Value::none();
    if (kClass[in.op] == InsnClass::Push) imm = push_word(in).to_value();
    Value line = mk(Op::ASM, small(in.pc), small(in.op), imm, mk_list(st_.span()));
    out_.push_back(line);
    cx().pcs.note(line, in.pc);
}

void Vm::push(const Insn& in) { st_.push_back(push_word(in).to_value()); }

void Vm::dup(u32 n, u32) { st_.push_back(st_[st_.size() - n]); }

void Vm::swap(u32 n, u32) { std::swap(st_[st_.size() - 1], st_[st_.size() - 1 - n]); }

void Vm::push_value(Value v, u32 pc) {
    st_.push_back(v);
    // Some arithmetic (the Newton iterations of mulDiv) makes expressions
    // grow exponentially, and the algebra with them: the big ones get a
    // name, as memory reads do (python MAX_EXP_SIZE)
    if (v.is_expr() && exp_size(v, limits::MAX_EXP_SIZE + 1) > limits::MAX_EXP_SIZE) {
        Value t = fresh_tmp();
        emit(mk(Op::SETVAR, t, v), pc);
        st_.back() = t;
    }
}

void Vm::split(u32 pc) {
    // a JUMPDEST in the middle of the block: the next node starts there
    NodeId c = new_node(pc, false, mk_list(st_.span()), condition_, known_, last_call_);
    Node& n = nodes_[cur_];
    n.lines.assign(out_.begin(), out_.end());
    n.end = End::Jump;
    n.end_pc = pc;
    n.a = c;
    link(cur_);
}

void Vm::fell_off(u32 pc) {
    // past the last instruction: the code stops there
    finish_halt(mk(Op::STOP), pc);
}

void Vm::jump(u32 pc) {
    if (underflow(u8(Op::JUMP), pc)) return;
    Value target = pop();
    if (target == kReturnAddress) {
        // the end of the internal function decompiled apart: what's on the
        // stack, its results
        finish_halt(mk(Op::LEAVE, mk_list(st_.span())), pc);
        return;
    }
    NodeId c = child_at(target, false, condition_, known_, pc);
    Node& n = nodes_[cur_];
    n.lines.assign(out_.begin(), out_.end());
    n.end = End::Jump;
    n.end_pc = pc;
    n.a = c;
    link(cur_);
}

void Vm::jumpi(u32 pc, u32 next) {
    if (underflow(u8(Op::JUMPI), pc)) return;
    Value target = pop();
    Value cond = simplify_bool(pop());
    Value neg = alg::iszero(cond);
    NodeId t = child_at(target, false, cond, known_.with_cond(cond), pc);
    NodeId f = child_at(small(next), true, neg, known_.with_cond(neg), pc);

    if (setup_.just_fdests) {
        if (auto test = selector_test(cond)) {
            auto [sel, taken] = *test;
            Node& x = nodes_[taken ? t : f];
            x.lines.clear();
            x.end = End::FuncCall;
            x.fsel = sel;
            if (taken) {
                // where a jump can't go: the function is that invalid jump
                x.ftarget = target.is_small() && target.small_val() >= 0 &&
                                    map_.is_jumpdest(u64(target.small_val()))
                                ? target.small_val()
                                : -1;
            } else {
                x.ftarget = next;
            }
        }
    }

    std::optional<bool> decided;
    if (auto w = alg::eval_const(cond)) decided = !w->is_zero();
    if (!decided) decided = known_.is_known(cond);

    Node& n = nodes_[cur_];
    n.lines.assign(out_.begin(), out_.end());
    n.end_pc = pc;
    if (decided) {
        n.end = End::Jump;
        n.a = *decided ? t : f;
    } else {
        n.end = End::If;
        n.cond = cond;
        n.a = t;
        n.b = f;
    }
    link(cur_);
}

void Vm::halt(u8 op, u32 pc) {
    if (underflow(op, pc)) return;
    switch (Op(op)) {
        case Op::STOP:
            finish_halt(mk(Op::STOP), pc);
            return;
        case Op::RETURN:
        case Op::REVERT: {
            Value p = pop();
            Value n = pop();
            if (is_zero_int(n)) {
                // returning nothing is stopping; reverting with nothing is no data
                finish_halt(Op(op) == Op::RETURN ? mk(Op::STOP) : mk(Op::REVERT, Value::none()), pc);
            } else {
                finish_halt(mk(Op(op), mem(p, n)), pc);
            }
            return;
        }
        case Op::SELFDESTRUCT:
            finish_halt(mk(Op::SELFDESTRUCT, pop()), pc);
            return;
        default:
            finish_halt(mk(Op::INVALID, small(i64(InvalidReason::OPCODE)), small(pc)), pc);
            return;
    }
}

void Vm::unknown(u8, u32 pc) { finish_halt(mk(Op::INVALID, small(i64(InvalidReason::OPCODE)), small(pc)), pc); }

Value Vm::returndatasize(u32 pc) {
    if (known_.rdzero()) return small(0);
    if (last_call_ == kAmbiguousCall) {
        finish_halt(mk(Op::UNDEFINED, small(i64(UndefinedReason::AMBIGUOUS_CALL)), small(pc)), pc);
        return Value();
    }
    return Value::leaf(Op::RETURNDATASIZE, last_call_);
}

// Before an instruction that changes the state, what was read from it and
// is still on the stack (or in what the memory was written with) gets a
// variable: afterwards the read stands for what's there then (python
// snapshot). All read at once, before the instruction, the outermost read
// replaced.
void Vm::snapshot(Op op, Value target, u32 pc) {
    SmallVec<Value, 8> reads;
    for (Value item : st_) changed_reads(item, op, target, reads);
    {
        SmallVec<Fact, 32> v;
        known_.to_vector(v);
        for (const Fact& f : v)
            if (f.kind == FactKind::Mem && !f.c.nil()) changed_reads(f.c, op, target, reads);
    }
    if (reads.empty()) return;
    // the smaller first: a read inside another gets its name first
    std::stable_sort(reads.begin(), reads.end(),
                     [](Value a, Value b) { return exp_size(a, 1u << 20) < exp_size(b, 1u << 20); });
    SmallVec<Subst, 8> names;
    for (Value r : reads) {
        Value t = fresh_tmp();
        emit(mk(Op::SETVAR, t, substitute(r, names)), pc);
        names.push_back(Subst{r, t});
        u32 b = max_value_bits(r, nullptr);
        // what it was is as small as that (a size): for where memory is
        // written, not to decide conditions
        if (b <= 128) known_ = known_.with_var_bits(t, b);
    }
    for (Value& item : st_) item = substitute(item, names);
    known_ = known_.map_mem_values([&](Value v) { return substitute(v, names); });
}

std::pair<Value, Value> Vm::call_data(Value arg_start, Value arg_len) {
    // (selector, params): the 4 first bytes and the others when there are
    // 4 or more for sure; else (None, all of them); (None, None): no data
    if (is_zero_int(arg_len)) return {Value::none(), Value::none()};
    if (arg_len == small(4)) return {mem(arg_start, small(4)), Value::none()};
    bool split = false;
    if (arg_len.is_int()) split = int_cmp(arg_len, small(4)) > 0;
    if (split)
        return {mem(arg_start, small(4)), mem(alg::add(arg_start, small(4)), alg::sub(arg_len, small(4)))};
    return {Value::none(), mem(arg_start, arg_len)};
}

// What a call returns, written to the ret_len bytes of memory at ret_start:
// min(ret_len, its return data's size) of them - the others stay as they
// were. Where the memory is known to be zeroes, the return data padded with
// zeroes (python output_write).
void Vm::output_write(u32 id, Value ret_start, Value ret_len, u32 pc) {
    if (auto w = alg::eval_const(ret_len); w && w->is_zero()) return;
    if (known_.known_zeroes(ret_start, ret_len)) {
        emit(mk(Op::SETMEM, range(ret_start, ret_len), mk(Op::RETURNDATA_BYTES, small(id), small(0), ret_len)), pc);
        return;
    }
    Value size = alg::min({ret_len, Value::leaf(Op::RETURNDATASIZE, id)});
    emit(mk(Op::SETMEM, range(ret_start, size), mk(Op::RETURNDATA_BYTES, small(id), small(0), size)), pc);
}

void Vm::handle_call(u8 op, u32 pc) {
    Value gas = pop();
    Value addr = pop();
    Value value = (Op(op) == Op::CALL || Op(op) == Op::CALLCODE) ? pop() : small(0);
    Value arg_start = pop(), arg_len = pop(), ret_start = pop(), ret_len = pop();
    const u32 id = ++call_ids_;
    const bool plain_call = Op(op) == Op::CALL || Op(op) == Op::STATICCALL;
    auto a = addr.is_small() && addr.small_val() >= 0 ? std::optional<u64>(u64(addr.small_val())) : std::nullopt;

    if (plain_call && a && *a == 4) {
        // identity: its return data is what it's given, as much of it as
        // there's room for written (and what the next returndatacopy copies)
        calls_.push_back({id, Op::PRECOMPILED, pc});
        Value args = mem(arg_start, arg_len);
        emit(mk(Op::PRECOMPILED, small(id), Value::name(NameKind::PRECOMPILE, 4u << 24), small(4), args), pc);
        Value size;
        if (ret_len == arg_len)
            size = ret_len;
        else if (ret_len.is_int() && arg_len.is_int())
            size = int_cmp(ret_len, arg_len) <= 0 ? ret_len : arg_len;
        else
            size = alg::min({ret_len, arg_len});
        auto w = alg::eval_const(size);
        if (!(w && w->is_zero())) emit(mk(Op::SETMEM, range(ret_start, size), mem(arg_start, size)), pc);
        last_call_ = id;
        push_value(Value::leaf(Op::CALL_SUCCESS, id), pc);
        return;
    }
    if (plain_call && a && is_precompile(*a)) {
        calls_.push_back({id, Op::PRECOMPILED, pc});
        Value args = mem(arg_start, arg_len);
        // a name for each result: signer, signer2... (sha256 and ripemd160
        // share theirs: hash, hash2...)
        u32 base = *a == 3 ? 2 : u32(*a);
        u32 k = ++precompile_count_[base];
        Value name = Value::name(NameKind::PRECOMPILE, u32(*a) << 24 | k);
        emit(mk(Op::PRECOMPILED, small(id), name, small(i64(*a)), args), pc);
        last_call_ = id;
        if (ret_len == small(32) && known_.known_zeroes(ret_start, small(32))) {
            // the word it returns, or zeroes (ecrecover of a wrong signature
            // returns nothing): the result
            emit(mk(Op::SETMEM, range(ret_start, small(32)), name), pc);
        } else {
            output_write(id, ret_start, ret_len, pc);
        }
        push_value(Value::leaf(Op::CALL_SUCCESS, id), pc);
        return;
    }
    calls_.push_back({id, Op(op), pc});
    auto [sel, params] = call_data(arg_start, arg_len);
    switch (Op(op)) {
        case Op::CALL:
        case Op::CALLCODE:
            emit(mk(Op(op), {small(id), gas, addr, value, sel, params}), pc);
            break;
        default:
            emit(mk(Op(op), {small(id), gas, addr, sel, params}), pc);
            break;
    }
    last_call_ = id;
    push_value(Value::leaf(Op::CALL_SUCCESS, id), pc);
    output_write(id, ret_start, ret_len, pc);
}

Value Vm::code_bytes(Value pos, Value len) const {
    if (pos.is_small() && len.is_small() && pos.small_val() >= 0 && len.small_val() >= 0 &&
        len.small_val() <= i64(limits::MAX_CODECOPY_SIZE)) {
        // the bytes of the code, and zeroes past its end (solc fills a new
        // array with them, copying from codesize)
        const u64 p = u64(pos.small_val()), n = u64(len.small_val());
        SmallVec<u8, 64> bytes;
        bytes.resize(n);
        for (u64 i = 0; i < n; ++i) bytes[i] = p + i < code_.size() ? code_[p + i] : 0;
        if (n <= 32) return mk_int_be(bytes.span());
        return mk_bytes(bytes.span());
    }
    return mk(Op::CODE_BYTES, pos, len);
}

bool Vm::plain(u8 op8, u32 pc) {
    if (underflow(op8, pc)) return false;
    const Op op = Op(op8);

    // what the instruction may change is read first, then forgotten
    switch (op) {
        case Op::SSTORE:
        case Op::TSTORE:
            snapshot(op, st_.back(), pc);
            known_ = known_.forget(op == Op::SSTORE ? Forget::Storage : Forget::Tload);
            break;
        case Op::CALL:
        case Op::STATICCALL:
        case Op::DELEGATECALL:
        case Op::CALLCODE:
        case Op::CREATE:
        case Op::CREATE2:
            snapshot(op, Value(), pc);
            // anything can happen in the callee, reentering this contract
            // and changing its storage included
            known_ = known_.forget(Forget::Volatile);
            break;
        default:
            break;
    }

    switch (op) {
        case Op::ADD: case Op::MUL: case Op::SUB: case Op::DIV: case Op::SDIV: case Op::MOD:
        case Op::SMOD: case Op::ADDMOD: case Op::MULMOD: case Op::EXP: case Op::SIGNEXTEND:
        case Op::LT: case Op::GT: case Op::SLT: case Op::SGT: case Op::EQ: case Op::ISZERO:
        case Op::AND: case Op::OR: case Op::XOR: case Op::NOT: case Op::BYTE: case Op::SHL:
        case Op::SHR: case Op::SAR: case Op::CLZ: {
            const u32 k = kStackIn[op8];
            SmallVec<Value, 4> args;
            for (u32 i = 0; i < k; ++i) args.push_back(pop());
            push_value(alg::apply(op, args.span()), pc);
            return true;
        }
        case Op::SHA3: {
            Value p = pop(), n = pop();
            Value t = fresh_tmp();
            emit(mk(Op::SETVAR, t, mk(Op::SHA3, mem(p, n))), pc);
            st_.push_back(t);
            return true;
        }
        case Op::ADDRESS: case Op::ORIGIN: case Op::CALLER: case Op::CALLVALUE: case Op::CALLDATASIZE:
        case Op::GASPRICE: case Op::COINBASE: case Op::TIMESTAMP: case Op::NUMBER: case Op::DIFFICULTY:
        case Op::GASLIMIT: case Op::CHAINID: case Op::BASEFEE: case Op::BLOBBASEFEE: case Op::GAS:
            st_.push_back(Value::leaf(op));
            return true;
        case Op::RETURNDATASIZE: {
            Value v = returndatasize(pc);
            if (v.nil()) return false;
            st_.push_back(v);
            return true;
        }
        case Op::CODESIZE:
            st_.push_back(small(i64(code_.size())));
            return true;
        case Op::SELFBALANCE:
            push_value(mk(Op::BALANCE, Value::leaf(Op::ADDRESS)), pc);
            return true;
        case Op::BALANCE: {
            Value a = pop();
            // (the address: the low 160 bits of the word, as printed)
            if (a.is(Op::MASK_SHL, 4) && a[0] == small(160) && a[1] == small(0) && a[2] == small(0)) a = a[3];
            push_value(mk(Op::BALANCE, a), pc);
            return true;
        }
        case Op::EXTCODESIZE: case Op::EXTCODEHASH: case Op::BLOCKHASH: case Op::BLOBHASH:
        case Op::CALLDATALOAD: case Op::TLOAD:
            push_value(mk(op, pop()), pc);
            return true;
        case Op::POP:
            st_.pop_back();
            return true;
        case Op::PC:
            st_.push_back(small(pc));
            return true;
        case Op::MSIZE: {
            Value t = fresh_tmp();
            emit(mk(Op::SETVAR, t, Value::leaf(Op::MSIZE)), pc);
            st_.push_back(t);
            return true;
        }
        case Op::MLOAD: {
            Value addr = pop();
            Value v = known_.read_memory(addr);
            if (!v.nil()) {
                push_value(v, pc);
            } else {
                Value t = fresh_tmp();
                emit(mk(Op::SETVAR, t, mem(addr, small(32))), pc);
                st_.push_back(t);
            }
            return true;
        }
        case Op::MSTORE: {
            Value addr = pop(), v = pop();
            emit(mk(Op::SETMEM, range(addr, small(32)), v), pc);
            return true;
        }
        case Op::MSTORE8: {
            Value addr = pop(), v = pop();
            // the lowest byte of v, into one byte of memory
            emit(mk(Op::SETMEM, range(addr, small(1)), mask_value(v, 8)), pc);
            return true;
        }
        case Op::SLOAD:
            push_value(mk(Op::STORAGE, small(256), small(0), pop()), pc);
            return true;
        case Op::SSTORE: {
            Value slot = pop(), v = pop();
            emit(mk(Op::STORE, small(256), small(0), slot, v), pc);
            return true;
        }
        case Op::TSTORE: {
            Value key = pop(), v = pop();
            emit(mk(Op::TSTORE, key, v), pc);
            return true;
        }
        case Op::MCOPY: {
            Value dst = pop(), src = pop(), n = pop();
            if (!is_zero_int(n)) emit(mk(Op::SETMEM, range(dst, n), mem(src, n)), pc);
            return true;
        }
        case Op::CALLDATACOPY: {
            Value dst = pop(), src = pop(), n = pop();
            if (!is_zero_int(n)) emit(mk(Op::SETMEM, range(dst, n), mk(Op::CALLDATA_BYTES, src, n)), pc);
            return true;
        }
        case Op::CODECOPY: {
            if (code_switch(pc)) return false;
            Value dst = pop(), src = pop(), n = pop();
            if (!is_zero_int(n)) emit(mk(Op::SETMEM, range(dst, n), code_bytes(src, n)), pc);
            return true;
        }
        case Op::EXTCODECOPY: {
            Value a = pop(), dst = pop(), src = pop(), n = pop();
            if (!is_zero_int(n)) emit(mk(Op::SETMEM, range(dst, n), mk(Op::EXTCODE_BYTES, a, range(src, n))), pc);
            return true;
        }
        case Op::RETURNDATACOPY: {
            Value dst = pop(), src = pop(), n = pop();
            // a copy of more than there is halts, as an invalid opcode does
            Value size = returndatasize(pc);
            if (size.nil()) return false;
            Value end = alg::add(src, n);
            Value beyond = alg::cmp(Op::LT, size, end);
            std::optional<bool> decided;
            if (auto w = alg::eval_const(beyond)) decided = !w->is_zero();
            if (!decided) decided = known_.is_known(beyond);
            if (!decided) {
                Value inv = mk(Op::INVALID, small(i64(InvalidReason::RETURNDATACOPY)), small(pc));
                cx().pcs.note(inv, pc);
                emit(mk(Op::IF, beyond, mk_trace({inv}), mk_trace({})), pc);
                known_ = known_.with_cond(alg::iszero(beyond));
            } else if (*decided) {
                finish_halt(mk(Op::INVALID, small(i64(InvalidReason::RETURNDATACOPY)), small(pc)), pc);
                return false;
            }
            if (!is_zero_int(n)) {
                u32 id = known_.rdzero() ? 0 : last_call_;
                emit(mk(Op::SETMEM, range(dst, n), mk(Op::RETURNDATA_BYTES, small(id), src, n)), pc);
            }
            return true;
        }
        case Op::LOG0: case Op::LOG1: case Op::LOG2: case Op::LOG3: case Op::LOG4: {
            Value p = pop(), s = pop();
            SmallVec<Value, 5> args{mem(p, s)};
            for (u32 i = 0; i < u32(op8 - u8(Op::LOG0)); ++i) args.push_back(pop());
            emit(mk(op, args.span()), pc);
            return true;
        }
        case Op::CALL: case Op::STATICCALL: case Op::DELEGATECALL: case Op::CALLCODE:
            handle_call(op8, pc);
            return true;
        case Op::CREATE: {
            Value wei = pop(), p = pop(), n = pop();
            const u32 id = ++call_ids_;
            calls_.push_back({id, Op::CREATE, pc});
            emit(mk(Op::CREATE, small(id), wei, mem(p, n)), pc);
            last_call_ = id;
            st_.push_back(Value::leaf(Op::CREATE_ADDRESS, id));
            return true;
        }
        case Op::CREATE2: {
            Value wei = pop(), p = pop(), n = pop(), salt = pop();
            const u32 id = ++call_ids_;
            calls_.push_back({id, Op::CREATE2, pc});
            emit(mk(Op::CREATE2, small(id), wei, mem(p, n), salt), pc);
            last_call_ = id;
            st_.push_back(Value::leaf(Op::CREATE_ADDRESS, id));
            return true;
        }
        default:
            // (an instruction the table calls plain that isn't one: never)
            throw InternalError("vm: unexpected plain instruction");
    }
}

// ---- Vyper's code switch ------------------------------------------------------------

namespace {

// (x, its values) for a part x of e of a few values: x % n, or a few of the
// bits of something (x & 1 is how Vyper's dispatcher takes x % 2) - python
// switch_values
bool switch_values(Value e, Value& m, SmallVec<Value, 16>& values) {
    check_stack();
    if (e.is(Op::MOD, 2) && e[1].is_small() && e[1].small_val() >= 2 && e[1].small_val() <= 256) {
        m = e;
        for (i64 k = 0; k < e[1].small_val(); ++k) values.push_back(Value::small(k));
        return true;
    }
    for (Value a : e.children())
        if (a.is_expr() && switch_values(a, m, values)) return true;
    return false;
}

bool switch_masks(Value e, Value& m, SmallVec<Value, 16>& values) {
    check_stack();
    if (e.is(Op::MASK_SHL, 4) && e[0].is_small() && e[1].is_small() && e[2].is_small() && e[0].small_val() >= 1 &&
        e[0].small_val() <= 8 && e[1].small_val() + e[2].small_val() >= 0 && !e[3].is_int()) {
        m = e;
        i64 sh = e[1].small_val() + e[2].small_val();
        for (i64 k = 0; k < (i64(1) << e[0].small_val()); ++k) {
            EvmInt v = EvmInt(k) << u64(sh);
            values.push_back(v.word().value());
        }
        return true;
    }
    for (Value a : e.children())
        if (a.is_expr() && switch_masks(a, m, values)) return true;
    return false;
}

}  // namespace

// A codecopy of a few bytes of the code from where one of few numbers says -
// x % n: Vyper's dispatcher (0.3.10 on) copies from a table where the code
// of a selector is, and jumps there. One path for each of the values, where
// the copy is from a known place. False if it's not that, or when x % n is
// known (python VM.code_switch).
bool Vm::code_switch(u32 pc) {
    if (st_.size() < 3) return false;
    Value mem_pos = st_[st_.size() - 1], code_pos = st_[st_.size() - 2], size = st_[st_.size() - 3];
    if (!(mem_pos.is_int() && size.is_small() && size.small_val() <= 32)) return false;
    if (code_pos.is_int()) return false;
    Value m;
    SmallVec<Value, 16> values;
    if (!switch_values(code_pos, m, values) && !switch_masks(code_pos, m, values)) return false;

    SmallVec<Value, 16> cases;
    for (Value k : values) {
        auto r = known_.is_known(alg::cmp(Op::EQ, m, k));
        if (!(r && !*r)) cases.push_back(k);
    }
    known_.each_newest_first([&](const Fact& f) {
        if (f.kind == FactKind::Cond && f.a.is(Op::EQ, 2) && f.a[0] == m && f.a[1].is_int()) {
            cases.clear();
            cases.push_back(f.a[1]);
            return false;
        }
        return true;
    });
    auto value = [&](Value k) {
        // the stack where m is k
        SmallVec<Subst, 1> map{Subst{m, k}};
        SmallVec<Value, 64> s;
        for (Value e : st_) s.push_back(substitute(e, map));
        return mk_list(s.span());
    };
    if (cases.size() < 2) {
        if (!cases.empty()) {
            Value s = value(cases[0]);
            st_.clear();
            for (Value e : s.args()) st_.push_back(e);
        }
        return false;
    }
    SmallVec<Case, 16> nodes;
    for (Value k : cases) {
        Value cond = alg::cmp(Op::EQ, m, k);
        NodeId n = new_node(pc, true, value(k), cond, known_.with_cond(cond), last_call_);
        // (not to be merged again: merged, what it copies wouldn't be known)
        nodes_[n].switched = true;
        nodes.push_back(Case{cond, n});
    }
    Value stack = mk_list(st_.span());
    NodeId rest = nodes.back().n;
    for (usize i = nodes.size() - 2; i >= 1; --i) {
        auto [cond, n] = nodes[i];  // (Case)
        NodeId r = new_node(pc, true, stack, Value(true), known_, last_call_, u32(i) + 1);
        Node& x = nodes_[r];
        x.end = End::If;
        x.end_pc = pc;
        x.cond = cond;
        x.a = n;
        x.b = rest;
        rest = r;
    }
    Node& self = nodes_[cur_];
    self.lines.assign(out_.begin(), out_.end());
    self.end = End::If;
    self.end_pc = pc;
    self.cond = nodes[0].cond;
    self.a = nodes[0].n;
    self.b = rest;
    link(cur_);
    halted_ = true;
    return true;
}

}  // namespace pan::vm
