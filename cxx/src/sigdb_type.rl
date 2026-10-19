// The parsers of the ABI types' texts of the signature dump (see sigdb.hpp:
// Type for the codes they make). Two Ragel machines (ragel -G2), one a
// function, sharing their actions (abi_type_common):
//
// abi_type (parse_type): the types as a signature writes them, exactly (no
// spaces, no leading zeros, the sizes the ABI has), the tuples written out -
// (uint256,address)[] - through Ragel's call stack, the named types (IERC20,
// Lib.Data) and the references of a library's signature (uint32[] storage).
// A text that isn't one of these is refused: the caller keeps it as a named
// type of that text. What hashes to its selector as it is goes through here.
//
// abi_type_lenient (parse_type_lenient): what a signature that doesn't hash
// to its selector may have meant - the repairs of sigdb.cpp. The same types,
// and: any case (Address, UINT256), the aliases (uint, int, byte, fixed,
// ufixed; panoramix's "array", a dynamic array of words), the words after a
// type (a parameter's name, "indexed", "payable"), a reference to memory or
// calldata (not in selectors: dropped), "tuple(...)" for a tuple written out,
// spaces around the punctuation; and the named types as slots (Slots): what
// each one is - itself, address, uint8, uint256, bytes32, the components of
// the parameter - is the caller's choice, its hint the words before it
// (contract or interface, enum, struct).
//
// The text "tuple" (and its arrays, its reference), when the parameter has
// components, is the tuple of its components (python's canonical_type): the
// caller's TupleSource writes that tuple.
//
// The array dimensions follow their element in the text; in the code they
// come first (the outer one first): each is inserted where the element's
// code begins.
#include <string>
#include <vector>

#include "sigdb_impl.hpp"

namespace pan::sigdb {

namespace {

constexpr int tuple_depth = 32;  // tuples written in tuples

%%{
machine abi_type_common;
alphtype unsigned char;

action fail { ok = false; fbreak; }

action bn_reset { bn = 0; }
action bn_digit { bn = bn < 100000 ? bn * 10 + (fc - '0') : 100000; }
action bm_save { bm = bn; bn = 0; }
action dn_reset { dn = 0; dover = false; }
action dn_digit {
    unsigned d = fc - '0';
    if (dn > (UINT64_MAX - d) / 10)
        dover = true;
    else
        dn = dn * 10 + d;
}

action uint_end {
    if (bn < 8 || bn > 256 || bn % 8) { ok = false; fbreak; }
    code.push_back(static_cast<char>(code::uint_base + bn / 8 - 1));
}
action int_end {
    if (bn < 8 || bn > 256 || bn % 8) { ok = false; fbreak; }
    code.push_back(static_cast<char>(code::int_base + bn / 8 - 1));
}
action bytesn_end {
    if (bn < 1 || bn > 32) { ok = false; fbreak; }
    code.push_back(static_cast<char>(code::bytes_base + bn - 1));
}
action bytes_end { code.push_back(static_cast<char>(code::bytes)); }
action address_end { code.push_back(static_cast<char>(code::address)); }
action bool_end { code.push_back(static_cast<char>(code::boolean)); }
action string_end { code.push_back(static_cast<char>(code::string)); }
action function_end { code.push_back(static_cast<char>(code::function)); }
action fixed_end {
    if (bm < 8 || bm > 256 || bm % 8 || bn > 80) { ok = false; fbreak; }
    code.push_back(static_cast<char>(code::fixed));
    code.push_back(static_cast<char>(bm / 8 - 1));
    code.push_back(static_cast<char>(bn));
}
action ufixed_end {
    if (bm < 8 || bm > 256 || bm % 8 || bn > 80) { ok = false; fbreak; }
    code.push_back(static_cast<char>(code::ufixed));
    code.push_back(static_cast<char>(bm / 8 - 1));
    code.push_back(static_cast<char>(bn));
}
action mark { mark = p; }
action tuple_keyword {
    // the parameter's components, at the top only (python substitutes
    // them where the whole text begins with "tuple")
    if (tuples.empty() && components && !components_used) {
        components_used = true;
        if (!components->tuple(code)) { ok = false; fbreak; }
    } else {
        code.push_back(static_cast<char>(code::named));
        put_varint(code, pool.intern("tuple"));
    }
}
action field_next {
    counts.back()++;
    code.push_back(0);
    base_at = code.size();
}
action dim_dynamic { code.insert(base_at, 1, static_cast<char>(code::array)); }
action dim_static {
    if (dover) { ok = false; fbreak; }
    std::string head(1, static_cast<char>(code::static_array));
    put_varint(head, dn);
    code.insert(base_at, head);
}
action storage { code.insert(base_at, 1, static_cast<char>(code::storage)); }
action memory { code.insert(base_at, 1, static_cast<char>(code::memory)); }
action calldata { code.insert(base_at, 1, static_cast<char>(code::calldata)); }

digits = '0' | [1-9] [0-9]*;
bnum = digits $bn_digit;
dnum = digits $dn_digit;
ident = [A-Za-z_$] [A-Za-z0-9_$]*;
}%%

// --- exact ---------------------------------------------------------------------------

%%{
machine abi_type;
include abi_type_common;

action named_end {
    code.push_back(static_cast<char>(code::named));
    put_varint(code, pool.intern(std::string_view(reinterpret_cast<const char*>(mark),
                                                  static_cast<std::size_t>(p - mark))));
}
action call_tuple {
    if (top == tuple_depth) { ok = false; fbreak; }
    // the tuple, its count (written at its end), the first field's name
    // (none: a written tuple has no names)
    tuples.push_back(code.size());
    counts.push_back(1);
    code.push_back(static_cast<char>(code::tuple));
    code.push_back(0);
    code.push_back(0);
    base_at = code.size();
    fcall tuple_body;
}
action tuple_end {
    std::size_t at = tuples.back();
    std::uint64_t n = counts.back();
    tuples.pop_back();
    counts.pop_back();
    if (n >= 0x80) {  // (a count of more than a byte: room made for it)
        std::string v;
        put_varint(v, n);
        code.replace(at + 1, 1, v);
    } else {
        code[at + 1] = static_cast<char>(n);
    }
    base_at = at;
    fret;
}
action tuple_end_empty {
    std::size_t at = tuples.back();
    tuples.pop_back();
    counts.pop_back();
    code.resize(at + 2);  // (no field: no name)
    code[at + 1] = 0;
    base_at = at;
    fret;
}

elementary = 'uint' @bn_reset bnum %uint_end
           | 'int' @bn_reset bnum %int_end
           | 'bytes' @bn_reset bnum %bytesn_end
           | 'bytes' %bytes_end
           | 'address' %address_end
           | 'bool' %bool_end
           | 'string' %string_end
           | 'function' %function_end
           | 'fixed' @bn_reset bnum 'x' @bm_save bnum %fixed_end
           | 'ufixed' @bn_reset bnum 'x' @bm_save bnum %ufixed_end;
elementary_text = ( 'uint' | 'int' ) digits | 'bytes' digits? | 'address' | 'bool' | 'string'
                | 'function' | ( 'fixed' | 'ufixed' ) digits 'x' digits;
named = ( ( ident ( '.' ident )* ) - ( elementary_text | 'tuple' ) ) >mark %named_end;

base = elementary | named | 'tuple' %tuple_keyword | '(' @call_tuple;
dim = '[' @dn_reset ( ']' @dim_dynamic | dnum ']' @dim_static );
location = ' ' ( 'storage' @storage | 'memory' @memory | 'calldata' @calldata );
type = base dim* location?;

tuple_body := ( ')' @tuple_end_empty | type ( ',' @field_next type )* ')' @tuple_end );
main := type;
}%%

%% write data;

}  // namespace

bool parse_type(std::string_view text, TupleSource* components, StringPool& pool,
                std::string& code)
{
    const std::size_t start = code.size();
    const unsigned char* p = reinterpret_cast<const unsigned char*>(text.data());
    const unsigned char* pe = p + text.size();
    const unsigned char* eof = pe;
    const unsigned char* mark = p;
    int cs, top = 0, stack[tuple_depth];
    bool ok = true, components_used = false;
    unsigned bn = 0, bm = 0;
    std::uint64_t dn = 0;
    bool dover = false;
    std::size_t base_at = start;
    std::vector<std::size_t> tuples;
    std::vector<std::uint64_t> counts;
    %% write init;
    %% write exec;
    if (!ok || cs < abi_type_first_final || p != pe) {
        code.resize(start);
        return false;
    }
    return true;
}

namespace {

// --- lenient -------------------------------------------------------------------------

%%{
machine abi_type_lenient;
include abi_type_common;

action uint256_end { code.push_back(static_cast<char>(code::uint_base + 31)); }
action int256_end { code.push_back(static_cast<char>(code::int_base + 31)); }
action bytes1_end { code.push_back(static_cast<char>(code::bytes_base)); }
action fixed_default_end {  // (fixed: fixed128x18)
    code.push_back(static_cast<char>(code::fixed));
    code.push_back(15);
    code.push_back(18);
}
action ufixed_default_end {
    code.push_back(static_cast<char>(code::ufixed));
    code.push_back(15);
    code.push_back(18);
}
action array_end {  // (panoramix's "array": its data, words)
    code.push_back(static_cast<char>(code::array));
    code.push_back(static_cast<char>(code::uint_base + 31));
}
action hint_bare { hint = Hint::bare; }
action hint_contract { hint = Hint::contract; }
action hint_enum { hint = Hint::enumeration; }
action hint_struct { hint = Hint::structure; }
action slot_end {
    // a named type: what the caller makes of it
    bool can_components = tuples.empty() && components && !components_used;
    std::size_t me = slots.next;
    Choice choice = slots.take(hint, can_components);
    if (slots.discovering && can_components) {
        // the slots of the components it may be made of, numbered after it
        std::string scratch;
        std::size_t before = slots.next;
        components->tuple(scratch);
        slots.found[me].inner = static_cast<std::uint32_t>(slots.next - before);
    } else if (!slots.discovering && choice != Choice::components && me < slots.found.size()) {
        slots.next += slots.found[me].inner;  // (not made of them: not met)
    }
    switch (choice) {
    case Choice::keep:
        code.push_back(static_cast<char>(code::named));
        put_varint(code, pool.intern(std::string_view(reinterpret_cast<const char*>(mark),
                                                      static_cast<std::size_t>(p - mark))));
        break;
    case Choice::components:
        if (!can_components) { ok = false; fbreak; }
        components_used = true;
        if (!components->tuple(code)) { ok = false; fbreak; }
        break;
    case Choice::address:
        code.push_back(static_cast<char>(code::address));
        break;
    case Choice::uint8:
        code.push_back(static_cast<char>(code::uint_base));
        break;
    case Choice::uint256:
        code.push_back(static_cast<char>(code::uint_base + 31));
        break;
    case Choice::bytes32:
        code.push_back(static_cast<char>(code::bytes_base + 31));
        break;
    }
}
action call_tuple {
    if (top == tuple_depth) { ok = false; fbreak; }
    tuples.push_back(code.size());
    counts.push_back(1);
    code.push_back(static_cast<char>(code::tuple));
    code.push_back(0);
    code.push_back(0);
    base_at = code.size();
    fcall tuple_body;
}
action tuple_end {
    std::size_t at = tuples.back();
    std::uint64_t n = counts.back();
    tuples.pop_back();
    counts.pop_back();
    if (n >= 0x80) {
        std::string v;
        put_varint(v, n);
        code.replace(at + 1, 1, v);
    } else {
        code[at + 1] = static_cast<char>(n);
    }
    base_at = at;
    fret;
}
action tuple_end_empty {
    std::size_t at = tuples.back();
    tuples.pop_back();
    counts.pop_back();
    code.resize(at + 2);
    code[at + 1] = 0;
    base_at = at;
    fret;
}

sp = ' '+;
ows = ' '*;
elementary = 'uint'i @bn_reset bnum %uint_end | 'uint'i %uint256_end
           | 'int'i @bn_reset bnum %int_end | 'int'i %int256_end
           | 'bytes'i @bn_reset bnum %bytesn_end | 'bytes'i %bytes_end | 'byte'i %bytes1_end
           | 'address'i %address_end
           | 'bool'i %bool_end
           | 'string'i %string_end
           | 'function'i %function_end
           | 'fixed'i @bn_reset bnum 'x'i @bm_save bnum %fixed_end | 'fixed'i %fixed_default_end
           | 'ufixed'i @bn_reset bnum 'x'i @bm_save bnum %ufixed_end | 'ufixed'i %ufixed_default_end
           | 'array' %array_end;
keywords = ( 'uint'i | 'int'i | 'bytes'i ) digits? | 'byte'i | 'address'i | 'bool'i | 'string'i
         | 'function'i | ( 'fixed'i | 'ufixed'i ) ( digits 'x'i digits )? | 'array'
         | 'tuple'i | 'contract'i | 'interface'i | 'enum'i | 'struct'i;
dotted = ident ( '.' ident )*;
# a named type, alone or after what says what it is
bare = ( dotted - keywords ) >mark >hint_bare %slot_end;
prefixed = ( ( 'contract'i | 'interface'i ) sp @hint_contract | 'enum'i sp @hint_enum
           | 'struct'i sp @hint_struct ) ( dotted >mark %slot_end );
base = elementary | bare | prefixed | 'tuple'i %tuple_keyword | 'tuple'i? '(' @call_tuple;
dim = '[' @dn_reset ows ( ']' @dim_dynamic | dnum ows ']' @dim_static );
locations = 'storage'i | 'memory'i | 'calldata'i;
# memory and calldata aren't in selectors: dropped
location = sp ( 'storage'i %storage | 'memory'i | 'calldata'i );
# words after the type: a name, indexed, payable...
words = ( sp ( ident - locations ) )*;
type = ows base ( ows dim )* location? words ows;

tuple_body := ( ows ')' @tuple_end_empty | type ( ',' @field_next type )* ')' @tuple_end );
main := type;
}%%

%% write data;

}  // namespace

bool parse_type_lenient(std::string_view text, TupleSource* components, StringPool& pool,
                        std::string& code, Slots& slots)
{
    const std::size_t start = code.size();
    const unsigned char* p = reinterpret_cast<const unsigned char*>(text.data());
    const unsigned char* pe = p + text.size();
    const unsigned char* eof = pe;
    const unsigned char* mark = p;
    int cs, top = 0, stack[tuple_depth];
    bool ok = true, components_used = false;
    unsigned bn = 0, bm = 0;
    std::uint64_t dn = 0;
    bool dover = false;
    std::size_t base_at = start;
    std::vector<std::size_t> tuples;
    std::vector<std::uint64_t> counts;
    Hint hint = Hint::bare;
    const std::size_t next = slots.next, found = slots.found.size();
    %% write init;
    %% write exec;
    if (!ok || cs < abi_type_lenient_first_final || p != pe) {
        code.resize(start);
        slots.next = next;
        slots.found.resize(found);
        return false;
    }
    return true;
}

}  // namespace pan::sigdb
