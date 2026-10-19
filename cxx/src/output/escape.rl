// Text from outside, made printable (Ragel, AGENTS.md rule 2):
//  - the names and types of the signature database as the text prints them
//    (the asm's db_intern / utf8_char): its valid UTF-8 as it is, every
//    character that isn't text - C0 and DEL, C1 (U+0080..U+009F), U+061C,
//    U+200E, U+200F, U+2028..U+202E (the separators, the embeddings and
//    overrides), U+2066..U+2069 (the isolates) - and each byte of no valid
//    UTF-8 written \xNN: no escape sequence of the terminal, no forged line,
//    no reordered one;
//  - python's pretty_text: bytes of the contract that are text (printable
//    ASCII, \n \r \t; a letter or a digit among them) as a string literal.
#include <string>

#include "output/print.hpp"

namespace pan::output::detail {

namespace {

constexpr char kHex[] = "0123456789abcdef";

void escape_bytes(std::string& out, const unsigned char* b, const unsigned char* e)
{
    for (; b < e; ++b) {
        out += "\\x";
        out += kHex[*b >> 4];
        out += kHex[*b & 15];
    }
}

%%{
    machine db_text;
    alphtype unsigned char;

    cont = 0x80..0xbf;
    utf8_2 = 0xc2..0xdf cont;
    utf8_3 = 0xe0 0xa0..0xbf cont | 0xe1..0xec cont cont | 0xed 0x80..0x9f cont | 0xee..0xef cont cont;
    utf8_4 = 0xf0 0x90..0xbf cont cont | 0xf1..0xf3 cont cont cont | 0xf4 0x80..0x8f cont cont;
    # the characters that aren't text: C1, the direction marks and overrides, the separators
    not_text = 0xc2 0x80..0x9f
             | 0xd8 0x9c
             | 0xe2 0x80 (0x8e | 0x8f | 0xa8..0xae)
             | 0xe2 0x81 0xa6..0xa9;
    text = 0x20..0x7e | ((utf8_2 | utf8_3 | utf8_4) - not_text);

    main := |*
        text => { out.append(reinterpret_cast<const char*>(ts), te - ts); };
        not_text => { escape_bytes(out, ts, te); };
        any => { escape_bytes(out, ts, te); };
    *|;
}%%

%% write data;

%%{
    machine text_bytes;
    alphtype unsigned char;

    action alnum { alnum = true; }
    printable = 0x20..0x7e | '\n' | '\r' | '\t';
    main := ( (printable - [0-9A-Za-z]) | [0-9A-Za-z] @alnum )*;
}%%

%% write data;

}  // namespace

void append_db_text(std::string& out, std::string_view raw)
{
    const auto* p = reinterpret_cast<const unsigned char*>(raw.data());
    const auto* const pe = p + raw.size();
    const auto* const eof = pe;
    const unsigned char* ts = nullptr;
    const unsigned char* te = nullptr;
    int cs, act;
    (void)act;
    %% machine db_text;
    %% write init;
    %% write exec;
    (void)db_text_first_final;
    (void)db_text_error;
    (void)db_text_en_main;
}

std::string db_text(std::string_view raw)
{
    std::string out;
    out.reserve(raw.size());
    append_db_text(out, raw);
    return out;
}

std::optional<std::string> pretty_text(std::span<const u8> b, bool short_ok)
{
    if (b.empty())
        return std::nullopt;
    bool alnum = false;
    const unsigned char* p = b.data();
    const unsigned char* const pe = p + b.size();
    int cs;
    %% machine text_bytes;
    %% write init;
    %% write exec;
    (void)text_bytes_en_main;
    if (cs < text_bytes_first_final || cs == text_bytes_error)
        return std::nullopt;
    if (!alnum && !(short_ok && b.size() <= 2))
        return std::nullopt;
    std::string out;
    out.reserve(b.size() + 2);
    out += '\'';
    for (const u8 c : b) {
        switch (c) {
            case '\\': out += "\\\\"; break;
            case '\'': out += "\\'"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default: out += char(c);
        }
    }
    out += '\'';
    return out;
}

}  // namespace pan::output::detail
