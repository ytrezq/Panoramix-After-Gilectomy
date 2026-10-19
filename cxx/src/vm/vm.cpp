// The symbolic VM's entry points: run_function (python decompiler.py's VM
// runs: a function from its entry, an internal function apart) and the
// encoding of the VM's entry state kept in EntryCondition::vm_state.
#include "vm/vm.hpp"

#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/platform.hpp"
#include "vm/entry.hpp"
#include "vm/vm_impl.hpp"

namespace pan::vm {

namespace {

Value opt(Value v) { return v.nil() ? Value::none() : v; }
Value unopt(Value v) { return v.is_none() ? Value() : v; }

}  // namespace

Value encode_state(Value stack, const Facts& known) {
    SmallVec<Fact, 32> v;
    known.to_vector(v);
    SmallVec<Value, 32> facts;
    for (const Fact& f : v) {
        Value c = f.kind == FactKind::Cond ? Value::none() : opt(f.c);  // (a condition's c: a cache)
        facts.push_back(mk_list({Value::small(i64(f.kind)), opt(f.a), opt(f.b), c}));
    }
    return mk_list({stack, mk_list(facts.span())});
}

bool decode_state(Value state, Value& stack, Facts& known) {
    if (!state.is_list() || state.size() != 2 || !state[0].is_list() || !state[1].is_list()) return false;
    stack = state[0];
    SmallVec<Fact, 32> v;
    const Value facts = state[1];
    for (Value f : facts.args()) {
        if (!f.is_list() || f.size() != 4 || !f[0].is_small()) return false;
        i64 k = f[0].small_val();
        if (k < i64(FactKind::Cond) || k > i64(FactKind::VarBits)) return false;
        v.push_back(Fact{FactKind(k), unopt(f[1]), unopt(f[2]), unopt(f[3])});
    }
    known = Facts();
    for (const Fact& f : v) known = known.with(f);  // (a condition gets its cache back)
    return true;
}

i64 vm_deadline(i64 timeout_ns, i64 base_ns) {
    i64 t = timeout_ns ? timeout_ns : scaled_timeout(base_ns);
    if (t <= 0 || t >= limits::NO_TIMEOUT_NS) return 0;
    return platform::monotonic_ns() + t;
}

VmResult run_function(const ContractShared& contract, const FunctionInfo& fn, const VmOptions& opts) {
    if (!contract.map) throw Unsupported("vm: no code map");
    RunSetup s;
    s.verbose = opts.verbose;
    s.max_nodes = opts.max_nodes;
    s.deadline_ns = vm_deadline(opts.timeout_ns, limits::VM_TIMEOUT_NS);
    if (opts.known_internals) s.internal = *opts.known_internals;
    const CodeMap& map = *contract.map;

    if (fn.kind == FunctionInfo::Kind::Internal) {
        // its params where its calls push them, above the address it
        // returns to; nothing known of the memory nor of what ran before
        u32 nargs = u32(fn.params.size());
        bool known = false;
        for (const InternalEntry& e : s.internal)
            if (e.entry == fn.entry_pc) {
                nargs = e.nargs;
                known = true;
            }
        if (!known) s.internal.push_back(InternalEntry{fn.entry_pc, nargs, 0, 0});
        SmallVec<Value, 16> stack{kReturnAddress};
        for (u32 k = 0; k < nargs; ++k) stack.push_back(Value::name(NameKind::PARAM, k));
        s.start = fn.entry_pc;
        s.stack = mk_list(stack.span());
        s.inside = true;
        s.given = s.stack;
    } else {
        // the function's body, from where the dispatcher jumps (past its
        // JUMPDEST, as python does)
        u32 start = fn.entry_pc;
        if (start > 1 && map.is_jumpdest(start)) start += 1;
        s.start = start;
        Value stack;
        Facts known;
        if (!fn.entry.vm_state.nil() && decode_state(fn.entry.vm_state, stack, known)) {
            s.stack = stack;
            s.known = known;
        } else {
            // the entry isn't known: the free memory pointer assumed to be
            // 0x60, as the old compilers set it
            s.stack = mk_list({});
            if (contract.free_memory_pointer)
                s.before.push_back(mk(Op::SETMEM, mk(Op::RANGE, Value::small(0x40), Value::small(32)),
                                      mk(Op::SIZED, Value::small(32), Value::small(0x60))));
        }
        s.given = mk_list({fn.entry.vm_state.nil() ? Value::none() : fn.entry.vm_state,
                           fn.entry.entry_lines.nil() ? Value::none() : fn.entry.entry_lines});
    }

    Vm vm(contract, s);
    vm.explore();
    VmResult r;
    r.trace = vm.make_trace();
    r.calls = vm.calls_of(r.trace);
    r.loops = vm.loops();
    r.found_internals = vm.found();
    r.complete = vm.complete();
    r.nodes = vm.node_count();
    return r;
}

}  // namespace pan::vm
