// The reference exec machine (nacl.md §7.5, §7.9): a block of the code run
// from a node's pc, re-entering the machine in its start state - NaCl's
// restart at every bundle, here at every node. Its only final state is the
// start state (cxx/tests/evm_dfa_proof.py), so every instruction boundary is
// the start: entered at any instruction start, it decodes exactly as the
// linear pass. The actions hand each instruction to a callback (NaCl's
// ProcessInstructionFunc) and end the block with fbreak.
//
// This is the skeleton lot 5's src/vm/vm_exec.rl copies, with the VM's
// handlers inlined in place of the callback. It is used by the tests.
#include "evm/decoder.hpp"

namespace pan {

namespace {

%%{
    machine evm_exec_ref;
    alphtype unsigned char;

    action imm_byte {}
    action insn_plain { step(p); }
    action insn_push { step(p); }
    action insn_dup { step(p); }
    action insn_swap { step(p); }
    # a JUMPDEST starts a block: in the middle of one, it ends it (Split)
    action insn_jumpdest {
        if (ib != first) {
            out = {BlockEndKind::Split, *ib, pc_of(ib), pc_of(ib)};
            fbreak;
        }
        step(p);
    }
    action insn_jump { out = end(BlockEndKind::Jump, p); fbreak; }
    action insn_jumpi { out = end(BlockEndKind::JumpI, p); fbreak; }
    action insn_halt { out = end(BlockEndKind::Halt, p); fbreak; }
    action insn_unknown { out = end(BlockEndKind::Unknown, p); fbreak; }

    include evm_grammar "evm/evm_grammar.rlh";

    main := insn*;
}%%

%% write data noerror nofinal noentry;

}  // namespace

BlockEnd exec_block_ref(std::span<const u8> bytes, u32 start, InsnFunc fn, void* data)
{
    const u8* const code = bytes.data();
    const u32 size = u32(bytes.size());
    const u8* const first = code + start;
    const u8* p = first;
    const u8* const pe = code + size;
    const u8* ib = p;  // where the instruction being read starts
    const auto pc_of = [code](const u8* q) { return u32(q - code); };
    // the instruction from ib to last (its last byte), handed over
    const auto step = [&](const u8* last) {
        fn(Insn{pc_of(ib), *ib, u8(last - ib), kImm[*ib], 0, ib + 1}, data);
        ib = last + 1;
    };
    // the instruction that ends the block (one byte: last == ib)
    const auto end = [&](BlockEndKind kind, const u8* last) {
        step(last);
        return BlockEnd{kind, *(last), pc_of(last), pc_of(last + 1)};
    };
    BlockEnd out{BlockEndKind::FellOff, 0, size, size};
    int cs;
    %% write init;
    %% write exec;
    if (out.kind == BlockEndKind::FellOff && cs != evm_exec_ref_start)
        // a push the end cuts: its bytes so far, then the EVM's STOP
        fn(Insn{pc_of(ib), *ib, u8(pe - ib - 1), kImm[*ib], 0, ib + 1}, data);
    return out;
}

}  // namespace pan
