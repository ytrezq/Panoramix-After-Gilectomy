// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ITreeHouseRouter {
    function depositETH() external payable;

    function deposit(address _asset, uint256 _amount) external;

    function depositCapInEth() external view returns (uint256);
}
