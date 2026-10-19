// TEMPORARY: plain loops standing for the Ragel machines (analysis.rl,
// listing.rl, exec_ref.rl, metadata.rl) until the Makefile generates the
// grammar they include. Same results; deleted when the machines land.
#include "evm/decoder.hpp"

namespace pan {

namespace {

Insn insn_of(std::span<const u8> code, usize pc)
{
    const u8 op = code[pc];
    const u8 size = kImm[op];
    const usize rest = code.size() - pc - 1;
    return Insn{u32(pc), op, u8(rest < size ? rest : size), size, 0, code.data() + pc + 1};
}

// the push's value when < 2^32, else kFarTarget
u32 target_of(const Insn& in)
{
    const auto v = push_u64(in);
    return v && *v < kFarTarget ? u32(*v) : kFarTarget;
}

}  // namespace

CodeMap analyse(std::span<const u8> code)
{
    CodeMap m;
    m.code = code;
    const usize n = code.size();
    m.insn_start = Bitset(n);
    m.jumpdest = Bitset(n);
    m.static_dest = Bitset(n);
    m.metadata_start = u32(n);
    // the last 5 instructions, for the idioms
    Insn last[5] = {};
    usize count = 0;
    auto back = [&](usize k) -> const Insn& { return last[(count - 1 - k) % 5]; };
    for (usize pc = 0; pc < n;) {
        const Insn in = insn_of(code, pc);
        m.insn_start.set(pc);
        ++m.ninsn;
        last[count % 5] = in;
        ++count;
        if (in.op == 0x5b) m.jumpdest.set(pc);
        if (in.cut()) m.cut_push = u32(pc);
        if ((in.op == 0x56 || in.op == 0x57) && count >= 2 && kClass[back(1).op] == InsnClass::Push) {
            const u32 t = target_of(back(1));
            if (t < n) m.static_dest.set(t);
            m.idioms.push_back({in.op == 0x56 ? IdiomKind::StaticJump : IdiomKind::StaticJumpI, back(1).pc, in.pc, t});
        }
        if (in.op == 0x57 && count >= 5 && back(4).op == 0x80 && back(3).op == 0x63 && back(2).op == 0x14 &&
            back(1).op >= 0x60 && back(1).op <= 0x63)
            m.idioms.push_back({IdiomKind::Selector, back(4).pc, in.pc, target_of(back(1)), u32(*push_u64(back(3)))});
        pc += 1 + in.imm_size;
    }
    m.fmp = n >= 5 && code[0] == 0x60 && code[1] >= 0x60 && code[2] == 0x60 && code[3] == 0x40 && code[4] == 0x52;
    m.njumpdest = u32(m.jumpdest.count());
    for (usize w = 0; w < m.static_dest.words().size(); ++w) {
        u64 bad = m.static_dest.words()[w] & ~m.jumpdest.words()[w];
        while (bad) {
            m.bad_static_jumps.push_back(u32(w * 64 + usize(std::countr_zero(bad))));
            bad &= bad - 1;
        }
    }
    if (auto md = metadata(code)) m.metadata_start = md->start;
    return m;
}

void for_each_insn(std::span<const u8> code, InsnFunc fn, void* data)
{
    for (usize pc = 0; pc < code.size();) {
        const Insn in = insn_of(code, pc);
        fn(in, data);
        pc += 1 + in.imm_size;
    }
}

BlockEnd exec_block_ref(std::span<const u8> code, u32 start, InsnFunc fn, void* data)
{
    const u32 n = u32(code.size());
    for (u32 pc = start; pc < n;) {
        const Insn in = insn_of(code, pc);
        switch (kClass[in.op]) {
        case InsnClass::JumpDest:
            if (pc != start) return {BlockEndKind::Split, in.op, pc, pc};
            break;
        case InsnClass::Jump:
            fn(in, data);
            return {BlockEndKind::Jump, in.op, pc, pc + 1};
        case InsnClass::JumpI:
            fn(in, data);
            return {BlockEndKind::JumpI, in.op, pc, pc + 1};
        case InsnClass::Halt:
            fn(in, data);
            return {BlockEndKind::Halt, in.op, pc, pc + 1};
        case InsnClass::Unknown:
            fn(in, data);
            return {BlockEndKind::Unknown, in.op, pc, pc + 1};
        default:
            break;
        }
        fn(in, data);
        pc += 1 + in.imm_size;
    }
    return {BlockEndKind::FellOff, 0, n, n};
}

std::optional<Metadata> metadata(std::span<const u8>)
{
    return std::nullopt;
}

}  // namespace pan
