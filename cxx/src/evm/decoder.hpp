// The EVM decoder, NaCl's way (nacl.md §7): one grammar generated from
// spec/evm.def (cxx/tools/gen_grammar.py -> $(B)/gen/src/evm/evm_grammar.rlh),
// several Ragel machines that give its class actions their bodies:
//
//   analysis.rl   the linear pass (NaCl's validator pass) -> CodeMap: bitmaps
//                 of 1 bit per code byte, the idioms (NaCl's superinstructions)
//   listing.rl    every instruction in order (the disassembler's walk)
//   exec_ref.rl   the reference exec machine: a block from a pc, an instruction
//                 at a time through a callback (NaCl's ProcessInstructionFunc).
//                 The VM's own exec machine (src/vm/vm_exec.rl, lot 5) copies its
//                 skeleton with inline handlers.
//   metadata.rl   the CBOR metadata tail (solc / vyper)
//   classes.rl    (tests) the class action the grammar fires for each opcode
//   text.cpp      `pancxx disasm` / `pancxx decode`, over listing and analysis
//
// Nothing per instruction is stored: an Insn is a 16-byte view into the code,
// handed from an action to its consumer and never kept (NaCl's struct
// Instruction). What persists is the CodeMap (3 bits per byte + the idioms).
//
// The grammar (for the consumers' .rl files):
//     alphtype unsigned char;  action imm_byte {...}  action insn_plain {...} ...
//     include evm_grammar "evm/evm_grammar.rlh";
//   defines, from spec/evm.def:
//     insn       one instruction: an alternative per opcode, a push followed by
//                its n immediate bytes (each with $imm_byte), the opcode's last
//                byte firing its class action - one of
//                  insn_plain insn_push insn_dup insn_swap insn_jump insn_jumpi
//                  insn_jumpdest insn_halt insn_unknown
//                (the class of kClass[op], core/ops_gen.hpp; a test checks they
//                agree). The consumer defines these 9 actions and imm_byte
//                BEFORE the include. `main := insn*;` has one final state, the
//                start state (proved: cxx/tests/evm_dfa_proof.py, run by make
//                check, with the analysis's idioms).
//     op_<name>  the bare bytes of each opcode, no actions (op_push2 = 0x61
//                any{2}); op_unknown; push_any (op_push0 | ... | op_push32):
//                the idioms' building blocks.
// Ragel orders the actions of a transition by where they were embedded, the
// star moving its start transitions' actions last, and merges duplicates: an
// action must not depend on running before or after another one of the same
// byte (the analysis computes everything from p and the bitmaps).
#pragma once

#include <array>
#include <bit>
#include <optional>
#include <span>
#include <string>
#include <vector>

#include "core/base.hpp"
#include "core/contract.hpp"
#include "core/evmint.hpp"
#include "core/ops.hpp"

namespace pan {

// ---------------------------------------------------------------------------
// Bitset: one bit per code byte (NaCl's valid_targets / jump_dests)

class Bitset {
public:
    Bitset() = default;
    explicit Bitset(usize nbits) : words_((nbits + 63) / 64), nbits_(nbits) {}

    [[nodiscard]] usize size() const noexcept { return nbits_; }
    // false past the end (any u64: a jump's target is a word)
    [[nodiscard]] bool test(u64 i) const noexcept { return i < nbits_ && (words_[i >> 6] >> (i & 63) & 1) != 0; }
    void set(usize i) noexcept { words_[i >> 6] |= u64{1} << (i & 63); }  // i < size()
    [[nodiscard]] usize count() const noexcept {
        usize n = 0;
        for (const u64 w : words_) n += usize(std::popcount(w));
        return n;
    }
    // the first set bit >= i (size() if none)
    [[nodiscard]] usize next(usize i) const noexcept {
        if (i >= nbits_) return nbits_;
        usize k = i >> 6;
        u64 w = words_[k] & (~u64{0} << (i & 63));
        while (w == 0) {
            if (++k == words_.size()) return nbits_;
            w = words_[k];
        }
        return (k << 6) + usize(std::countr_zero(w));
    }
    // the last set bit < i (size() if none)
    [[nodiscard]] usize prev(usize i) const noexcept {
        if (i > nbits_) i = nbits_;
        if (i == 0) return nbits_;
        usize k = (i - 1) >> 6;
        u64 w = words_[k] & (~u64{0} >> (63 - ((i - 1) & 63)));
        while (w == 0) {
            if (k == 0) return nbits_;
            w = words_[--k];
        }
        return (k << 6) + 63 - usize(std::countl_zero(w));
    }
    [[nodiscard]] std::span<const u64> words() const noexcept { return words_; }
    std::span<u64> words() noexcept { return words_; }

private:
    std::vector<u64> words_;
    usize nbits_ = 0;
};

// ---------------------------------------------------------------------------
// Insn: the view an action hands to its consumer (never stored)

struct Insn {
    u32 pc;          // the opcode's offset
    u8 op;           // the opcode byte: the IR's Op for an EVM instruction (rule 1)
    u8 imm_len;      // immediate bytes present (< imm_size only for a push the end cuts)
    u8 imm_size;     // kImm[op]: pc + 1 + imm_size is the next instruction
    u8 pad_ = 0;
    const u8* imm;   // its immediate's first byte, in the code (imm_len bytes readable)

    [[nodiscard]] u32 next_pc() const noexcept { return pc + 1 + imm_size; }
    [[nodiscard]] bool cut() const noexcept { return imm_len < imm_size; }
    [[nodiscard]] InsnClass cls() const noexcept { return kClass[op]; }
};
static_assert(sizeof(Insn) == 16);

// a push's value as the EVM reads it: big-endian, the bytes a cut push lacks
// zeroes (0 for PUSH0); any Insn: its immediate's bytes
[[nodiscard]] Word256 push_word(const Insn& in) noexcept;
// the same when it fits 64 bits
[[nodiscard]] std::optional<u64> push_u64(const Insn& in) noexcept;

// ---------------------------------------------------------------------------
// BlockEnd: how a block (a run of the exec machine from a node's pc) ends

enum class BlockEndKind : u8 {
    Jump,     // a JUMP at pc
    JumpI,    // a JUMPI at pc; next: the fall-through
    Halt,     // STOP, RETURN, REVERT, INVALID (0xfe), SELFDESTRUCT at pc (kClass Halt)
    Unknown,  // a byte that isn't an opcode at pc (python's UNKNOWN: the EVM's invalid)
    Split,    // a JUMPDEST at pc, not the block's first instruction: the next block starts there
    FellOff,  // the end of the code (the EVM's implicit STOP): pc = next = size; a push
              // the end cuts was handed over first
};

struct BlockEnd {
    BlockEndKind kind = BlockEndKind::FellOff;
    u8 op = 0;     // the last instruction's opcode (Split: 0x5b, FellOff: 0x00)
    u32 pc = 0;    // where the last instruction starts (Split: the JUMPDEST's)
    u32 next = 0;  // the pc after it: pc + 1 + kImm[op] (Split: = pc)
    friend bool operator==(const BlockEnd&, const BlockEnd&) = default;
};

// ---------------------------------------------------------------------------
// CodeMap: what the analysis pass finds - all that persists besides the bytes

enum class IdiomKind : u8 {
    StaticJump,   // PUSHn x; JUMP
    StaticJumpI,  // PUSHn x; JUMPI
    Selector,     // DUP1; PUSH4 sel; EQ; PUSH1..4 dest; JUMPI (solc's dispatcher)
};

// a static jump's target that doesn't fit 32 bits (the code is smaller)
inline constexpr u32 kFarTarget = 0xffffffff;

struct Idiom {
    IdiomKind kind;
    u32 first_pc;      // its first instruction: the push (static jumps), the DUP1 (selector)
    u32 last_pc;       // its last: the JUMP / JUMPI
    u32 target;        // where it jumps (the push before the jump): kFarTarget when >= 2^32
    u32 selector = 0;  // Selector: the PUSH4's value
    friend bool operator==(const Idiom&, const Idiom&) = default;
};

struct CodeMap {
    std::span<const u8> code;  // a view: the caller keeps the bytes
    Bitset insn_start;         // an instruction starts here
    Bitset jumpdest;           // a JUMPDEST instruction starts here (not a 0x5b of a push's data)
    Bitset static_dest;        // a static jump's target (< size)
    std::vector<Idiom> idioms;            // by where they end (static_jumpi before selector on a JUMPI)
    u32 ninsn = 0;                        // the instructions, a cut push included
    u32 njumpdest = 0;                    // jumpdest.count()
    bool fmp = false;                     // solidity's free memory pointer set first: the code
                                          // starts PUSH1 v (v >= 0x60), PUSH1 0x40, MSTORE
    std::optional<u32> cut_push;          // the push the end of the code cuts: its pc
    std::vector<u32> bad_static_jumps;    // static_dest & ~jumpdest, ascending (NaCl's
                                          // ProcessInvalidJumpTargets): targets < size only
    u32 metadata_start = 0;               // where the CBOR metadata tail starts; size() if none

    [[nodiscard]] u32 size() const noexcept { return u32(code.size()); }
    [[nodiscard]] bool is_jumpdest(u64 pc) const noexcept { return jumpdest.test(pc); }
    [[nodiscard]] bool is_insn_start(u64 pc) const noexcept { return insn_start.test(pc); }
    // the instruction at pc (an instruction start, < size)
    [[nodiscard]] Insn insn_at(u32 pc) const noexcept;
};

// The largest code the decoder takes: its pcs are u32, the code's size
// included (the CLI caps its input at 128 MiB of code; the python module
// doesn't). Every entry point below throws SizeLimit past it.
inline constexpr usize kMaxCodeSize = 0xffffffff;
void check_code_size(std::span<const u8> code);

// The analysis pass: one linear run of the analysis machine over the code.
// Throws std::bad_alloc, and SizeLimit past kMaxCodeSize.
[[nodiscard]] CodeMap analyse(std::span<const u8> code);

// python's loader.sets_free_memory_pointer (ContractShared::free_memory_pointer):
// the code starts as solidity's does - its first MSTORE, within its first 32
// instructions, writes a number in [0x60, 2^16) at 0x40, the stack before it
// made of pushes, dups, swaps and ADDRESS CALLVALUE CALLDATASIZE ISZERO EQ LT
// GT (their results unknown). CodeMap::fmp (the idiom) implies it.
[[nodiscard]] bool sets_free_memory_pointer(std::span<const u8> code);

// ---------------------------------------------------------------------------
// The machines with a callback (NaCl's ProcessInstructionFunc): the
// disassembler, the tests, and the skeleton lot 5's exec machine copies.

using InsnFunc = void (*)(const Insn& insn, void* data);

// every instruction from pc 0 to the end, in order (a cut push last, its
// imm_len short)
void for_each_insn(std::span<const u8> code, InsnFunc fn, void* data);

// The reference exec machine: from `start` (an instruction start < size, or
// size), every instruction of the block through fn (a JUMPDEST first one
// too), the block's end returned: JUMP / JUMPI / a halt / an unknown byte
// (each handed to fn first), a JUMPDEST that isn't the first instruction
// (Split: not handed to fn), the end of the code (FellOff: a cut push handed
// to fn first).
BlockEnd exec_block_ref(std::span<const u8> code, u32 start, InsnFunc fn, void* data);

// ---------------------------------------------------------------------------
// The CBOR metadata tail (solc, vyper): the last 2 bytes are the length of a
// CBOR map (solc) or of vyper's list just before them.

struct Metadata {
    Lang lang = Lang::Unknown;           // Solidity (solc, ipfs, bzzr0/1 keys), Vyper (vyper key)
    u32 start = 0;                       // where the CBOR item starts
    std::optional<std::array<u8, 3>> version;  // solc's "solc" bytes, vyper's [major, minor, patch]
    bool ipfs = false, bzzr0 = false, bzzr1 = false, experimental = false;
};

// the tail of the code, when it is one (nullopt otherwise)
[[nodiscard]] std::optional<Metadata> metadata(std::span<const u8> code);

// ---------------------------------------------------------------------------
// For the tests: what the grammar makes of each opcode, read from the machine
// `main := insn;` run on the opcode followed by zeroes

struct GrammarClass {
    InsnClass cls;     // the class action that fired (the last one, if several)
    u8 length;         // the byte it fired on, + 1: the instruction's length
    u8 actions;        // how many class actions fired (1)
    u8 imm_bytes;      // how many bytes had $imm_byte (kImm)
};
[[nodiscard]] std::array<GrammarClass, 256> grammar_classes();

// ---------------------------------------------------------------------------
// Text: the CLI's `disasm` and `decode` (byte-identical to panasm's)

namespace evm {

// panoramix's Loader.disasm(): "0x0, push1, 0x80\n" a line per instruction
[[nodiscard]] std::string disassemble(std::span<const u8> code);
// the same lines without their '\n' (Decompilation::asm_lines)
[[nodiscard]] std::vector<std::string> disassembly_lines(std::span<const u8> code);
// panasm decode: the decoder's findings, a fact a line
[[nodiscard]] std::string decode_report(std::span<const u8> code);

}  // namespace evm

}  // namespace pan
