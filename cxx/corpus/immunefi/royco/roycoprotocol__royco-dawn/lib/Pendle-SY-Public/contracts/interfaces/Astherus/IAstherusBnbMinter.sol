// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IAstherusBnbMinter {
    function mintAsBnb() external payable returns (uint256);

    function mintAsBnb(uint256 amountIn) external returns (uint256);

    function convertToTokens(uint256 asBnbAmt) external view returns (uint256);

    function withdrawalFeeRate() external view returns (uint256);

    function convertToAsBnb(uint256 tokens) external view returns (uint256);

    function burnAsBnb(uint256 amountToBurn) external returns (uint256);
}
