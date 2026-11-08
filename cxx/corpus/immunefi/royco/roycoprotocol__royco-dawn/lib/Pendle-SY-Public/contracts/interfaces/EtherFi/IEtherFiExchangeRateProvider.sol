// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEtherFiExchangeRateProvider {
    function getConversionAmount(address token, uint256 amountIn) external view returns (uint256 amountOut);
}
