// The decoder (src/evm/): the grammar against core's tables, the machines
// (analysis, listing, exec_ref, metadata) against a reference written the
// plain way (pc += 1 + kImm[op], the idioms matched on the instruction list),
// on hand-made code, random bytes and the corpus; the text of disasm/decode.
#include <doctest/doctest.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <limits>
#include <random>
#include <set>
#include <string>
#include <vector>

#include "evm/decoder.hpp"
#include "hex.hpp"
#include "io.hpp"

using namespace pan;

namespace {

std::vector<u8> bytes_of(std::string_view hex_text)
{
    auto b = hex::decode(hex_text);
    REQUIRE(b.has_value());
    return *b;
}

// --- the reference: the instructions by the letter of evm.def ---------------

struct RefInsn {
    u32 pc;
    u8 op, imm_len, imm_size;
    friend bool operator==(const RefInsn&, const RefInsn&) = default;
};

std::vector<RefInsn> ref_decode(std::span<const u8> code, usize from = 0)
{
    std::vector<RefInsn> out;
    for (usize pc = from; pc < code.size();) {
        const u8 op = code[pc];
        const usize rest = code.size() - pc - 1;
        const u8 size = kImm[op];
        out.push_back({u32(pc), op, u8(rest < size ? rest : size), size});
        pc += 1 + size;
    }
    return out;
}

RefInsn ref_of(const Insn& in) { return {in.pc, in.op, in.imm_len, in.imm_size}; }

// a push's value when it fits 32 bits, else kFarTarget
u32 ref_value(std::span<const u8> code, const RefInsn& in)
{
    u64 v = 0;
    for (u32 i = 0; i < in.imm_size; ++i) {
        if (v > 0xffffffffu) return kFarTarget;
        v = v << 8 | (i < in.imm_len ? code[in.pc + 1 + i] : 0);
    }
    return v < kFarTarget ? u32(v) : kFarTarget;
}

struct RefMap {
    std::vector<u32> starts, jumpdests, static_dest, bad;
    std::vector<Idiom> idioms;
    std::optional<u32> cut;
    bool fmp = false;
};

RefMap ref_map(std::span<const u8> code)
{
    RefMap r;
    const auto ins = ref_decode(code);
    std::set<u32> dest;
    const auto is_push = [](u8 op) { return kClass[op] == InsnClass::Push; };
    for (usize k = 0; k < ins.size(); ++k) {
        const RefInsn& in = ins[k];
        r.starts.push_back(in.pc);
        if (in.op == 0x5b) r.jumpdests.push_back(in.pc);
        if (in.imm_len < in.imm_size) r.cut = in.pc;
        if ((in.op == 0x56 || in.op == 0x57) && k >= 1 && is_push(ins[k - 1].op)) {
            const u32 t = ref_value(code, ins[k - 1]);
            if (t < code.size()) dest.insert(t);
            r.idioms.push_back({in.op == 0x56 ? IdiomKind::StaticJump : IdiomKind::StaticJumpI, ins[k - 1].pc, in.pc, t, 0});
        }
        if (in.op == 0x57 && k >= 4 && ins[k - 4].op == 0x80 && ins[k - 3].op == 0x63 && ins[k - 2].op == 0x14 &&
            ins[k - 1].op >= 0x60 && ins[k - 1].op <= 0x63)
            r.idioms.push_back(
                {IdiomKind::Selector, ins[k - 4].pc, in.pc, ref_value(code, ins[k - 1]), ref_value(code, ins[k - 3])});
    }
    r.fmp = ins.size() >= 3 && ins[0].op == 0x60 && ins[0].imm_len == 1 && code[1] >= 0x60 && ins[1].op == 0x60 &&
            ins[1].imm_len == 1 && code[3] == 0x40 && ins[2].op == 0x52;
    r.static_dest.assign(dest.begin(), dest.end());
    const std::set<u32> jd(r.jumpdests.begin(), r.jumpdests.end());
    for (const u32 t : dest)
        if (!jd.contains(t)) r.bad.push_back(t);
    return r;
}

std::vector<u32> bits_of(const Bitset& b)
{
    std::vector<u32> out;
    for (usize i = b.next(0); i < b.size(); i = b.next(i + 1)) out.push_back(u32(i));
    return out;
}

// the CodeMap against the reference; false (and the failed CHECKs) if not
bool same_as_reference(std::span<const u8> code)
{
    const CodeMap m = analyse(code);
    const RefMap r = ref_map(code);
    bool ok = true;
    const auto check = [&](bool c, const char* what) {
        if (!c) {
            ok = false;
            FAIL_CHECK(what << " differs on " << code.size() << " bytes: "
                            << hex::escape(std::string_view(reinterpret_cast<const char*>(code.data()),
                                                            std::min<usize>(code.size(), 64))));
        }
    };
    check(m.code.data() == code.data() && m.size() == code.size(), "the code");
    check(bits_of(m.insn_start) == r.starts, "insn_start");
    check(m.ninsn == r.starts.size(), "ninsn");
    check(bits_of(m.jumpdest) == r.jumpdests, "jumpdest");
    check(m.njumpdest == r.jumpdests.size(), "njumpdest");
    check(bits_of(m.static_dest) == r.static_dest, "static_dest");
    check(m.bad_static_jumps == r.bad, "bad_static_jumps");
    check(m.idioms == r.idioms, "idioms");
    check(m.cut_push == r.cut, "cut_push");
    check(m.fmp == r.fmp, "fmp");
    return ok;
}

// --- random code, dense with what the decoder must get right -----------------

std::vector<u8> random_code(std::mt19937_64& rnd)
{
    static const std::vector<std::vector<u8>> pieces = {
        {0x80}, {0x63, 0x12, 0x34, 0x56, 0x78}, {0x14}, {0x61, 0x00, 0x05}, {0x60, 0x07}, {0x56}, {0x57},
        {0x5f}, {0x60, 0x80}, {0x60, 0x40}, {0x52}, {0x5b}, {0x60, 0x5b}, {0x00}, {0xfe}, {0x0c}, {0x7f},
        {0x62}, {0x01}, {0x63, 0x00, 0x00, 0x00, 0x03}, {0x60, 0x02}};
    std::vector<u8> code;
    if (rnd() % 3 == 0) {
        const usize n = rnd() % 300;
        for (usize i = 0; i < n; ++i) code.push_back(u8(rnd()));
    } else {
        const usize n = rnd() % 60;
        for (usize i = 0; i < n; ++i) {
            const auto& piece = pieces[rnd() % pieces.size()];
            code.insert(code.end(), piece.begin(), piece.end());
        }
    }
    return code;
}

// the corpus' contracts (PANCXX_CORPUS: a list of .hex paths, else the
// Makefile's default CORPUS); empty when there is none
std::vector<std::vector<u8>> corpus(std::vector<std::string>* names = nullptr)
{
    const char* env = std::getenv("PANCXX_CORPUS");
    const std::string list = env ? env
                                 : "/tmp/claude-0/-home-claude/0fe601fa-3d3d-56af-9a22-c5068d00d0e0/scratchpad/prof/"
                                   "all_hex.txt";
    std::vector<std::vector<u8>> out;
    const auto text = io::read_regular_file(list, io::max_input);
    if (!text) return out;
    usize i = 0;
    while (i < text->size()) {
        usize j = text->find('\n', i);
        if (j == std::string::npos) j = text->size();
        const std::string path = text->substr(i, j - i);
        i = j + 1;
        if (path.empty()) continue;
        const auto hex_text = io::read_regular_file(path, io::max_input);
        if (!hex_text) continue;
        auto code = hex::decode(*hex_text);
        if (!code) continue;
        out.push_back(std::move(*code));
        if (names) names->push_back(path);
    }
    return out;
}

// what a callback machine hands over
struct Seen {
    std::vector<RefInsn> insns;
    std::vector<const u8*> imms;
};
void record(const Insn& in, void* data)
{
    auto& s = *static_cast<Seen*>(data);
    s.insns.push_back(ref_of(in));
    s.imms.push_back(in.imm);
}

// the reference block walk (what exec_block_ref must do)
BlockEnd ref_block(std::span<const u8> code, u32 start, std::vector<RefInsn>& out)
{
    for (usize pc = start; pc < code.size(); pc += 1 + kImm[code[pc]]) {
        const usize rest = code.size() - pc - 1;
        const RefInsn in{u32(pc), code[pc], u8(rest < kImm[code[pc]] ? rest : kImm[code[pc]]), kImm[code[pc]]};
        switch (kClass[in.op]) {
        case InsnClass::JumpDest:
            if (in.pc != start) return {BlockEndKind::Split, in.op, in.pc, in.pc};
            break;
        case InsnClass::Jump: out.push_back(in); return {BlockEndKind::Jump, in.op, in.pc, in.pc + 1};
        case InsnClass::JumpI: out.push_back(in); return {BlockEndKind::JumpI, in.op, in.pc, in.pc + 1};
        case InsnClass::Halt: out.push_back(in); return {BlockEndKind::Halt, in.op, in.pc, in.pc + 1};
        case InsnClass::Unknown: out.push_back(in); return {BlockEndKind::Unknown, in.op, in.pc, in.pc + 1};
        default: break;
        }
        out.push_back(in);
    }
    return {BlockEndKind::FellOff, 0, u32(code.size()), u32(code.size())};
}

bool blocks_same_as_reference(std::span<const u8> code)
{
    std::vector<u32> starts;
    for (const RefInsn& in : ref_decode(code)) starts.push_back(in.pc);
    starts.push_back(u32(code.size()));
    for (const u32 s : starts) {
        Seen seen;
        std::vector<RefInsn> want;
        const BlockEnd e = exec_block_ref(code, s, record, &seen);
        const BlockEnd w = ref_block(code, s, want);
        if (e != w || seen.insns != want) {
            FAIL_CHECK("exec_block_ref from " << s << " differs");
            return false;
        }
        for (usize k = 0; k < seen.insns.size(); ++k)
            if (seen.imms[k] != code.data() + seen.insns[k].pc + 1) {
                FAIL_CHECK("an Insn's imm pointer at " << seen.insns[k].pc);
                return false;
            }
    }
    return true;
}

// --- metadata tails ------------------------------------------------------------

std::vector<u8> with_tail(std::vector<u8> code, std::string_view cbor_hex)
{
    const auto cbor = bytes_of(cbor_hex);
    code.insert(code.end(), cbor.begin(), cbor.end());
    code.push_back(u8(cbor.size() >> 8));
    code.push_back(u8(cbor.size()));
    return code;
}

std::string hex_of(std::string_view text)
{
    std::string out;
    for (const char c : text) {
        constexpr char d[] = "0123456789abcdef";
        out += d[u8(c) >> 4];
        out += d[u8(c) & 15];
    }
    return out;
}

}  // namespace

TEST_CASE("evm: the grammar's classes are core's kClass, its lengths kImm's")
{
    const auto g = grammar_classes();
    for (u32 op = 0; op < 256; ++op) {
        CAPTURE(op);
        CHECK(g[op].actions == 1);
        CHECK(g[op].cls == kClass[op]);
        CHECK(g[op].length == 1 + kImm[op]);
        CHECK(g[op].imm_bytes == kImm[op]);
        // an unknown byte is no opcode of evm.def, and the other way round
        CHECK((kClass[op] == InsnClass::Unknown) == !info(Op(op)).defined);
    }
}

TEST_CASE("evm: Bitset")
{
    Bitset b(130);
    CHECK(b.size() == 130);
    CHECK(b.count() == 0);
    CHECK(b.next(0) == 130);
    CHECK(b.prev(130) == 130);
    for (const usize i : {0u, 5u, 63u, 64u, 127u, 129u}) b.set(i);
    CHECK(b.count() == 6);
    CHECK(b.test(63));
    CHECK(!b.test(62));
    CHECK(!b.test(130));
    CHECK(!b.test(u64(-1)));
    CHECK(b.next(0) == 0);
    CHECK(b.next(1) == 5);
    CHECK(b.next(6) == 63);
    CHECK(b.next(65) == 127);
    CHECK(b.next(128) == 129);
    CHECK(b.next(130) == 130);
    CHECK(b.prev(0) == 130);
    CHECK(b.prev(1) == 0);
    CHECK(b.prev(64) == 63);
    CHECK(b.prev(65) == 64);
    CHECK(b.prev(127) == 64);
    CHECK(b.prev(1000) == 129);
    CHECK(Bitset(0).next(0) == 0);
    CHECK(Bitset(0).prev(0) == 0);
    CHECK(!Bitset(0).test(0));
}

TEST_CASE("evm: push values, cut pushes")
{
    const auto code = bytes_of("62abcd");  // a push3 the end cuts: 0xabcd00
    const Insn in{0, 0x62, 2, 3, 0, code.data() + 1};
    CHECK(in.cut());
    CHECK(in.next_pc() == 4);
    CHECK(push_u64(in) == 0xabcd00);
    CHECK(push_word(in) == Word256::of(0xabcd00));
    const auto full = bytes_of("7f" + std::string(64, 'f'));
    const Insn p32{0, 0x7f, 32, 32, 0, full.data() + 1};
    CHECK(!push_u64(p32));
    CHECK(push_word(p32) == Word256{{~u64{0}, ~u64{0}, ~u64{0}, ~u64{0}}});
    const Insn p0{0, 0x5f, 0, 0, 0, full.data() + 1};
    CHECK(push_u64(p0) == 0);
    CHECK(push_word(p0).is_zero());
    const CodeMap m = analyse(code);
    CHECK(m.cut_push == 0u);
    const Insn at = m.insn_at(0);
    CHECK(at.imm_len == 2);
    CHECK(at.imm_size == 3);
}

TEST_CASE("evm: the analysis on hand-made code")
{
    SUBCASE("empty") {
        const CodeMap m = analyse({});
        CHECK(m.ninsn == 0);
        CHECK(m.size() == 0);
        CHECK(!m.cut_push);
        CHECK(!m.fmp);
        CHECK(m.idioms.empty());
        CHECK(m.metadata_start == 0);
    }
    SUBCASE("a 0x5b inside a push is no jumpdest") {
        const auto code = bytes_of("605b5b615b5b5b");
        const CodeMap m = analyse(code);
        CHECK(bits_of(m.jumpdest) == std::vector<u32>{2, 6});
        CHECK(bits_of(m.insn_start) == std::vector<u32>{0, 2, 3, 6});
        CHECK(m.ninsn == 4);
    }
    SUBCASE("static jumps, to a jumpdest or not, far") {
        // 0: push1 6; 2: jump; 3: push1 5; 5: jumpi; 6: jumpdest; 7: push5 2^32; 13: jump
        const auto code = bytes_of("6006566005575b64010000000056");
        const CodeMap m = analyse(code);
        REQUIRE(m.idioms.size() == 3);
        CHECK(m.idioms[0] == Idiom{IdiomKind::StaticJump, 0, 2, 6, 0});
        CHECK(m.idioms[1] == Idiom{IdiomKind::StaticJumpI, 3, 5, 5, 0});
        CHECK(m.idioms[2] == Idiom{IdiomKind::StaticJump, 7, 13, kFarTarget, 0});
        CHECK(bits_of(m.static_dest) == std::vector<u32>{5, 6});
        CHECK(m.bad_static_jumps == std::vector<u32>{5});
    }
    SUBCASE("solc's dispatcher: static_jumpi, then the selector, on the jumpi") {
        const auto code = bytes_of("8063a9059cbb1461004257005b");
        const CodeMap m = analyse(code);
        REQUIRE(m.idioms.size() == 2);
        CHECK(m.idioms[0] == Idiom{IdiomKind::StaticJumpI, 7, 10, 0x42, 0});
        CHECK(m.idioms[1] == Idiom{IdiomKind::Selector, 0, 10, 0x42, 0xa9059cbb});
    }
    SUBCASE("the free memory pointer, set first only") {
        CHECK(analyse(bytes_of("6080604052")).fmp);
        CHECK(analyse(bytes_of("6060604052")).fmp);
        CHECK(!analyse(bytes_of("605f604052")).fmp);
        CHECK(!analyse(bytes_of("6080604152")).fmp);
        CHECK(!analyse(bytes_of("5b6080604052")).fmp);
        CHECK(!analyse(bytes_of("60806040")).fmp);
    }
    SUBCASE("a push the end cuts") {
        const CodeMap m = analyse(bytes_of("6001617f"));
        CHECK(m.cut_push == 2u);
        CHECK(m.ninsn == 2);
        CHECK(analyse(bytes_of("600161")).cut_push == 2u);
        CHECK(analyse(bytes_of("60016101")).cut_push == 2u);
        CHECK(!analyse(bytes_of("6001610101")).cut_push);
        CHECK(!analyse(bytes_of("5f")).cut_push);
    }
}

TEST_CASE("evm: the machines on random code against the reference")
{
    std::mt19937_64 rnd(20261019);
    usize bad = 0;
    for (int i = 0; i < 3000 && bad < 5; ++i) {
        const auto code = random_code(rnd);
        bad += !same_as_reference(code);
        Seen seen;
        for_each_insn(code, record, &seen);
        if (seen.insns != ref_decode(code)) {
            FAIL_CHECK("for_each_insn differs");
            ++bad;
        }
        bad += !blocks_same_as_reference(code);
    }
    CHECK(bad == 0);
}

TEST_CASE("evm: exec_block_ref's ends")
{
    // 0: jumpdest; 1: push1 0; 3: jumpdest (split); 4: jumpi; 5: unknown 0x0c; 6: push2 cut
    const auto code = bytes_of("5b60005b570c61ff");
    Seen s;
    CHECK(exec_block_ref(code, 0, record, &s) == BlockEnd{BlockEndKind::Split, 0x5b, 3, 3});
    CHECK(s.insns.size() == 2);  // the first jumpdest, the push
    s = {};
    CHECK(exec_block_ref(code, 3, record, &s) == BlockEnd{BlockEndKind::JumpI, 0x57, 4, 5});
    CHECK(s.insns.size() == 2);
    s = {};
    CHECK(exec_block_ref(code, 5, record, &s) == BlockEnd{BlockEndKind::Unknown, 0x0c, 5, 6});
    s = {};
    CHECK(exec_block_ref(code, 6, record, &s) == BlockEnd{BlockEndKind::FellOff, 0, 8, 8});
    REQUIRE(s.insns.size() == 1);
    CHECK(s.insns[0] == RefInsn{6, 0x61, 1, 2});
    s = {};
    CHECK(exec_block_ref(code, 8, record, &s) == BlockEnd{BlockEndKind::FellOff, 0, 8, 8});
    CHECK(s.insns.empty());
    const auto halts = bytes_of("600056fd");
    CHECK(exec_block_ref(halts, 0, record, &s).kind == BlockEndKind::Jump);
    CHECK(exec_block_ref(halts, 3, record, &s) == BlockEnd{BlockEndKind::Halt, 0xfd, 3, 4});
}

TEST_CASE("evm: metadata tails")
{
    const std::vector<u8> body = bytes_of("6080604052600080fd");
    SUBCASE("solc 0.8: ipfs, solc") {
        const auto code = with_tail(body, "a2" "64" + hex_of("ipfs") + "5822" + std::string(68, '1') + "64" +
                                              hex_of("solc") + "43000814");
        const auto md = metadata(code);
        REQUIRE(md);
        CHECK(md->lang == Lang::Solidity);
        CHECK(md->start == body.size());
        CHECK(md->ipfs);
        CHECK(md->version == std::array<u8, 3>{0, 8, 20});
        CHECK(analyse(code).metadata_start == body.size());
    }
    SUBCASE("solc 0.5: bzzr1, solc, experimental") {
        const auto code = with_tail(body, "a3" "65" + hex_of("bzzr1") + "5820" + std::string(64, '2') + "6c" +
                                              hex_of("experimental") + "f5" "64" + hex_of("solc") + "43000510");
        const auto md = metadata(code);
        REQUIRE(md);
        CHECK(md->lang == Lang::Solidity);
        CHECK(md->bzzr1);
        CHECK(md->experimental);
        CHECK(md->version == std::array<u8, 3>{0, 5, 16});
    }
    SUBCASE("solc 0.4: bzzr0 alone") {
        const auto md = metadata(with_tail(body, "a1" "65" + hex_of("bzzr0") + "5820" + std::string(64, '3')));
        REQUIRE(md);
        CHECK(md->lang == Lang::Solidity);
        CHECK(md->bzzr0);
        CHECK(!md->version);
    }
    SUBCASE("solc's prerelease version: a text") {
        const std::string v = "0.8.26-nightly.2024.5.1+commit.abc12345";
        const std::string len_hex = hex_of(std::string(1, char(v.size())));
        const auto md = metadata(with_tail(body, "a1" "64" + hex_of("solc") + "78" + len_hex + hex_of(v)));
        REQUIRE(md);
        CHECK(md->lang == Lang::Solidity);
        CHECK(!md->version);
    }
    SUBCASE("vyper 0.3.7") {
        const auto md = metadata(with_tail(body, "a1" "65" + hex_of("vyper") + "83000307"));
        REQUIRE(md);
        CHECK(md->lang == Lang::Vyper);
        CHECK(md->version == std::array<u8, 3>{0, 3, 7});
    }
    SUBCASE("not metadata") {
        CHECK(!metadata(body));
        CHECK(!metadata({}));
        CHECK(!metadata(bytes_of("0001")));
        // an unknown key, a wrong pair count, a string past the end, a bad length
        CHECK(!metadata(with_tail(body, "a1" "64" + hex_of("xxxx") + "01")));
        CHECK(!metadata(with_tail(body, "a2" "64" + hex_of("solc") + "43000814")));
        CHECK(!metadata(with_tail(body, "a1" "64" + hex_of("solc") + "5810" "0000")));
        CHECK(!metadata(with_tail(body, "a1" "64" + hex_of("solc") + "43000814" "00")));
        auto cut = with_tail(body, "a1" "64" + hex_of("solc") + "43000814");
        cut[cut.size() - 1] += 1;
        CHECK(!metadata(cut));
        CHECK(analyse(body).metadata_start == body.size());
    }
}

TEST_CASE("evm: metadata on mutated and random tails")
{
    const std::vector<u8> body = bytes_of("6080604052600080fd");
    const std::vector<std::vector<u8>> valid = {
        with_tail(body, "a2" "64" + hex_of("ipfs") + "5822" + std::string(68, '1') + "64" + hex_of("solc") + "43000814"),
        with_tail(body, "a3" "65" + hex_of("bzzr1") + "5820" + std::string(64, '2') + "6c" + hex_of("experimental") +
                            "f5" "64" + hex_of("solc") + "43000510"),
        with_tail(body, "a1" "65" + hex_of("vyper") + "83000307"),
        with_tail(body, "a1" "64" + hex_of("solc") + "7818" + hex_of("0.4.26-nightly.2018.1.1+")),
    };
    std::mt19937_64 rnd(42);
    usize accepted = 0;
    for (int i = 0; i < 20000; ++i) {
        std::vector<u8> code = valid[rnd() % valid.size()];
        const usize nmut = 1 + rnd() % 3;
        for (usize k = 0; k < nmut; ++k) {
            const usize at = body.size() + rnd() % (code.size() - body.size());
            code[at] = rnd() % 4 == 0 ? u8(rnd()) : u8(code[at] ^ (1u << (rnd() % 8)));
        }
        if (rnd() % 8 == 0) code.resize(rnd() % (code.size() + 1));
        if (const auto md = metadata(code)) {
            ++accepted;
            CHECK(md->start + 2 < code.size() + 1);
            CHECK(md->lang != Lang::Unknown);
        }
    }
    for (int i = 0; i < 5000; ++i) {
        std::vector<u8> code(rnd() % 80);
        for (u8& b : code) b = u8(rnd());
        if (code.size() >= 2 && rnd() % 2) {
            const usize len = rnd() % code.size();
            code[code.size() - 2] = u8(len >> 8);
            code[code.size() - 1] = u8(len);
        }
        if (const auto md = metadata(code)) CHECK(md->start + 2 < code.size() + 1);
    }
    MESSAGE(accepted << " of 20000 mutated tails still metadata");
}

TEST_CASE("evm: disassembly and the decode report")
{
    // push1 0x80, push1 0x40, mstore, dup1, swap1, 0x0c, push0, push2 cut
    const auto code = bytes_of("60806040528090" "0c" "5f" "61ab");
    CHECK(evm::disassemble(code) ==
          "0x0, push1, 0x80\n0x2, push1, 0x40\n0x4, mstore, \n0x5, dup1, \n0x6, swap1, \n"
          "0x7, UNKNOWN, 0xc\n0x8, push0, 0x0\n0x9, push2, 0xab00\n");
    std::string joined;
    for (const auto& line : evm::disassembly_lines(code)) joined += line + "\n";
    CHECK(joined == evm::disassemble(code));
    CHECK(evm::disassemble({}).empty());
    CHECK(evm::decode_report(code) ==
          "11 bytes of code, 8 instructions, 0 jumpdests\n"
          "the free memory pointer is set first: mem[0x40] = 0x80\n"
          "the code ends in a push2 at 0x9: 1 of its 2 bytes\n"
          "1 bytes that aren't opcodes:\n"
          "  0x7: 0xc\n"
          "0 jumps to a number, 0 of them to no jumpdest\n"
          "0 jumps to a computed place\n");
    const auto jumps = bytes_of("8063000000ff14600c57600d565b5b56");
    CHECK(evm::decode_report(jumps) ==
          "16 bytes of code, 10 instructions, 2 jumpdests\n"
          "2 jumps to a number, 1 of them to no jumpdest\n"
          "  0x9: jumpi to 0xc\n"
          "1 jumps to a computed place\n"
          "1 functions solc's dispatcher compares the selector with:\n"
          "  0x000000ff -> 0xc\n");
}

TEST_CASE("evm: the corpus - the analysis against the reference, the metadata, the speed")
{
    std::vector<std::string> names;
    const auto all = corpus(&names);
    if (all.empty()) {
        MESSAGE("no corpus (PANCXX_CORPUS): skipped");
        return;
    }
    usize bad = 0, solidity = 0, vyper = 0, bytes = 0, insns = 0;
    for (usize i = 0; i < all.size() && bad < 5; ++i) {
        CAPTURE(names[i]);
        bad += !same_as_reference(all[i]);
        Seen seen;
        for_each_insn(all[i], record, &seen);
        if (seen.insns != ref_decode(all[i])) {
            FAIL_CHECK("for_each_insn differs");
            ++bad;
        }
        if (const auto md = metadata(all[i])) {
            solidity += md->lang == Lang::Solidity;
            vyper += md->lang == Lang::Vyper;
        }
        bytes += all[i].size();
        insns += seen.insns.size();
    }
    CHECK(bad == 0);
    MESSAGE(all.size() << " contracts, " << bytes << " bytes, " << insns << " instructions: " << solidity
                        << " with solc's metadata, " << vyper << " with vyper's");
    // the blocks from every jumpdest, on a sample
    for (usize i = 0; i < all.size(); i += 37) CHECK(blocks_same_as_reference(all[i]));

    // the speed of the analysis on Seaport 1.5 (the brief: < 10 ns/byte; the
    // prototype's 2.9-5.4), else on the largest contract - a message only:
    // the machine is shared, and the debug build is slow
    usize which = usize(std::max_element(all.begin(), all.end(), [](auto& a, auto& b) { return a.size() < b.size(); }) -
                        all.begin());
    for (usize i = 0; i < names.size(); ++i)
        if (names[i].ends_with("/Seaport15.hex")) which = i;
    const auto& code = all[which];
    usize sink = 0;
    i64 best = std::numeric_limits<i64>::max();
    for (int round = 0; round < 5; ++round) {
        constexpr int reps = 40;
        const auto t0 = std::chrono::steady_clock::now();
        for (int r = 0; r < reps; ++r) sink += analyse(code).ninsn;
        const auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - t0).count();
        best = std::min<i64>(best, ns / reps);
    }
    MESSAGE("analysis of " << names[which] << " (" << code.size() << " bytes): " << best * 100 / i64(code.size())
                           << " ns/byte x100, best of 5 (" << sink << ")");
}
