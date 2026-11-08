// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

/// @title Instance manager interface
interface IInstanceManager is IVersion {
    // ------ //
    // EVENTS //
    // ------ //

    event SetPendingGovernance(address indexed newGovernance);
    event AcceptGovernance(address indexed newGovernance);

    // ------ //
    // ERRORS //
    // ------ //

    error CallerIsNotCrossChainGovernanceException(address caller);
    error CallerIsNotPendingGovernanceException(address caller);
    error CallerIsNotTreasuryException(address caller);
    error InvalidKeyException(bytes32 key);

    // ------- //
    // GETTERS //
    // ------- //

    function addressProvider() external view returns (address);
    function bytecodeRepository() external view returns (address);
    function instanceManagerProxy() external view returns (address);
    function treasuryProxy() external view returns (address);
    function crossChainGovernanceProxy() external view returns (address);
    function isActivated() external view returns (bool);
    function owner() external view returns (address);
    function pendingGovernance() external view returns (address);

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function activate(address instanceOwner, address treasury, address weth, address gear) external;
    function deploySystemContract(bytes32 contractType, uint256 version, bool saveVersion) external;
    function setGlobalAddress(bytes32 key, address addr, bool saveVersion) external;
    function setLocalAddress(bytes32 key, address addr, bool saveVersion) external;
    function configureGlobal(address target, bytes calldata data) external;
    function configureLocal(address target, bytes calldata data) external;
    function configureTreasury(address target, bytes calldata data) external;
    function setPendingGovernance(address newGovernance) external;
    function acceptGovernance() external;
}
