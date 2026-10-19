// What the grammar makes of each opcode, read from the machine itself: the
// class action that fires on the instruction it opens, and on which byte
// (the tests check them against core's kClass and kImm, which gen_ops.py
// derives from evm.def independently of gen_grammar.py).
#include "evm/decoder.hpp"

namespace pan {

namespace {

%%{
    machine evm_classes;
    alphtype unsigned char;

    action imm_byte { ++imm_bytes; }
    action insn_plain { fired(InsnClass::Plain, p); }
    action insn_push { fired(InsnClass::Push, p); }
    action insn_dup { fired(InsnClass::Dup, p); }
    action insn_swap { fired(InsnClass::Swap, p); }
    action insn_jump { fired(InsnClass::Jump, p); }
    action insn_jumpi { fired(InsnClass::JumpI, p); }
    action insn_jumpdest { fired(InsnClass::JumpDest, p); }
    action insn_halt { fired(InsnClass::Halt, p); }
    action insn_unknown { fired(InsnClass::Unknown, p); }

    include evm_grammar "evm/evm_grammar.rlh";

    main := insn;
}%%

%% write data noerror nofinal noentry;

}  // namespace

std::array<GrammarClass, 256> grammar_classes()
{
    std::array<GrammarClass, 256> out{};
    for (u32 op = 0; op < 256; ++op) {
        u8 buf[40] = {};  // the opcode, then zeroes for its immediate
        buf[0] = u8(op);
        GrammarClass g{InsnClass::Unknown, 0, 0, 0};
        u8 imm_bytes = 0;
        const auto fired = [&](InsnClass cls, const u8* at) {
            g.cls = cls;
            g.length = u8(at - buf + 1);
            ++g.actions;
        };
        const u8* p = buf;
        const u8* const pe = buf + sizeof buf;
        int cs;
        %% write init;
        %% write exec;
        (void)cs;
        g.imm_bytes = imm_bytes;
        out[op] = g;
    }
    return out;
}

}  // namespace pan
