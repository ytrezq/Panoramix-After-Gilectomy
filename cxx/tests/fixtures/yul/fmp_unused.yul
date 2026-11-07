// No free memory pointer at all (static frames, as Vyper's): the word at 0x40
// is plain data and the code never writes it first.
//   scratchOnly(uint256,uint256) f1008add   0x40 as an operand of a hash
//   ptrAlias(uint256,uint256)    6472cd88   a pointer from calldata may alias 0x80
//   anything else: returns 0x40, 0, calldatasize
object "FmpUnused" {
    code {
        let sel := shr(224, calldataload(0))
        if eq(sel, 0xf1008add) { scratchOnly(calldataload(4), calldataload(36)) }
        if eq(sel, 0x6472cd88) { ptrAlias(calldataload(4), calldataload(36)) }
        mstore(0x40, calldatasize())
        mstore(0x00, 0x40)
        return(0x00, 0x60)

        function scratchOnly(a, b) {
            mstore(0x40, a)
            mstore(0x00, b)
            mstore(0x20, add(mload(0x40), mload(0x00)))
            mstore(0x40, keccak256(0x00, 0x40))
            return(0x20, 0x40)
        }
        function ptrAlias(p, v) {
            p := and(p, 0xe0)
            mstore(0x80, 7)
            mstore(p, v)
            mstore(0x100, mload(0x80))
            mstore(0x120, mload(0x40))
            return(0x100, 0x40)
        }
    }
}
