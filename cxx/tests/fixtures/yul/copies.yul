// Overlapping copies: loops (forward, backward, bytewise) and MCOPY, the
// destination above and below the source. Memory starts as a copy of the code.
//   loopFwd(uint256,uint256,uint256)   6319684f   ascending words: smears when dst > src
//   loopBwd(uint256,uint256,uint256)   cfa9bdcb   descending words: a memmove
//   loopBytes(uint256,uint256,uint256) c21d5a80   mstore8 of byte 0, dst below src
//   mcopyFwd(uint256,uint256,uint256)  b78f1d71   MCOPY, dst above src
//   mcopyBwd(uint256,uint256,uint256)  4005c4f5   MCOPY, dst below src
//   mcopyCalldata(bytes)               8bd05801   calldata moved over itself twice
object "Copies" {
    code {
        mstore(0x40, 0x80)
        codecopy(0x80, 0, 0x400)
        let sel := shr(224, calldataload(0))
        let a := and(calldataload(4), 0x1ff)
        let b := and(calldataload(36), 0x1ff)
        let n := and(calldataload(68), 0x1ff)
        switch sel
        case 0x6319684f { loopFwd(a, b, n) }
        case 0xcfa9bdcb { loopBwd(a, b, n) }
        case 0xc21d5a80 { loopBytes(a, b, n) }
        case 0xb78f1d71 { mcopyFwd(a, b, n) }
        case 0x4005c4f5 { mcopyBwd(a, b, n) }
        case 0x8bd05801 { mcopyCalldata() }
        default { revert(0, 0) }

        function done() { return(0x80, 0x480) }
        function loopFwd(src, dst, n) {
            src := add(0x80, src)
            dst := add(src, and(dst, 0x3f))
            for { let i := 0 } lt(i, n) { i := add(i, 0x20) } {
                mstore(add(dst, i), mload(add(src, i)))
            }
            done()
        }
        function loopBwd(src, dst, n) {
            src := add(0x80, src)
            dst := add(src, and(dst, 0x3f))
            let i := and(add(n, 0x1f), not(0x1f))
            for { } gt(i, 0) { } {
                i := sub(i, 0x20)
                mstore(add(dst, i), mload(add(src, i)))
            }
            done()
        }
        function loopBytes(src, dst, n) {
            dst := add(0x80, dst)
            src := add(dst, and(src, 0x3f))
            for { let i := 0 } lt(i, n) { i := add(i, 1) } {
                mstore8(add(dst, i), byte(0, mload(add(src, i))))
            }
            done()
        }
        function mcopyFwd(src, dst, n) {
            src := add(0x80, src)
            mcopy(add(src, and(dst, 0x3f)), src, n)
            done()
        }
        function mcopyBwd(src, dst, n) {
            dst := add(0x80, dst)
            mcopy(dst, add(dst, and(src, 0x3f)), n)
            done()
        }
        function mcopyCalldata() {
            let len := and(calldataload(add(4, calldataload(4))), 0x1ff)
            calldatacopy(0x80, add(36, calldataload(4)), len)
            mcopy(0xa0, 0x80, len)
            mcopy(0x80, 0x90, len)
            done()
        }
    }
}
