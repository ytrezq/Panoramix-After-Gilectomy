// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

struct DefillamaCreditAccountData {
    address creditAccount;
    uint256 debt;
    DefillamaTokenInfo[] tokens;
}

struct DefillamaTokenInfo {
    address token;
    uint256 balance;
}

struct DefillamaPoolData {
    address pool;
    address underlying;
    uint256 availableLiquidity;
    uint256 totalBorrowed;
}
