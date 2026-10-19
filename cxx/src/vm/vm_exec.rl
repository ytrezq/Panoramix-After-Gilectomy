// The VM's exec machine (nacl.md §7.5, §7.9): lot 1's grammar with the VM's
// handlers bound statically (members of Vm, inlined by LTO) in place of the
// reference machine's callback (src/evm/exec_ref.rl). Re-entered at each
// node's start pc in its start state - the only final state, so every
// instruction boundary is the start and re-entry decodes as the linear pass
// does. A block ends at JUMP, JUMPI, a halt, an unknown byte, a JUMPDEST
// that isn't its first instruction (the next node starts there), or the end
// of the code (the EVM's STOP, after a push the end cuts).
#include "core/budget.hpp"
#include "vm/vm_impl.hpp"

namespace pan::vm {

namespace {

%%{
    machine vm_exec;
    alphtype unsigned char;

    action imm_byte {}
    action insn_plain {
        if (verbose) asm_line(insn_of(p));
        if (!plain(*ib, pc_of(ib))) { ended = true; fbreak; }
        ib = p + 1;
    }
    action insn_push {
        if (verbose) asm_line(insn_of(p));
        push(insn_of(p));
        ib = p + 1;
    }
    action insn_dup {
        if (verbose) asm_line(insn_of(p));
        if (underflow(*ib, pc_of(ib))) { ended = true; fbreak; }
        dup(u32(*ib - 0x7f), pc_of(ib));
        ib = p + 1;
    }
    action insn_swap {
        if (verbose) asm_line(insn_of(p));
        if (underflow(*ib, pc_of(ib))) { ended = true; fbreak; }
        swap(u32(*ib - 0x8f), pc_of(ib));
        ib = p + 1;
    }
    # a JUMPDEST starts a block: in the middle of one, it ends it
    action insn_jumpdest {
        if (ib != first) { split(pc_of(ib)); ended = true; fbreak; }
        ib = p + 1;
    }
    action insn_jump {
        if (verbose) asm_line(insn_of(p));
        jump(pc_of(ib)); ended = true; fbreak;
    }
    action insn_jumpi {
        if (verbose) asm_line(insn_of(p));
        jumpi(pc_of(ib), pc_of(p + 1)); ended = true; fbreak;
    }
    action insn_halt {
        if (verbose) asm_line(insn_of(p));
        halt(*ib, pc_of(ib)); ended = true; fbreak;
    }
    action insn_unknown {
        if (verbose) asm_line(insn_of(p));
        unknown(*ib, pc_of(ib)); ended = true; fbreak;
    }

    include evm_grammar "evm/evm_grammar.rlh";

    main := insn*;
}%%

%% write data noerror nofinal noentry;

}  // namespace

void Vm::exec_block(u32 start) {
    const u8* const code = code_.data();
    const u32 size = u32(code_.size());
    const u8* const first = code + start;
    const u8* p = first;
    const u8* const pe = code + size;
    const u8* ib = p;  // where the instruction being read starts
    const bool verbose = setup_.verbose;
    bool ended = false;
    const auto pc_of = [code](const u8* q) { return u32(q - code); };
    // the instruction from ib to last (its last byte)
    const auto insn_of = [&](const u8* last) {
        return Insn{pc_of(ib), *ib, u8(last - ib), kImm[*ib], 0, ib + 1};
    };
    int cs;
    %% write init;
    %% write exec;
    if (!ended) {
        // the end of the code: a push it cuts (zero padded), then STOP
        if (cs != vm_exec_start) {
            Insn in{pc_of(ib), *ib, u8(pe - ib - 1), kImm[*ib], 0, ib + 1};
            if (verbose) asm_line(in);
            push(in);
        }
        fell_off(size);
    }
}

}  // namespace pan::vm
