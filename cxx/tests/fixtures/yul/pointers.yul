// Memory pointers that follow no allocation discipline.
//   ptrStored(uint256,uint256) 54401de7   a pointer kept in memory, its object
//                                         overwritten through another pointer
//   downAlloc(uint256,uint256) 443b39a8   an allocator growing downwards
//   ptrWrap(uint256)           5224f062   pointer arithmetic wrapping around 2**256
object "Pointers" {
    code {
        mstore(0x40, 0x80)
        switch shr(224, calldataload(0))
        case 0x54401de7 { ptrStored(calldataload(4), calldataload(36)) }
        case 0x443b39a8 { downAlloc(calldataload(4), calldataload(36)) }
        case 0x5224f062 { ptrWrap(calldataload(4)) }
        default { revert(0, 0) }

        function ptrStored(a, b) {
            let obj := mload(0x40)
            mstore(0x40, add(obj, 0x40))
            mstore(obj, a)
            mstore(add(obj, 0x20), b)
            mstore(0x200, obj)
            let other := add(obj, and(b, 0x20))
            mstore(other, 0x1234)
            let p := mload(0x200)
            mstore(0x220, mload(p))
            mstore(0x240, mload(add(p, 0x20)))
            return(0x220, 0x40)
        }
        function downAlloc(a, n) {
            mstore(0x40, 0x400)
            n := and(n, 7)
            for { let i := 0 } lt(i, n) { i := add(i, 1) } {
                let p := sub(mload(0x40), 0x20)
                mstore(0x40, p)
                mstore(p, add(a, i))
            }
            let top := mload(0x40)
            mstore(0x00, top)
            mstore(0x20, mload(top))
            mstore(0x440, mload(0x3e0))
            return(0x00, 0x40)
        }
        function ptrWrap(x) {
            let p := mload(0x40)
            let q := add(p, not(0x1f))
            mstore(q, x)
            let r := add(add(q, 0x20), not(0))
            mstore8(r, 0xab)
            return(q, 0x40)
        }
    }
}
