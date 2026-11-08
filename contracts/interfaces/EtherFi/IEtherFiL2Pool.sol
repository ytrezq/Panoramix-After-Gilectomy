// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEtherFiL2Pool {
    function deposit(
        address depositAsset,
        uint256 depositAmount,
        uint256 minimumMint
    ) external payable returns (uint256 share);

    function getTokenOut() external view returns (address);

    function getL2ExchangeRateProvider() external view returns (address);
}
