//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IMorphoVault {
    function deposit(uint256 assets, address receiver) external;
    function withdraw(uint256 assets, address receiver, address owner) external;
    function asset() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
}