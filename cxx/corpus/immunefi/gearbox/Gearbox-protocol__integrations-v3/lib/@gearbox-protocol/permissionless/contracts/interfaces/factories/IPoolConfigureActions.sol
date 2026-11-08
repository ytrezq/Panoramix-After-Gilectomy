// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

interface IPoolConfigureActions {
    function setTotalDebtLimit(uint256 limit) external;
    function setCreditManagerDebtLimit(address creditManager, uint256 limit) external;
    function setTokenLimit(address token, uint96 limit) external;
    function setTokenQuotaIncreaseFee(address token, uint16 fee) external;
    function pause() external;
    function unpause() external;
}
