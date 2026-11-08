// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IV2Vault {
    function newVault(
        address _token,
        address _guardian,
        address _rewards,
        string memory _name,
        string memory _symbol
    ) external  returns (address ) ;

    function deposit(uint256 _amount, address _recipient) external returns (uint256);
    function withdraw(uint256 _shares, address _recipient) external returns (uint256);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function lastReport() external view returns (uint256);
    function lockedProfit() external view returns (uint256);
    function lockedProfitDegradation() external view returns (uint256);
}