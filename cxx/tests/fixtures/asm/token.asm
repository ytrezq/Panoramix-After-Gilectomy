// A token as Huff contracts are written (assemble.py: Huff without macros):
// no free memory pointer, the selector left on the stack by the dispatcher,
// no check of the calldata's size or of its words (an address is the whole
// word), a balance's slot keccak(account . 1) made in the scratch words.
// Slots: 0 the total supply, 1 the balances, 2 the owner.
0x00 calldataload 0xe0 shr
dup1 0x70a08231 eq @balance_of jumpi
dup1 0x18160ddd eq @total_supply jumpi
dup1 0xa9059cbb eq @transfer jumpi
dup1 0x40c10f19 eq @mint jumpi
0x00 0x00 revert

// balanceOf(address)
balance_of:
    0x04 calldataload 0x00 mstore 0x01 0x20 mstore 0x40 0x00 sha3
    sload 0x00 mstore 0x20 0x00 return

// totalSupply()
total_supply:
    0x00 sload 0x00 mstore 0x20 0x00 return

// transfer(address,uint256): the caller's balance at least the amount
transfer:
    caller 0x00 mstore 0x01 0x20 mstore 0x40 0x00 sha3  // [sel from]
    dup1 sload                                          // [sel from balance]
    0x24 calldataload                                   // [sel from balance amount]
    dup1 dup3 lt @short jumpi
    swap1 sub swap1 sstore
    0x04 calldataload 0x00 mstore 0x01 0x20 mstore 0x40 0x00 sha3
    dup1 sload 0x24 calldataload add swap1 sstore
    0x24 calldataload 0x00 mstore
    0x04 calldataload caller 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef 0x20 0x00 log3
    0x01 0x00 mstore 0x20 0x00 return
short:
    0x00 0x00 revert

// mint(address,uint256): the owner's only
mint:
    0x02 sload caller eq @owner jumpi
    0x00 0x00 revert
owner:
    0x04 calldataload 0x00 mstore 0x01 0x20 mstore 0x40 0x00 sha3
    dup1 sload 0x24 calldataload add swap1 sstore
    0x00 sload 0x24 calldataload add 0x00 sstore
    stop
