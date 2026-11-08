// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

interface ICreditEmergencyConfigureActions {
    function forbidAdapter(address adapter) external;
    function forbidToken(address token) external;
    function forbidBorrowing() external;
    function pause() external;
}
