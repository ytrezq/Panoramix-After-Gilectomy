// The names of the getters (names.hpp): Ragel machines over the bytes of a
// signature database's name (rule 2: no comparison of names).
#include "storage/names.hpp"

#include <array>

namespace pan::storage::detail {

namespace {

%%{
    machine good_name;
    write data noerror noentry;

    ident = [A-Za-z_] [A-Za-z0-9_]*;
    # what a name of the output means already (python RESERVED)
    reserved = 'stor' | 'mem' | 'call' | 'calldata' | 'block' | 'tx' | 'msg' | 'this' | 'caller'
             | 'Mask' | 'Bytes' | 'Array' | 'concat' | 'sha3' | 'bool' | 'address' | 'ceil32'
             | 'floor32' | 'addmod' | 'mulmod' | 'max' | 'min' | 'ext_call' | 'ext_code' | 'eth'
             | 'transient' | 'not' | 'and' | 'or' | 'if' | 'while' | 'return' | 'revert';
    # python: startswith("unknown"), startswith("_"), the default names
    bad = reserved | '_' any* | 'unknown' any*
        | ( 'u'? 'int' | 'bytes' | 'stor' ) digit*
        | 'stor' [0-9A-F]+ ( '_' digit+ )?
        | 'stor' digit+ '_' digit+;

    main := ident - bad;
}%%

%%{
    machine get_prefix;
    write data noerror nofinal noentry;
    main := 'get' [A-Z] @{ found = true; fbreak; };
}%%

}  // namespace

bool good_name(std::span<const u8> name) noexcept {
    if (name.empty()) return false;
    int cs;
    const u8* p = name.data();
    const u8* pe = p + name.size();
    %%{
        machine good_name;
        write init;
        write exec;
    }%%
    // (the whole name read: a final state, not the error state 0)
    return cs >= good_name_first_final;
}

GetterName getter_name(std::span<const u8> name) noexcept {
    bool found = false;
    {
        int cs;
        const u8* p = name.data();
        const u8* pe = p + name.size();
        %%{
            machine get_prefix;
            write init;
            write exec;
        }%%
        (void)cs;
    }
    if (!found) return GetterName{good_name(name), false};
    // getBalance -> balance (an ASCII uppercase letter: its lowercase)
    std::array<u8, 256> buf;
    if (name.size() - 3 > buf.size()) return GetterName{false, true};
    const usize n = name.size() - 3;
    buf[0] = u8(name[3] | 0x20);
    for (usize i = 1; i < n; ++i) buf[i] = name[3 + i];
    return GetterName{good_name(std::span<const u8>(buf.data(), n)), true};
}

}  // namespace pan::storage::detail
