// Packed calldata, as MEV bots have it (assemble.py: Huff without macros):
// no selector - the first byte says what to do, the arguments follow it
// packed (a key and a value of 32 bytes each, an address in 20 bytes, an
// amount in 16). Slots: keccak(key . 0) the values, 1 the owner.
0x00 calldataload 0xf8 shr
dup1 0x01 eq @set jumpi
dup1 0x02 eq @get jumpi
dup1 0x03 eq @sweep jumpi
0x00 0x00 revert

// 01 key value: the owner sets values[key]
set:
    0x01 sload caller eq iszero @fail jumpi
    0x01 calldataload 0x00 mstore 0x00 0x20 mstore
    0x21 calldataload 0x40 0x00 sha3 sstore
    stop

// 02 key: values[key]
get:
    0x01 calldataload 0x00 mstore 0x00 0x20 mstore
    0x40 0x00 sha3 sload 0x00 mstore 0x20 0x00 return

// 03 to amount: the owner sends amount wei to `to`
sweep:
    0x01 sload caller eq iszero @fail jumpi
    0x00 0x00 0x00 0x00
    0x15 calldataload 0x80 shr
    0x01 calldataload 0x60 shr
    gas call iszero @fail jumpi
    stop

fail:
    0x00 0x00 revert
