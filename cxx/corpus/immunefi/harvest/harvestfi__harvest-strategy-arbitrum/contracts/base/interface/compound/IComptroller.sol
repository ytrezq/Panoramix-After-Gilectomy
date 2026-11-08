// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

interface IComptroller {
    function enterMarkets(address[] memory cTokens) external returns (uint[] memory);
    function borrowCaps(address cToken) external view returns (uint256);
    function supplyCaps(address cToken) external view returns (uint256);
    function getRewardDistributors() external view returns (address[] memory);
}
