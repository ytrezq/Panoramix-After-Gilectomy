// Vyper 0.3.1's dispatcher (assemble.py): the selector copied to
// mem[28] and read as the word at 0, the payable functions' tests first, then
// one callvalue check before the other selectors' tests - each PUSH4 h DUP2
// XOR PUSH2 next JUMPI, the function's body after it; a call of fewer than 4
// bytes goes to the default function without the callvalue check.
// Slots: 0 a counter, 1 the owner.
0x04 calldatasize lt @default jumpi
0x04 0x00 0x1c calldatacopy
0x00 mload

// deposit() payable: counter += callvalue
0xd0e30db0 dup2 xor @nonpayable jumpi
    callvalue 0x00 sload add 0x00 sstore
    stop

nonpayable:
callvalue @fail jumpi

// get(): counter
0x6d4ce63c dup2 xor @next jumpi
    0x00 sload 0x00 mstore 0x20 0x00 return

// set(uint256) by the owner
next:
0x60fe47b1 dup2 xor @none jumpi
    0x01 sload caller eq iszero @fail jumpi
    0x04 calldataload 0x00 sstore
    stop

none:
pop
// the default function: 7
default:
    0x07 0x00 mstore 0x20 0x00 return

fail:
    0x00 0x00 revert
