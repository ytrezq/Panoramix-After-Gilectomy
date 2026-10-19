// Hex text into bytes (hex.hpp): one machine a function, as every parser
// here. The bytes are what the machines take: the text is never looked at
// another way.
#include "hex.hpp"

// (ragel -G2 makes the cases of its switches fall through)
#pragma GCC diagnostic ignored "-Wimplicit-fallthrough"

namespace pan::hex {

namespace {

// The hex of bytecode: the asm's hex_decode (0x prefix, blanks anywhere,
// a byte's two digits apart or not), the leading blanks python's strip()
// leaves out allowed before the prefix.
%%{
    machine hex_decode;
    alphtype unsigned char;

    action high_digit { high = static_cast<unsigned>(fc - '0'); }
    action high_lower { high = static_cast<unsigned>(fc - 'a' + 10); }
    action high_upper { high = static_cast<unsigned>(fc - 'A' + 10); }
    action low_digit { out.push_back(static_cast<std::uint8_t>(high << 4 | unsigned(fc - '0'))); }
    action low_lower { out.push_back(static_cast<std::uint8_t>(high << 4 | unsigned(fc - 'a' + 10))); }
    action low_upper { out.push_back(static_cast<std::uint8_t>(high << 4 | unsigned(fc - 'A' + 10))); }

    blank = [ \t\r\n];
    high = [0-9] @high_digit | [a-f] @high_lower | [A-F] @high_upper;
    low = [0-9] @low_digit | [a-f] @low_lower | [A-F] @low_upper;

    # (the prefix's 0 runs high_digit as a byte's first digit would: the
    # x that follows makes it the prefix, and the next byte sets it again)
    main := blank* ('0' [xX])? (blank | high blank* low)*;
}%%

%% write data;

// Bytes from outside made printable: the asm's sb_append_clean.
%%{
    machine hex_escape;
    alphtype unsigned char;

    action plain { out.push_back(static_cast<char>(fc)); }
    action escaped {
        out.push_back('\\');
        out.push_back('x');
        out.push_back(digits[fc >> 4]);
        out.push_back(digits[fc & 15]);
    }

    printable = 0x20..0x7e - '\\';
    main := (printable @plain | (any - printable) @escaped)*;
}%%

%% write data;

constexpr char digits[] = "0123456789abcdef";

}  // namespace

std::expected<std::vector<std::uint8_t>, DecodeError> decode(std::string_view text)
{
    std::vector<std::uint8_t> out;
    out.reserve(text.size() / 2);
    unsigned high = 0;
    const auto* const start = reinterpret_cast<const unsigned char*>(text.data());
    const unsigned char* p = start;
    const unsigned char* const pe = start + text.size();
    int cs;
    %% machine hex_decode;
    %% write init;
    %% write exec;
    if (cs == hex_decode_error)
        return std::unexpected(DecodeError{static_cast<std::size_t>(p - start), false});
    if (cs < hex_decode_first_final)
        return std::unexpected(DecodeError{text.size(), true});
    return out;
}

std::string escape(std::string_view bytes, std::size_t max)
{
    bytes = bytes.substr(0, max);
    std::string out;
    out.reserve(bytes.size());
    const auto* p = reinterpret_cast<const unsigned char*>(bytes.data());
    const auto* const pe = p + bytes.size();
    int cs;
    %% machine hex_escape;
    %% write init;
    %% write exec;
    (void)cs;
    return out;
}

}  // namespace pan::hex
