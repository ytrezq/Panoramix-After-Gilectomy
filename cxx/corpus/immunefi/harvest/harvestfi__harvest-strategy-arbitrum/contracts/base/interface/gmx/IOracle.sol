// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IOracle {
    function getPriceFeedMultiplier(address dataStore, address token) external view returns (uint256);
}