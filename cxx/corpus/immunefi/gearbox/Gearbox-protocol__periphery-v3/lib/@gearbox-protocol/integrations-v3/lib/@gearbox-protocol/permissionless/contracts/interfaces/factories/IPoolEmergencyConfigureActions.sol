// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

interface IPoolEmergencyConfigureActions {
    function setCreditManagerDebtLimitToZero(address creditManager) external;
    function setTokenLimitToZero(address token) external;
    function pause() external;
}
