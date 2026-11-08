// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {LibString} from "@solady/utils/LibString.sol";

import {CrossChainCall, ICrossChainMultisig} from "../interfaces/ICrossChainMultisig.sol";
import {SignedBatch, SignedRecoveryModeMessage} from "../interfaces/Types.sol";
import {EIP712Mainnet} from "../helpers/EIP712Mainnet.sol";
import {AP_CROSS_CHAIN_MULTISIG} from "../libraries/ContractLiterals.sol";

/// @title Cross-chain multisig
contract CrossChainMultisig is EIP712Mainnet, Ownable, ReentrancyGuard, ICrossChainMultisig {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using LibString for bytes32;
    using LibString for uint256;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_CROSS_CHAIN_MULTISIG;

    /// @notice Cross-chain call typehash
    bytes32 public constant override CROSS_CHAIN_CALL_TYPEHASH =
        keccak256("CrossChainCall(uint256 chainId,address target,bytes callData)");

    /// @notice Batch typehash
    /// @dev This typehash is used to identify batches
    bytes32 public constant override BATCH_TYPEHASH =
        keccak256("Batch(string name,CrossChainCall[] calls,bytes32 prevHash)");

    /// @notice Compact batch typehash
    /// @dev This typehash is used for signing to avoid cluttering the message with calls
    bytes32 public constant override COMPACT_BATCH_TYPEHASH =
        keccak256("CompactBatch(string name,bytes32 batchHash,bytes32 prevHash)");

    /// @notice Recovery mode typehash
    bytes32 public constant override RECOVERY_MODE_TYPEHASH =
        keccak256("RecoveryMode(uint256 chainId,bytes32 startingBatchHash)");

    /// @notice Confirmation threshold
    uint8 public override confirmationThreshold;

    /// @notice Whether recovery mode is enabled
    bool public override isRecoveryModeEnabled = false;

    /// @dev Set of approved signers
    EnumerableSet.AddressSet internal _signersSet;

    /// @dev List of executed batch hashes
    bytes32[] internal _executedBatchHashes;

    /// @dev Mapping from `batchHash` to the set of connected batch hashes
    mapping(bytes32 batchHash => EnumerableSet.Bytes32Set) internal _connectedBatchHashes;

    /// @dev Mapping from `batchHash` to signed batch
    mapping(bytes32 batchHash => SignedBatch) internal _signedBatches;

    /// @dev Ensures that function can only be called on Ethereum Mainnet
    modifier onlyOnMainnet() {
        if (block.chainid != 1) revert CantBeExecutedOnCurrentChainException();
        _;
    }

    /// @dev Ensures that function can only be called outside Ethereum Mainnet
    modifier onlyNotOnMainnet() {
        if (block.chainid == 1) revert CantBeExecutedOnCurrentChainException();
        _;
    }

    /// @dev Ensures that function can only be called by the contract itself
    modifier onlySelf() {
        if (msg.sender != address(this)) revert CallerIsNotSelfException(msg.sender);
        _;
    }

    /// @notice Constructor
    /// @param signers_ Array of initial signers
    /// @param confirmationThreshold_ Confirmation threshold
    /// @param owner_ Owner of the contract, assumed to be Gearbox DAO
    constructor(address[] memory signers_, uint8 confirmationThreshold_, address owner_)
        EIP712Mainnet(contractType.fromSmallString(), version.toString())
    {
        uint256 len = signers_.length;
        for (uint256 i; i < len; ++i) {
            _addSigner(signers_[i]);
        }
        _setConfirmationThreshold(confirmationThreshold_);
        _transferOwnership(owner_);
    }

    // --------------- //
    // EIP-712 GETTERS //
    // --------------- //

    /// @notice Returns the domain separator
    function domainSeparatorV4() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Computes struct hash for cross-chain call
    function computeCrossChainCallHash(CrossChainCall calldata call) public pure override returns (bytes32) {
        return keccak256(abi.encode(CROSS_CHAIN_CALL_TYPEHASH, call.chainId, call.target, keccak256(call.callData)));
    }

    /// @notice Computes struct hash for batch
    function computeBatchHash(string calldata name, CrossChainCall[] calldata calls, bytes32 prevHash)
        public
        pure
        returns (bytes32)
    {
        uint256 len = calls.length;
        bytes32[] memory callHashes = new bytes32[](len);
        for (uint256 i; i < len; ++i) {
            callHashes[i] = computeCrossChainCallHash(calls[i]);
        }
        return keccak256(
            abi.encode(BATCH_TYPEHASH, keccak256(bytes(name)), keccak256(abi.encodePacked(callHashes)), prevHash)
        );
    }

    /// @notice Computes struct hash for compact batch
    function computeCompactBatchHash(string memory name, bytes32 batchHash, bytes32 prevHash)
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes(name)), batchHash, prevHash));
    }

    /// @notice Computes struct hash for recovery mode
    function computeRecoveryModeHash(uint256 chainId, bytes32 startingBatchHash)
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encode(RECOVERY_MODE_TYPEHASH, chainId, startingBatchHash));
    }

    // ---------- //
    // GOVERNANCE //
    // ---------- //

    /// @notice Returns the hash of the last executed batch
    function lastBatchHash() public view override returns (bytes32) {
        uint256 len = _executedBatchHashes.length;
        return len == 0 ? bytes32(0) : _executedBatchHashes[len - 1];
    }

    /// @notice Returns list of executed batch hashes
    function getExecutedBatchHashes() external view returns (bytes32[] memory) {
        return _executedBatchHashes;
    }

    /// @notice Returns list of batch hashes connected to the last executed batch
    function getCurrentBatchHashes() external view returns (bytes32[] memory) {
        return _connectedBatchHashes[lastBatchHash()].values();
    }

    /// @notice Returns list of batch hashes connected to a batch with `batchHash`
    function getConnectedBatchHashes(bytes32 batchHash) external view override returns (bytes32[] memory) {
        return _connectedBatchHashes[batchHash].values();
    }

    /// @notice Returns batch by hash
    function getBatch(bytes32 batchHash) external view returns (SignedBatch memory result) {
        return _signedBatches[batchHash];
    }

    /// @notice Allows Gearbox DAO to submit a new batch on Ethereum Mainnet
    /// @dev Can only be executed by Gearbox DAO on Ethereum Mainnet
    /// @dev If batch contains `disableRecoveryMode` self-call, it must be its only call
    /// @dev Reverts if `prevHash` is not the hash of the last executed batch
    /// @dev Reverts if `calls` is empty or contains local self-calls
    function submitBatch(string calldata name, CrossChainCall[] calldata calls, bytes32 prevHash)
        external
        override
        onlyOwner
        onlyOnMainnet
        nonReentrant
    {
        bytes32 batchHash = computeBatchHash(name, calls, prevHash);
        if (!_connectedBatchHashes[lastBatchHash()].add(batchHash)) return;

        _verifyBatch(calls, prevHash);

        SignedBatch storage signedBatch = _signedBatches[batchHash];
        signedBatch.name = name;
        signedBatch.prevHash = prevHash;
        uint256 len = calls.length;
        for (uint256 i; i < len; ++i) {
            signedBatch.calls.push(calls[i]);
        }

        emit SubmitBatch(batchHash);
    }

    /// @notice Submits a signature for a compact batch message for a batch with `batchHash`.
    ///         If the number of signatures reaches confirmation threshold, the batch is executed.
    /// @dev Can only be executed on Ethereum Mainnet (though permissionlessly to ease signers' life)
    /// @dev Reverts if batch with `batchHash` hasn't been submitted or is not connected to the last executed batch
    /// @dev Reverts if signer is not approved or their signature has already been submitted
    function signBatch(bytes32 batchHash, bytes calldata signature) external override onlyOnMainnet nonReentrant {
        SignedBatch storage signedBatch = _signedBatches[batchHash];
        if (signedBatch.calls.length == 0) revert BatchIsNotSubmittedException(batchHash);
        if (signedBatch.prevHash != lastBatchHash()) revert InvalidPrevHashException();

        bytes32 digest = _hashTypedDataV4(computeCompactBatchHash(signedBatch.name, batchHash, signedBatch.prevHash));
        address signer = ECDSA.recover(digest, signature);
        if (!_signersSet.contains(signer)) revert SignerIsNotApprovedException(signer);

        signedBatch.signatures.push(signature);
        emit SignBatch(batchHash, signer);

        uint256 validSignatures = _verifySignatures(signedBatch.signatures, digest);
        if (validSignatures >= confirmationThreshold) _executeBatch(signedBatch.calls, batchHash);
    }

    /// @notice Executes a proposal outside Ethereum Mainnet permissionlessly
    /// @dev In the current implementation, signers are trusted not to deviate and only sign batches
    ///      submitted by Gearbox DAO on Ethereum Mainnet. In future versions, DAO decisions will be
    ///      propagated to other chains using bridges or `L1SLOAD`.
    /// @dev If batch contains `disableRecoveryMode` self-call, it must be its only call
    /// @dev Reverts if batch's `prevHash` is not the hash of the last executed batch
    /// @dev Reverts if batch is empty or contains local self-calls
    /// @dev Reverts if signatures have duplicates or the number of valid signatures is insufficient
    function executeBatch(SignedBatch calldata signedBatch) external override onlyNotOnMainnet nonReentrant {
        _verifyBatch(signedBatch.calls, signedBatch.prevHash);

        bytes32 batchHash = computeBatchHash(signedBatch.name, signedBatch.calls, signedBatch.prevHash);

        bytes32 digest = _hashTypedDataV4(computeCompactBatchHash(signedBatch.name, batchHash, signedBatch.prevHash));
        uint256 validSignatures = _verifySignatures(signedBatch.signatures, digest);
        if (validSignatures < confirmationThreshold) revert InsufficientNumberOfSignaturesException();

        _executeBatch(signedBatch.calls, batchHash);
    }

    /// @dev Ensures that batch is connected to the last executed batch, is non-empty and contains no local self-calls
    /// @dev If batch contains `disableRecoveryMode` self-call, it must be its only call
    function _verifyBatch(CrossChainCall[] memory calls, bytes32 prevHash) internal view {
        if (prevHash != lastBatchHash()) revert InvalidPrevHashException();

        uint256 len = calls.length;
        if (len == 0) revert InvalidBatchException();
        for (uint256 i; i < len; ++i) {
            if (calls[i].target == address(this)) {
                if (calls[i].chainId != 0) revert InvalidBatchException();
                if (bytes4(calls[i].callData) == ICrossChainMultisig.disableRecoveryMode.selector && len != 1) {
                    revert InvalidBatchException();
                }
            }
        }
    }

    /// @dev Executes a batch of calls skipping local calls from other chains, updates the last executed batch hash
    /// @dev In recovery mode, only self-calls are executed
    function _executeBatch(CrossChainCall[] memory calls, bytes32 batchHash) internal {
        uint256 len = calls.length;
        for (uint256 i; i < len; ++i) {
            if (isRecoveryModeEnabled && calls[i].target != address(this)) continue;
            uint256 chainId = calls[i].chainId;
            if (chainId == 0 || chainId == block.chainid) {
                calls[i].target.functionCall(calls[i].callData, "Call execution failed");
            }
        }
        _executedBatchHashes.push(batchHash);
        emit ExecuteBatch(batchHash);
    }

    // ------------------ //
    // SIGNERS MANAGEMENT //
    // ------------------ //

    /// @notice Returns whether `account` is an approved signer
    function isSigner(address account) external view override returns (bool) {
        return _signersSet.contains(account);
    }

    /// @notice Returns list of approved signers
    function getSigners() external view override returns (address[] memory) {
        return _signersSet.values();
    }

    /// @notice Adds `signer` to the list of approved signers
    /// @dev Can only be called by the contract itself
    /// @dev Reverts if signer is zero address or is already approved
    function addSigner(address signer) external override onlySelf {
        _addSigner(signer);
    }

    /// @notice Removes `signer` from the list of approved signers
    /// @dev Can only be called by the contract itself
    /// @dev Reverts if signer is not approved
    /// @dev Reverts if removing the signer makes multisig have less than `confirmationThreshold` signers
    function removeSigner(address signer) external override onlySelf {
        if (!_signersSet.remove(signer)) revert SignerIsNotApprovedException(signer);
        if (_signersSet.length() < confirmationThreshold) revert InvalidConfirmationThresholdException();
        emit RemoveSigner(signer);
    }

    /// @notice Sets the minimum number of signatures required to execute a batch to `newConfirmationThreshold`
    /// @dev Can only be called by the contract itself
    /// @dev Reverts if the new confirmation threshold is 0 or greater than the number of signers
    function setConfirmationThreshold(uint8 newConfirmationThreshold) external override onlySelf {
        _setConfirmationThreshold(newConfirmationThreshold);
    }

    /// @dev `addSigner` implementation
    function _addSigner(address signer) internal {
        if (signer == address(0)) revert InvalidSignerAddressException();
        if (!_signersSet.add(signer)) revert SignerIsAlreadyApprovedException(signer);
        emit AddSigner(signer);
    }

    /// @dev `setConfirmationThreshold` implementation
    function _setConfirmationThreshold(uint8 newConfirmationThreshold) internal {
        if (newConfirmationThreshold == 0 || newConfirmationThreshold > _signersSet.length()) {
            revert InvalidConfirmationThresholdException();
        }
        if (newConfirmationThreshold == confirmationThreshold) return;
        confirmationThreshold = newConfirmationThreshold;
        emit SetConfirmationThreshold(newConfirmationThreshold);
    }

    /// @dev Ensures that the list of signatures has no duplicates and returns the number of valid signatures
    function _verifySignatures(bytes[] memory signatures, bytes32 digest)
        internal
        view
        returns (uint256 validSignatures)
    {
        uint256 len = signatures.length;
        address[] memory signers = new address[](len);
        for (uint256 i; i < len; ++i) {
            address signer = ECDSA.recover(digest, signatures[i]);
            if (_signersSet.contains(signer)) validSignatures++;
            for (uint256 j; j < i; ++j) {
                if (signers[j] == signer) revert DuplicateSignatureException(signer);
            }
            signers[i] = signer;
        }
    }

    // ------------- //
    // RECOVERY MODE //
    // ------------- //

    /// @notice If `message.chainId` matches current chain, enables recovery mode, in which only self-calls are executed
    /// @dev Can only be executed outside Ethereum Mainnet
    /// @dev Reverts if starting batch of recovery mode is not the last executed batch
    /// @dev Reverts if the number of signatures is insufficient
    function enableRecoveryMode(SignedRecoveryModeMessage calldata message)
        external
        override
        onlyNotOnMainnet
        nonReentrant
    {
        if (isRecoveryModeEnabled || message.chainId != block.chainid) return;
        if (message.startingBatchHash != lastBatchHash()) revert InvalidRecoveryModeMessageException();

        bytes32 digest = _hashTypedDataV4(computeRecoveryModeHash(message.chainId, message.startingBatchHash));
        uint256 validSignatures = _verifySignatures(message.signatures, digest);
        if (validSignatures < confirmationThreshold) revert InsufficientNumberOfSignaturesException();

        isRecoveryModeEnabled = true;
        emit EnableRecoveryMode(message.startingBatchHash);
    }

    /// @notice If `chainId` matches current chain, disables recovery mode
    /// @dev Can only be executed by the contract itself
    function disableRecoveryMode(uint256 chainId) external override onlySelf {
        if (!isRecoveryModeEnabled || chainId != block.chainid) return;
        isRecoveryModeEnabled = false;
        emit DisableRecoveryMode();
    }
}
