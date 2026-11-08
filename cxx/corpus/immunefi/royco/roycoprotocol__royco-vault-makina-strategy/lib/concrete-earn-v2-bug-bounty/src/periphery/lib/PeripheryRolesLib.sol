// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title PeripheryRolesLib
 * @dev Library containing role definitions for periphery contracts
 */
library PeripheryRolesLib {
    /// @dev Role for operators that can adjust total assets in strategies
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant OPERATOR_ADMIN = keccak256("OPERATOR_ADMIN");

    /// @dev Role for strategy administrators
    bytes32 public constant STRATEGY_ADMIN = keccak256("STRATEGY_ADMIN");
    bytes32 public constant STRATEGY_ADMIN_ADMIN = keccak256("STRATEGY_ADMIN_ADMIN");
}
