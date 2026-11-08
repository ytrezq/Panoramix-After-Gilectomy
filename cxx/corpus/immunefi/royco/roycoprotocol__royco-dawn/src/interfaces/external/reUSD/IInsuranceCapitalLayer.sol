// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IInsuranceCapitalLayer
 * @notice Interface for the reUSD insurance capital layer
 * @dev https://etherscan.io/address/0x4691c475be804fa85f91c2d6d0adf03114de3093
 */
interface IInsuranceCapitalLayer {
    function convertFromShares(address token, uint256 shares) external view returns (uint256);
}
