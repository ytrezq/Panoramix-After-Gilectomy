// A dispatcher on the first byte of the call data, as MEV bots and Huff
// contracts have: packed arguments, no ABI, no selector.
//   cmd & 3 == 0: sstore(byte 1, word at 2)
//   cmd & 3 == 1: return sload(byte 1)
//   cmd & 3 == 2: credit a 12-byte amount to a 20-byte address (one word at 1)
//   cmd & 3 == 3: the caller's credit (nonpayable)
object "DispatchByte" {
    code {
        let cmd := byte(0, calldataload(0))
        switch and(cmd, 3)
        case 0 {
            sstore(byte(1, calldataload(0)), calldataload(2))
            stop()
        }
        case 1 {
            mstore(0, sload(byte(1, calldataload(0))))
            return(0, 0x20)
        }
        case 2 {
            let w := calldataload(1)
            let who := shr(96, w)
            let amount := and(w, 0xffffffffffffffffffffffff)
            mstore(0, who)
            mstore(0x20, 7)
            let slot := keccak256(0, 0x40)
            sstore(slot, add(sload(slot), amount))
            log2(0, 0, 0xdeadbeef, who)
            stop()
        }
        default {
            if callvalue() { revert(0, 0) }
            mstore(0, caller())
            mstore(0x20, 7)
            mstore(0, sload(keccak256(0, 0x40)))
            return(0, 0x20)
        }
    }
}
