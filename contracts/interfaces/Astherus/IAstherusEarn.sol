// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

interface IAstherusEarn {
    function deposit(uint256 amountIn) external;

    function exchangePrice() external view returns (uint256);
}
