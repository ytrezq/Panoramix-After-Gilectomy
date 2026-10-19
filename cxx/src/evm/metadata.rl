// The CBOR metadata the compilers append to the code: a CBOR map, then its
// length in 2 bytes, big-endian, at the very end. solc's keys: ipfs, bzzr0,
// bzzr1 (the source's hash), solc (its version: 3 bytes, a text for a
// prerelease), experimental (true); vyper 0.3.4 to 0.3.9's: vyper ([major,
// minor, patch]). (vyper 0.3.10 on appends it to the initcode only.)
// A Ragel machine over the map (ir.md §3 #25: not a search for "solc" in the
// last bytes, python's storage.language): the keys spelled out, so that a
// map with another key isn't taken for metadata; the strings' contents
// skipped - their length is in their head, which no regular language counts.
#include "evm/decoder.hpp"

namespace pan {

namespace {

enum class Key : u8 { None, Ipfs, Bzzr0, Bzzr1, Solc, Experimental, Vyper };

%%{
    machine evm_metadata;
    alphtype unsigned char;

    # a string's length: in its head's low 5 bits, or in the 1, 2, 4 bytes after it
    action len_inline { len = *p & 0x1f; }
    action len_1 { len = *p; }
    action len_2 { len = u64(p[-1]) << 8 | p[0]; }
    action len_4 { len = u64(p[-3]) << 24 | u64(p[-2]) << 16 | u64(p[-1]) << 8 | p[0]; }
    # its bytes, skipped (solc's 3-byte version kept)
    action skip {
        if (len > u64(pe - p - 1)) {
            bad = true;
            fbreak;
        }
        if (key == Key::Solc && len == 3) md.version = std::array<u8, 3>{p[1], p[2], p[3]};
        fexec p + 1 + len;
    }
    # an unsigned number: in the head's low 5 bits, or in the 1, 2, 4 bytes after it
    action num_inline { num = *p & 0x1f; }
    action num_1 { num = *p; }
    action num_2 { num = u64(p[-1]) << 8 | p[0]; }
    action num_4 { num = u64(p[-3]) << 24 | u64(p[-2]) << 16 | u64(p[-1]) << 8 | p[0]; }
    # an item of vyper's version
    action version_item {
        if (key == Key::Vyper && nversion < 3 && num < 256) version[nversion] = u8(num);
        ++nversion;
    }

    action k_ipfs { key = Key::Ipfs; md.ipfs = true; }
    action k_bzzr0 { key = Key::Bzzr0; md.bzzr0 = true; }
    action k_bzzr1 { key = Key::Bzzr1; md.bzzr1 = true; }
    action k_solc { key = Key::Solc; solc = true; }
    action k_experimental { key = Key::Experimental; md.experimental = true; }
    action k_vyper { key = Key::Vyper; vyper = true; }
    action pair { ++pairs; }
    action head { want = *p & 0x1f; }

    bstr = (0x40..0x57 @len_inline | 0x58 any @len_1 | 0x59 any{2} @len_2 | 0x5a any{4} @len_4) @skip;
    tstr = (0x60..0x77 @len_inline | 0x78 any @len_1 | 0x79 any{2} @len_2 | 0x7a any{4} @len_4) @skip;
    num = 0x00..0x17 @num_inline | 0x18 any @num_1 | 0x19 any{2} @num_2 | 0x1a any{4} @num_4;
    # false, true, null, undefined
    simple = 0xf4..0xf7;
    value = bstr | tstr | num | simple | 0x83 (num @version_item){3};

    key = 0x64 'ipfs' @k_ipfs
        | 0x65 'bzzr0' @k_bzzr0
        | 0x65 'bzzr1' @k_bzzr1
        | 0x64 'solc' @k_solc
        | 0x6c 'experimental' @k_experimental
        | 0x65 'vyper' @k_vyper;

    # a map of 1 to 23 pairs (their number checked after the machine)
    main := (0xa1..0xb7 @head) . ((key . value) @pair)+;
}%%

%% write data noerror noentry;

}  // namespace

std::optional<Metadata> metadata(std::span<const u8> code)
{
    check_code_size(code);
    const usize n = code.size();
    if (n < 3) return std::nullopt;
    const usize len_cbor = usize(code[n - 2]) << 8 | code[n - 1];
    if (len_cbor == 0 || len_cbor + 2 > n) return std::nullopt;

    Metadata md;
    md.start = u32(n - 2 - len_cbor);
    Key key = Key::None;
    u64 len = 0, num = 0;
    u32 pairs = 0, want = 0, nversion = 0;
    std::array<u8, 3> version{};
    bool bad = false, solc = false, vyper = false;

    const u8* p = code.data() + md.start;
    const u8* const pe = code.data() + n - 2;
    int cs;
    %% write init;
    %% write exec;
    if (bad || p != pe || cs < evm_metadata_first_final || pairs != want) return std::nullopt;
    if (vyper) {
        md.lang = Lang::Vyper;
        md.version = nversion == 3 ? std::optional(version) : std::nullopt;
    } else if (solc || md.ipfs || md.bzzr0 || md.bzzr1 || md.experimental) {
        md.lang = Lang::Solidity;
    }
    return md;
}

}  // namespace pan
