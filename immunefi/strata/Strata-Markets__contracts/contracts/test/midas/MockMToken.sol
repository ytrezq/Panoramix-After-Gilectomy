// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockMToken
 * @dev Simple ERC20 mock for mHYPER in tests
 */
contract MockMToken is ERC20 {
    constructor() ERC20("Mock mHYPER", "mHYPER") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
