// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IDepositor {
    function deposit(IERC20 asset, uint256 amount, address receiver) external returns (uint256);
}
