// The decoder's text: `disasm` (panoramix's Loader.disasm()) and `decode`
// (panasm's decoder report, NaCl's ncval for the EVM) - byte for byte the
// asm's (src/loader.s loader_disasm, src/decode_report.s decoder_report).
#include <charconv>
#include <string_view>

#include "evm/decoder.hpp"

namespace pan::evm {

namespace {

constexpr char kHex[] = "0123456789abcdef";

// python's hex(): 0x and the lowercase digits, no padding
void append_hex(std::string& s, u64 v)
{
    char buf[18];
    char* end = buf + sizeof buf;
    char* p = end;
    do {
        *--p = kHex[v & 15];
        v >>= 4;
    } while (v);
    *--p = 'x';
    *--p = '0';
    s.append(p, end);
}

// hex() of the big-endian number whose bytes are `bytes`, then `zeroes`
// zero bytes (a push the end cuts)
void append_hex_be(std::string& s, std::span<const u8> bytes, usize zeroes = 0)
{
    s += "0x";
    usize i = 0;
    while (i < bytes.size() && bytes[i] == 0) ++i;
    if (i == bytes.size()) {
        s += '0';
        return;
    }
    if (bytes[i] >> 4) s += kHex[bytes[i] >> 4];
    s += kHex[bytes[i] & 15];
    for (++i; i < bytes.size(); ++i) {
        s += kHex[bytes[i] >> 4];
        s += kHex[bytes[i] & 15];
    }
    s.append(2 * zeroes, '0');
}

void append_u(std::string& s, u64 v)
{
    char buf[24];
    auto [end, ec] = std::to_chars(buf, buf + sizeof buf, v);
    (void)ec;
    s.append(buf, end);
}

// the name the disassembly prints (evm.def's; python's UNKNOWN)
std::string_view name_of(u8 op)
{
    const OpInfo& i = info(Op(op));
    return i.defined ? std::string_view(i.name) : std::string_view("UNKNOWN");
}

// a line of Loader.disasm(), without its newline
void append_line(std::string& s, const Insn& in)
{
    append_hex(s, in.pc);
    s += ", ";
    s += name_of(in.op);
    s += ", ";
    switch (kClass[in.op]) {
    case InsnClass::Push:  // (python's param: the value, zeroes for what the end cuts)
        append_hex_be(s, std::span<const u8>(in.imm, in.imm_len), usize(in.imm_size - in.imm_len));
        break;
    case InsnClass::Unknown:  // (python's param: the byte)
        append_hex(s, in.op);
        break;
    default:  // (a dup's or a swap's n isn't printed)
        break;
    }
}

}  // namespace

std::string disassemble(std::span<const u8> code)
{
    std::string s;
    s.reserve(code.size() * 8);
    for_each_insn(
        code,
        [](const Insn& in, void* data) {
            auto& out = *static_cast<std::string*>(data);
            append_line(out, in);
            out += '\n';
        },
        &s);
    return s;
}

std::vector<std::string> disassembly_lines(std::span<const u8> code)
{
    std::vector<std::string> lines;
    for_each_insn(
        code,
        [](const Insn& in, void* data) {
            auto& out = *static_cast<std::vector<std::string>*>(data);
            append_line(out.emplace_back(), in);
        },
        &lines);
    return lines;
}

std::string decode_report(std::span<const u8> code)
{
    const CodeMap m = analyse(code);
    // what the report counts of the instructions: the bytes that aren't
    // opcodes, the jumps, the last instruction (a push the end cuts)
    struct Walk {
        std::vector<Insn> unknown;
        u64 jumps = 0;
    } w;
    for_each_insn(
        code,
        [](const Insn& in, void* data) {
            auto& walk = *static_cast<Walk*>(data);
            switch (kClass[in.op]) {
            case InsnClass::Unknown: walk.unknown.push_back(in); break;
            case InsnClass::Jump:
            case InsnClass::JumpI: ++walk.jumps; break;
            default: break;
            }
        },
        &w);

    std::string s;
    append_u(s, code.size());
    s += " bytes of code, ";
    append_u(s, m.ninsn);
    s += " instructions, ";
    append_u(s, m.njumpdest);
    s += " jumpdests\n";
    if (m.fmp) {
        s += "the free memory pointer is set first: mem[0x40] = ";
        append_hex(s, code[1]);
        s += '\n';
    }
    if (m.cut_push) {
        const Insn in = m.insn_at(*m.cut_push);
        s += "the code ends in a ";
        s += name_of(in.op);
        s += " at ";
        append_hex(s, in.pc);
        s += ": ";
        append_u(s, in.imm_len);
        s += " of its ";
        append_u(s, in.imm_size);
        s += " bytes\n";
    }
    if (!w.unknown.empty()) {
        append_u(s, w.unknown.size());
        s += " bytes that aren't opcodes:\n";
        for (const Insn& in : w.unknown) {
            s += "  ";
            append_hex(s, in.pc);
            s += ": ";
            append_hex(s, in.op);
            s += '\n';
        }
    }
    // the static jumps, and those to no jumpdest (the EVM's jump fails there)
    u64 nstatic = 0, nbad = 0;
    for (const Idiom& i : m.idioms) {
        if (i.kind == IdiomKind::Selector) continue;
        ++nstatic;
        nbad += !m.is_jumpdest(i.target == kFarTarget ? u64(-1) : i.target);
    }
    append_u(s, nstatic);
    s += " jumps to a number, ";
    append_u(s, nbad);
    s += " of them to no jumpdest\n";
    for (const Idiom& i : m.idioms) {
        if (i.kind == IdiomKind::Selector || m.is_jumpdest(i.target == kFarTarget ? u64(-1) : i.target)) continue;
        s += "  ";
        append_hex(s, i.last_pc);
        s += ": ";
        s += name_of(code[i.last_pc]);
        s += " to ";
        const Insn push = m.insn_at(i.first_pc);  // (whole: a jump follows it)
        append_hex_be(s, std::span<const u8>(push.imm, push.imm_len));
        s += '\n';
    }
    append_u(s, w.jumps - nstatic);
    s += " jumps to a computed place\n";
    u64 nsel = 0;
    for (const Idiom& i : m.idioms) nsel += i.kind == IdiomKind::Selector;
    if (nsel) {
        append_u(s, nsel);
        s += " functions solc's dispatcher compares the selector with:\n";
        for (const Idiom& i : m.idioms) {
            if (i.kind != IdiomKind::Selector) continue;
            s += "  0x";
            for (int k = 28; k >= 0; k -= 4) s += kHex[(i.selector >> k) & 15];
            s += " -> ";
            append_hex(s, i.target);
            s += '\n';
        }
    }
    return s;
}

}  // namespace pan::evm
