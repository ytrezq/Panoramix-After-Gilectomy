// The listing: every instruction of the code in order, through a callback
// (NaCl's decoder and its ProcessInstructionFunc) - the disassembler's and
// the decode report's walk. Every class action has the same body: the
// instruction that ends on this byte, handed over.
#include "evm/decoder.hpp"

namespace pan {

namespace {

%%{
    machine evm_listing;
    alphtype unsigned char;

    action imm_byte {}
    action insn_plain { emit(p); }
    action insn_push { emit(p); }
    action insn_dup { emit(p); }
    action insn_swap { emit(p); }
    action insn_jump { emit(p); }
    action insn_jumpi { emit(p); }
    action insn_jumpdest { emit(p); }
    action insn_halt { emit(p); }
    action insn_unknown { emit(p); }

    include evm_grammar "evm/evm_grammar.rlh";

    # one final state, the start: every instruction boundary is the start
    main := insn*;
}%%

%% write data noerror nofinal noentry;

}  // namespace

void for_each_insn(std::span<const u8> bytes, InsnFunc fn, void* data)
{
    const u8* const code = bytes.data();
    const u8* p = code;
    const u8* const pe = code + bytes.size();
    const u8* ib = p;  // where the instruction being read starts
    // the instruction from ib to last (its last byte), handed over
    const auto emit = [&](const u8* last) {
        fn(Insn{u32(ib - code), *ib, u8(last - ib), kImm[*ib], 0, ib + 1}, data);
        ib = last + 1;
    };
    int cs;
    %% write init;
    %% write exec;
    (void)cs;
    // a push the end cuts: its bytes so far
    if (ib != pe) fn(Insn{u32(ib - code), *ib, u8(pe - ib - 1), kImm[*ib], 0, ib + 1}, data);
}

}  // namespace pan
