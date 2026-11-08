// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

/// @title Pausable interface
/// @notice Generic interface of a contract that can be paused and unpaused
interface IPausable {
    function paused() external view returns (bool);
    function pause() external;
    function unpause() external;
}
