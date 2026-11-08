// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ConcreteV2RolesLib {
    /// Roles and their ADMIN roles.
    bytes32 public constant VAULT_MANAGER = keccak256("VAULT_MANAGER");
    bytes32 public constant VAULT_MANAGER_ADMIN = keccak256("VAULT_MANAGER_ADMIN");

    bytes32 public constant HOOK_MANAGER = keccak256("HOOK_MANAGER");
    bytes32 public constant HOOK_MANAGER_ADMIN = keccak256("HOOK_MANAGER_ADMIN");

    bytes32 public constant STRATEGY_MANAGER = keccak256("STRATEGY_MANAGER");
    bytes32 public constant STRATEGY_MANAGER_ADMIN = keccak256("STRATEGY_MANAGER_ADMIN");

    bytes32 public constant ALLOCATOR = keccak256("ALLOCATOR");
    bytes32 public constant ALLOCATOR_ADMIN = keccak256("ALLOCATOR_ADMIN");

    bytes32 public constant WITHDRAWAL_MANAGER = keccak256("WITHDRAWAL_MANAGER");
    bytes32 public constant WITHDRAWAL_MANAGER_ADMIN = keccak256("WITHDRAWAL_MANAGER_ADMIN");
}
