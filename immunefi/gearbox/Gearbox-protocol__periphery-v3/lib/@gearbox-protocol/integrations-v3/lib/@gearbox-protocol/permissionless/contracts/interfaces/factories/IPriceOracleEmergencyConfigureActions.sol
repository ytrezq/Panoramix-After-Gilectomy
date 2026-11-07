// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

interface IPriceOracleEmergencyConfigureActions {
    function setPriceFeed(address token, address priceFeed) external;
}
