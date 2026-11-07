// The word at 0x40 written below 0x60 after a solc-like prologue: a decompiler
// that takes mem[0x40] for solc's free memory pointer (always >= 0x80, never
// overlapped by what is allocated from it) gets these functions wrong.
//   lowerFmp(uint256)   c79361d7   the "allocation" from 0x20 covers the word
//   fmpBranch(uint256)  a714ee33   branches on mem[0x40] < 0x60 and == 0
//   overlapFmp(uint256) 4043af3f   writes at mem[0x40] + k overlapping the word
//   zeroSlot(uint256)   192b7e86   the zero slot 0x60 used as data
object "FmpLowered" {
    code {
        mstore(0x40, 0x80)
        if iszero(lt(calldatasize(), 4)) {
            switch shr(224, calldataload(0))
            case 0xc79361d7 { lowerFmp(calldataload(4)) }
            case 0xa714ee33 { fmpBranch(calldataload(4)) }
            case 0x4043af3f { overlapFmp(calldataload(4)) }
            case 0x192b7e86 { zeroSlot(calldataload(4)) }
        }
        revert(0, 0)

        function lowerFmp(x) {
            mstore(0x40, 0x20)
            let p := mload(0x40)
            mstore(add(p, 0x20), add(x, 1))
            mstore(p, x)
            let q := mload(0x40)
            mstore(0x40, add(p, 0x40))
            mstore(0x80, q)
            return(p, 0x80)
        }
        function fmpBranch(x) {
            mstore(0x40, and(x, 0xff))
            let r := 1
            if lt(mload(0x40), 0x60) { r := 2 }
            if iszero(mload(0x40)) { r := 3 }
            if gt(mload(0x40), 0x7f) { r := add(r, 4) }
            mstore(0x80, r)
            mstore(0xa0, mload(0x40))
            return(0x80, 0x40)
        }
        function overlapFmp(x) {
            mstore(0x40, sub(0x40, and(x, 0x3f)))
            let p := mload(0x40)
            mstore(p, not(x))
            mstore(add(p, 0x20), x)
            let q := mload(0x40)
            mstore(0xc0, q)
            return(0x00, 0xe0)
        }
        function zeroSlot(x) {
            mstore(0x60, x)
            let len := mload(0x60)
            mstore(0x80, 0x20)
            mstore(0xa0, and(len, 0x3f))
            mstore(0xc0, keccak256(0x60, 0x20))
            return(0x80, 0x60)
        }
    }
}
