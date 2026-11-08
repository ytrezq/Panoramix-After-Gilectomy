// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IStoneVault {
    function deposit() external payable returns (uint256 mintAmount);

    function latestRoundID() external view returns (uint256);

    function roundPricePerShare(uint256 rID) external view returns (uint256);
}
