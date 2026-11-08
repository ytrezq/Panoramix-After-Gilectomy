// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20("MockERC20", "MOCK") {
    uint8 mockDecimals = 18;

    constructor(uint8 _decimals) {
        mockDecimals = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return mockDecimals;
    }

    function mintTo(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}
