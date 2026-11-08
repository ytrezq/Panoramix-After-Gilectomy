// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {CrossChainCall, SignedBatch, SignedRecoveryModeMessage} from "./Types.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

/// @title Cross-chain multisig interface
interface ICrossChainMultisig is IVersion {
    // ------ //
    // EVENTS //
    // ------ //

    event AddSigner(address indexed signer);
    event DisableRecoveryMode();
    event EnableRecoveryMode(bytes32 indexed startingBatchHash);
    event ExecuteBatch(bytes32 indexed batchHash);
    event RemoveSigner(address indexed signer);
    event SetConfirmationThreshold(uint8 newConfirmationThreshold);
    event SignBatch(bytes32 indexed batchHash, address indexed signer);
    event SubmitBatch(bytes32 indexed batchHash);

    // ------ //
    // ERRORS //
    // ------ //

    error BatchIsNotSubmittedException(bytes32 batchHash);
    error CallerIsNotSelfException(address caller);
    error CantBeExecutedOnCurrentChainException();
    error DuplicateSignatureException(address signer);
    error InsufficientNumberOfSignaturesException();
    error InvalidBatchException();
    error InvalidConfirmationThresholdException();
    error InvalidPrevHashException();
    error InvalidRecoveryModeMessageException();
    error InvalidSignerAddressException();
    error SignerIsAlreadyApprovedException(address signer);
    error SignerIsNotApprovedException(address signer);

    // --------------- //
    // EIP-712 GETTERS //
    // --------------- //

    function domainSeparatorV4() external view returns (bytes32);
    function CROSS_CHAIN_CALL_TYPEHASH() external view returns (bytes32);
    function BATCH_TYPEHASH() external view returns (bytes32);
    function COMPACT_BATCH_TYPEHASH() external view returns (bytes32);
    function RECOVERY_MODE_TYPEHASH() external view returns (bytes32);
    function computeCrossChainCallHash(CrossChainCall calldata call) external view returns (bytes32);
    function computeBatchHash(string memory name, CrossChainCall[] calldata calls, bytes32 prevHash)
        external
        view
        returns (bytes32);
    function computeCompactBatchHash(string memory name, bytes32 batchHash, bytes32 prevHash)
        external
        view
        returns (bytes32);
    function computeRecoveryModeHash(uint256 chainId, bytes32 startingBatchHash) external view returns (bytes32);

    // ---------- //
    // GOVERNANCE //
    // ---------- //

    function lastBatchHash() external view returns (bytes32);
    function getExecutedBatchHashes() external view returns (bytes32[] memory);
    function getCurrentBatchHashes() external view returns (bytes32[] memory);
    function getConnectedBatchHashes(bytes32 batchHash) external view returns (bytes32[] memory);
    function getBatch(bytes32 batchHash) external view returns (SignedBatch memory);
    function submitBatch(string calldata name, CrossChainCall[] calldata calls, bytes32 prevHash) external;
    function signBatch(bytes32 batchHash, bytes calldata signature) external;
    function executeBatch(SignedBatch calldata batch) external;

    // ------------------ //
    // SIGNERS MANAGEMENT //
    // ------------------ //

    function isSigner(address account) external view returns (bool);
    function getSigners() external view returns (address[] memory);
    function confirmationThreshold() external view returns (uint8);
    function addSigner(address signer) external;
    function removeSigner(address signer) external;
    function setConfirmationThreshold(uint8 newThreshold) external;

    // ------------- //
    // RECOVERY MODE //
    // ------------- //

    function isRecoveryModeEnabled() external view returns (bool);
    function enableRecoveryMode(SignedRecoveryModeMessage calldata message) external;
    function disableRecoveryMode(uint256 chainId) external;
}
