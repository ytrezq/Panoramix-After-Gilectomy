// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IInfraredBERA {
    function mint(address receiver) external payable returns (uint256 shares);

    function deposits() external view returns (uint256);

    function previewMint(uint256 beraAmount) external view returns (uint256 shares);
}

interface IInfraredBeraFeeReceivor {
    function distribution() external view returns (uint256 amount, uint256 fees);
}
