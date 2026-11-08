// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWrapper is IERC20 {
    /// @dev `msg.value` of coinbase sent to this contract grants caller account a matching increase
    /// in Wrapper token balance.
    function deposit() external payable;

    /// @dev Burn `value` Wrapper token from caller account and withdraw matching coinbase to the same.
    function withdraw(uint256 value) external;
}
