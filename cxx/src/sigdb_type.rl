// The parser of the ABI types' texts of the signature dump (see sigdb.hpp:
// Type for the codes it makes). One Ragel machine (ragel -G2): the types as a
// signature writes them, exactly (no spaces, no leading zeros, the sizes the
// ABI has), the tuples written out - (uint256,address)[] - through Ragel's
// call stack, the named types (IERC20, Lib.Data) and the references of a
// library's signature (uint32[] storage). A text that isn't one of these is
// refused: the caller keeps it as a named type of that text.
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
machine abi_type;
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
action named_end {
    code.push_back(static_cast<char>(code::named));
    put_varint(code, pool.intern(std::string_view(reinterpret_cast<const char*>(mark),
                                                  static_cast<std::size_t>(p - mark))));
}
action tuple_keyword {
    // the parameter's components, at the top only (python substitutes
    // them where the whole text begins with "tuple")
    if (tuples.empty() && components) {
        if (!components->tuple(code)) { ok = false; fbreak; }
    } else {
        code.push_back(static_cast<char>(code::named));
        put_varint(code, pool.intern("tuple"));
    }
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
action field_next {
    counts.back()++;
    code.push_back(0);
    base_at = code.size();
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
ident = [A-Za-z_$] [A-Za-z0-9_$]*;
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
    bool ok = true;
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

}  // namespace pan::sigdb
