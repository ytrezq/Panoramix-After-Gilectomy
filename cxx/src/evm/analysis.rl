// The analysis pass (NaCl's validator pass): one linear run of a Ragel
// machine over the code, which fills the CodeMap - the instruction starts,
// the jumpdests, the static jumps' targets (bitmaps of a bit per byte) and
// the idioms (NaCl's superinstructions: unions with the instruction stream,
// their action on their last byte). Only the class action insn_jumpdest has
// a body here: the decoder/validator technique, the same grammar with other
// action bodies (listing.rl, exec_ref.rl, lot 5's vm_exec.rl).
//
// Ragel may run the actions of a byte in another order than written (a
// starred machine's start transitions run theirs last; duplicates merge):
// every action here reads only p and the bitmaps' bits below p.
#include "evm/decoder.hpp"

namespace pan {

namespace {

// the value of a push's immediate code[from, to) when it fits 32 bits (else
// kFarTarget, which no code reaches)
u32 small_value(const u8* from, const u8* to) noexcept
{
    u64 v = 0;
    for (; from < to; ++from) {
        if (v >> 32) return kFarTarget;
        v = v << 8 | *from;
    }
    return v < kFarTarget ? u32(v) : kFarTarget;
}

// The analysis's state beside the machine's (p, cs): the map being filled,
// the code's first byte
struct Analysis {
    CodeMap& m;
    const u8* code;
    usize n;

    // the start of the instruction before the one at pc (an idiom's: the
    // instructions are whole)
    u32 before(u32 pc) const noexcept { return u32(m.insn_start.prev(pc)); }

    // PUSHn x; JUMP(I) - the jump at pc
    void static_jump(IdiomKind kind, u32 pc)
    {
        const u32 push = before(pc);
        const u32 target = small_value(code + push + 1, code + pc);
        if (target < n) m.static_dest.set(target);
        m.idioms.push_back(Idiom{kind, push, pc, target, 0});
    }

    // DUP1; PUSH4 sel; EQ; PUSH1..4 dest; JUMPI - the jumpi at pc
    void selector(u32 pc)
    {
        const u32 dest = before(pc), eq = before(dest), push4 = before(eq), dup1 = before(push4);
        m.idioms.push_back(Idiom{IdiomKind::Selector, dup1, pc, small_value(code + dest + 1, code + pc),
                                 small_value(code + push4 + 1, code + eq)});
    }
};

%%{
    machine evm_analysis;
    alphtype unsigned char;

    action imm_byte {}
    action insn_plain {}
    action insn_push {}
    action insn_dup {}
    action insn_swap {}
    action insn_jump {}
    action insn_jumpi {}
    action insn_halt {}
    action insn_unknown {}
    # (a JUMPDEST is one byte: p is where it starts)
    action insn_jumpdest { jumpdests[usize(p - code) >> 6] |= u64{1} << (usize(p - code) & 63); }

    # an instruction starts at p
    action begin { starts[usize(p - code) >> 6] |= u64{1} << (usize(p - code) & 63); }

    action static_jump { a.static_jump(IdiomKind::StaticJump, u32(p - code)); }
    action static_jumpi { a.static_jump(IdiomKind::StaticJumpI, u32(p - code)); }
    action selector { a.selector(u32(p - code)); }
    action fmp { m.fmp = true; }

    include evm_grammar "evm/evm_grammar.rlh";

    # a jump to a number: where it goes is known
    static_jump = (push_any . op_jump) @static_jump;
    static_jumpi = (push_any . op_jumpi) @static_jumpi;

    # solc's dispatcher: the selector compared with a function's, the jump to
    # it if it is that one
    selector = (op_dup1 . op_push4 . op_eq . (op_push1 | op_push2 | op_push3 | op_push4) . op_jumpi) @selector;

    # solidity's free memory pointer, set first: mstore(0x40, v), v a PUSH1
    # of 0x60 at least
    fmp = (0x60 . 0x60..0xff . 0x60 . 0x40 . 0x52) @fmp;

    # the instructions one after the other, the idioms recognised among them
    # (made of whole instructions, they begin and end where instructions do:
    # cxx/tests/evm_dfa_proof.py); fmp? any* runs beside them over the code
    main := ((insn >begin) | static_jump | static_jumpi | selector)* | (fmp? . any*);
}%%

%% write data noerror nofinal noentry;

}  // namespace

CodeMap analyse(std::span<const u8> code_bytes)
{
    CodeMap m;
    const usize n = code_bytes.size();
    m.code = code_bytes;
    m.insn_start = Bitset(n);
    m.jumpdest = Bitset(n);
    m.static_dest = Bitset(n);
    m.metadata_start = u32(n);

    const u8* const code = code_bytes.data();
    u64* const starts = m.insn_start.words().data();
    u64* const jumpdests = m.jumpdest.words().data();
    Analysis a{m, code, n};

    const u8* p = code;
    const u8* const pe = code + n;
    int cs;
    %% write init;
    %% write exec;
    (void)cs;

    m.ninsn = u32(m.insn_start.count());
    // a push the end cuts: the last instruction, open
    if (const usize last = m.insn_start.prev(n); last < n && n - last < 1u + kImm[code[last]])
        m.cut_push = u32(last);
    m.njumpdest = u32(m.jumpdest.count());
    // the static jumps to no jumpdest (NaCl's ProcessInvalidJumpTargets),
    // word by word
    const auto dest = m.static_dest.words();
    const auto jd = m.jumpdest.words();
    for (usize w = 0; w < dest.size(); ++w)
        for (u64 bad = dest[w] & ~jd[w]; bad; bad &= bad - 1)
            m.bad_static_jumps.push_back(u32(w * 64 + usize(std::countr_zero(bad))));
    if (const auto md = metadata(code_bytes)) m.metadata_start = md->start;
    return m;
}

}  // namespace pan
