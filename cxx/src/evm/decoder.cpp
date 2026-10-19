// The decoder's small helpers: a push's value, the instruction at a pc,
// python's sets_free_memory_pointer, the size guard.
#include "evm/decoder.hpp"

#include "core/errors.hpp"

namespace pan {

void check_code_size(std::span<const u8> code)
{
    if (code.size() > kMaxCodeSize) [[unlikely]]
        throw SizeLimit("the code is larger than 4 GiB: its offsets don't fit 32 bits");
}

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

bool sets_free_memory_pointer(std::span<const u8> code)
{
    // the first 32 instructions are in the first 32 * 33 bytes
    constexpr usize kInsns = 32, kBytes = kInsns * 33;
    struct Walk {
        // the stack's words: a number below 2^64, or nullopt (unknown, or more)
        std::optional<u64> stack[kInsns];
        usize depth = 0, seen = 0;
        enum : u8 { Open, Yes, No } verdict = Open;
    } w;
    for_each_insn(
        code.first(code.size() < kBytes ? code.size() : kBytes),
        [](const Insn& in, void* data) {
            auto& w = *static_cast<Walk*>(data);
            if (w.verdict != Walk::Open || w.seen++ == kInsns) {
                if (w.verdict == Walk::Open) w.verdict = Walk::No;
                return;
            }
            const auto pop_push = [&](usize popped) {
                if (w.depth < popped) return false;
                w.depth -= popped;
                w.stack[w.depth++] = std::nullopt;
                return true;
            };
            switch (in.op) {
            case 0x52:  // mstore: of a number at 0x40?
                if (w.depth < 2) break;
                {
                    const auto addr = w.stack[w.depth - 1], value = w.stack[w.depth - 2];
                    w.verdict = addr == 0x40u && value && *value >= 0x60 && *value < 0x10000 ? Walk::Yes : Walk::No;
                }
                return;
            case 0x30: case 0x34: case 0x36:  // address, callvalue, calldatasize
                if (pop_push(0)) return;
                break;
            case 0x15:  // iszero
                if (pop_push(1)) return;
                break;
            case 0x10: case 0x11: case 0x14:  // lt, gt, eq
                if (pop_push(2)) return;
                break;
            default:
                switch (kClass[in.op]) {
                case InsnClass::Push: w.stack[w.depth++] = push_u64(in); return;
                case InsnClass::Dup: {
                    const usize n = usize(in.op - 0x7f);
                    if (w.depth < n) break;
                    w.stack[w.depth] = w.stack[w.depth - n];
                    ++w.depth;
                    return;
                }
                case InsnClass::Swap: {
                    const usize n = usize(in.op - 0x8f);
                    if (w.depth <= n) break;
                    std::swap(w.stack[w.depth - 1], w.stack[w.depth - 1 - n]);
                    return;
                }
                default: break;
                }
            }
            w.verdict = Walk::No;
        },
        &w);
    return w.verdict == Walk::Yes;
}

Insn CodeMap::insn_at(u32 pc) const noexcept
{
    const u8 op = code[pc];
    const u8 size = kImm[op];
    const usize rest = code.size() - pc - 1;
    return Insn{pc, op, u8(rest < size ? rest : size), size, 0, code.data() + pc + 1};
}

}  // namespace pan
