// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

interface ISYToken {
    function deposit(
        address receiver,
        address tokenIn,
        uint256 amountTokenToDeposit,
        uint256 minSharesOut
    ) external payable returns (uint256 amountSharesOut);

    function isValidTokenIn(address token) external view returns (bool);
}