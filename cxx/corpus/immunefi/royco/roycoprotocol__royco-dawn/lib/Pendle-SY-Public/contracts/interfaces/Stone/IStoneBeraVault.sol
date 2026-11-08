// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IStoneBeraVault {
    function deposit(address _asset, uint256 _amount, address _receiver) external returns (uint256 shares);

    function previewDeposit(address _asset, uint256 _amount) external view returns (uint256 shares);

    function cap() external view returns (uint256);

    function feeRate(address) external view returns (uint256);
}
