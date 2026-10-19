// The decoder's small helpers: a push's value, the instruction at a pc.
#include "evm/decoder.hpp"

namespace pan {

Word256 push_word(const Insn& in) noexcept
{
    // the bytes present, then the missing ones as zeroes (a push the end cuts)
    u8 buf[32] = {};
    const u32 n = in.imm_size <= 32 ? in.imm_size : 32;
    const u32 have = in.imm_len < n ? in.imm_len : n;
    for (u32 i = 0; i < have; ++i) buf[i] = in.imm[i];
    return Word256::from_be(std::span<const u8>(buf, n));
}

std::optional<u64> push_u64(const Insn& in) noexcept
{
    u64 v = 0;
    for (u32 i = 0; i < in.imm_size; ++i) {
        if (v >> 56) return std::nullopt;
        v = v << 8 | (i < in.imm_len ? in.imm[i] : 0);
    }
    return v;
}

Insn CodeMap::insn_at(u32 pc) const noexcept
{
    const u8 op = code[pc];
    const u8 size = kImm[op];
    const usize rest = code.size() - pc - 1;
    return Insn{pc, op, u8(rest < size ? rest : size), size, 0, code.data() + pc + 1};
}

}  // namespace pan
