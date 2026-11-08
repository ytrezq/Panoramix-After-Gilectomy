// SPDX-License-Identifier: GPL-v3
pragma solidity =0.8.21;

import '../DeltaSwapERC20.sol';

contract ERC20 is DeltaSwapERC20 {
    constructor(uint256 _totalSupply) {
        _mint(msg.sender, _totalSupply);
    }
}