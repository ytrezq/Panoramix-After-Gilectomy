// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {CrossChainMultisigHarness} from "./CrossChainMultisigHarness.sol";
import {CrossChainCall, SignedBatch, SignedRecoveryModeMessage} from "../../interfaces/ICrossChainMultisig.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ICrossChainMultisig} from "../../interfaces/ICrossChainMultisig.sol";
import {console} from "forge-std/console.sol";
import {SignatureHelper} from "../helpers/SignatureHelper.sol";
import {GeneralMock} from "@gearbox-protocol/core-v3/contracts/test/mocks/GeneralMock.sol";

contract CrossChainMultisigTest is Test, SignatureHelper {
    CrossChainMultisigHarness multisig;

    uint256 signer0PrivateKey = _generatePrivateKey("SIGNER_1");
    uint256 signer1PrivateKey = _generatePrivateKey("SIGNER_2");
    address[] signers;
    uint8 constant THRESHOLD = 2;
    address owner;

    bytes32 COMPACT_BATCH_TYPEHASH = keccak256("CompactBatch(string name,bytes32 batchHash,bytes32 prevHash)");
    bytes32 RECOVERY_MODE_TYPEHASH = keccak256("RecoveryMode(uint256 chainId,bytes32 startingBatchHash)");

    function setUp() public {
        // Setup initial signers
        signers = new address[](3);
        signers[0] = vm.addr(signer0PrivateKey);
        signers[1] = vm.addr(signer1PrivateKey);
        signers[2] = makeAddr("signer3");

        owner = makeAddr("owner");

        // Deploy contract
        multisig = new CrossChainMultisigHarness(signers, THRESHOLD, owner);
    }

    function _getDigest(bytes32 structHash) internal view returns (bytes32) {
        bytes32 domainSeparator = multisig.domainSeparatorV4();
        return ECDSA.toTypedDataHash(domainSeparator, structHash);
    }

    function _signBatch(uint256 privateKey, CrossChainCall[] memory calls, bytes32 prevHash)
        internal
        view
        returns (bytes memory)
    {
        bytes32 batchHash = multisig.computeBatchHash("test", calls, prevHash);
        bytes32 structHash = _getDigest(batchHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, structHash);
        return abi.encodePacked(r, s, v);
    }

    function _signBatchHash(uint256 privateKey, bytes32 structHash) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, _getDigest(structHash));
        return abi.encodePacked(r, s, v);
    }

    /// @notice U:[CCM-1]: Initial state is correct
    function test_U_CCM_01_InitialState() public {
        assertEq(multisig.confirmationThreshold(), THRESHOLD);
        assertEq(multisig.lastBatchHash(), bytes32(0));
        assertEq(multisig.owner(), owner);

        // Verify all signers were added
        for (uint256 i = 0; i < signers.length; i++) {
            assertTrue(multisig.isSigner(signers[i]));
        }

        // Check events emitted during deployment
        vm.expectEmit(true, false, false, false);
        emit ICrossChainMultisig.AddSigner(signers[0]);

        vm.expectEmit(true, false, false, false);
        emit ICrossChainMultisig.AddSigner(signers[1]);

        vm.expectEmit(true, false, false, false);
        emit ICrossChainMultisig.AddSigner(signers[2]);

        vm.expectEmit(false, false, false, true);
        emit ICrossChainMultisig.SetConfirmationThreshold(THRESHOLD);

        // Re-deploy to verify events
        new CrossChainMultisigHarness(signers, THRESHOLD, owner);
    }

    /// @notice U:[CCM-2]: Access modifiers work correctly
    function test_U_CCM_02_AccessModifiers() public {
        // Test onlyOnMainnet modifier
        vm.chainId(5); // Set to non-mainnet chain
        vm.startPrank(owner);
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 1, target: address(0x123), callData: hex"1234"});
        vm.expectRevert(ICrossChainMultisig.CantBeExecutedOnCurrentChainException.selector);
        multisig.submitBatch("test", calls, bytes32(0));

        vm.expectRevert(ICrossChainMultisig.CantBeExecutedOnCurrentChainException.selector);
        multisig.signBatch(bytes32(0), new bytes(65));
        vm.stopPrank();

        // Test onlyOnNotMainnet modifier
        vm.chainId(1);
        vm.expectRevert(ICrossChainMultisig.CantBeExecutedOnCurrentChainException.selector);
        multisig.executeBatch(
            SignedBatch({name: "test", calls: calls, prevHash: bytes32(0), signatures: new bytes[](0)})
        );

        // Test onlySelf modifier
        vm.expectRevert(abi.encodeWithSelector(ICrossChainMultisig.CallerIsNotSelfException.selector, address(this)));
        multisig.addSigner(address(0x123));

        vm.expectRevert(abi.encodeWithSelector(ICrossChainMultisig.CallerIsNotSelfException.selector, address(this)));
        multisig.removeSigner(signers[0]);

        vm.expectRevert(abi.encodeWithSelector(ICrossChainMultisig.CallerIsNotSelfException.selector, address(this)));
        multisig.setConfirmationThreshold(3);

        vm.expectRevert(abi.encodeWithSelector(ICrossChainMultisig.CallerIsNotSelfException.selector, address(this)));
        multisig.disableRecoveryMode(0);

        // Test onlyOwner modifier
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        multisig.submitBatch("test", calls, bytes32(0));
    }

    /// @notice U:[CCM-3]: Submit batch works correctly
    function test_U_CCM_03_SubmitBatch() public {
        vm.chainId(1); // Set to mainnet

        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 1, target: address(0x123), callData: hex"1234"});

        bytes32 expectedBatchHash = multisig.computeBatchHash("test", calls, bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ICrossChainMultisig.SubmitBatch(expectedBatchHash);

        vm.prank(owner);
        multisig.submitBatch("test", calls, bytes32(0));

        SignedBatch memory batch = multisig.getBatch(expectedBatchHash);
        assertEq(batch.calls.length, 1);
        assertEq(batch.prevHash, bytes32(0));
        assertEq(batch.signatures.length, 0);

        // submit the same batch again doesn't change calls
        vm.prank(owner);
        multisig.submitBatch("test", calls, bytes32(0));

        batch = multisig.getBatch(expectedBatchHash);
        assertEq(batch.calls.length, 1);
        assertEq(batch.prevHash, bytes32(0));
        assertEq(batch.signatures.length, 0);
    }

    /// @notice U:[CCM-4]: Reverts when submitting batch with invalid prev hash
    function test_U_CCM_04_revert_on_invalid_prev_hash() public {
        vm.chainId(1);
        vm.startPrank(owner);

        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 1, target: address(0x123), callData: hex"1234"});

        vm.expectRevert(ICrossChainMultisig.InvalidPrevHashException.selector);
        multisig.submitBatch("test", calls, bytes32(uint256(1))); // Invalid prevHash
    }

    /// @notice U:[CCM-5]: Reverts when submitting empty batch
    function test_U_CCM_05_revert_on_empty_calls() public {
        vm.chainId(1);
        vm.startPrank(owner);

        CrossChainCall[] memory calls = new CrossChainCall[](0);

        vm.expectRevert(ICrossChainMultisig.InvalidBatchException.selector);
        multisig.submitBatch("test", calls, bytes32(0));
    }

    /// @notice U:[CCM-6]: Sign batch works correctly with single signature
    function test_U_CCM_06_SignBatch() public {
        vm.chainId(1); // Set to mainnet

        // Submit batch
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 1, target: address(0x123), callData: hex"1234"});

        vm.prank(owner);
        multisig.submitBatch("test", calls, bytes32(0));
        bytes32 batchHash = multisig.computeBatchHash("test", calls, bytes32(0));

        console.log(signers[0]);
        console.logBytes32(batchHash);

        bytes32 structHash =
            keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes("test")), batchHash, bytes32(0)));

        // Generate EIP-712 signature
        bytes memory signature = _signBatchHash(signer0PrivateKey, structHash);

        // Sign with first signer
        multisig.signBatch(batchHash, signature);

        // Verify batch state after signing
        SignedBatch memory batch = multisig.getBatch(batchHash);
        assertEq(batch.signatures.length, 1);
        assertEq(batch.signatures[0], signature);

        // Verify batch was not executed since threshold not met
        assertEq(multisig.lastBatchHash(), bytes32(0));
    }

    /// @notice U:[CCM-7]: Sign batch reverts when signing with invalid signature
    function test_U_CCM_07_SignBatchInvalidSignature() public {
        vm.chainId(1);

        // Submit batch
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 1, target: address(0x123), callData: hex"1234"});

        vm.prank(owner);
        multisig.submitBatch("test", calls, bytes32(0));
        bytes32 batchHash = multisig.computeBatchHash("test", calls, bytes32(0));

        // Try to sign with invalid signature
        bytes memory invalidSig = hex"1234";
        vm.expectRevert("ECDSA: invalid signature length");
        multisig.signBatch(batchHash, invalidSig);
    }

    /// @notice U:[CCM-8]: Sign batch reverts when signing non-existent batch
    function test_U_CCM_08_SignBatchNonExistentBatch() public {
        vm.chainId(1);

        // Set last batch hash to 1, to avoid ambiguity that default value of 0 is a valid batch hash
        multisig.setLastBatchHash(bytes32(uint256(1)));

        bytes32 nonExistentHash = keccak256("non-existent");
        bytes memory signature = _signBatchHash(signer0PrivateKey, nonExistentHash);

        vm.expectRevert(
            abi.encodeWithSelector(ICrossChainMultisig.BatchIsNotSubmittedException.selector, nonExistentHash)
        );
        multisig.signBatch(nonExistentHash, signature);
    }

    /// @notice U:[CCM-9]: Sign batch reverts when same signer signs twice
    function test_U_CCM_09_SignBatchDuplicateSigner() public {
        vm.chainId(1);

        // Submit batch
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 1, target: address(0x123), callData: hex"1234"});

        vm.prank(owner);
        multisig.submitBatch("test", calls, bytes32(0));
        bytes32 batchHash = multisig.computeBatchHash("test", calls, bytes32(0));

        bytes32 structHash =
            keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes("test")), batchHash, bytes32(0)));

        // Sign first time
        bytes memory signature = _signBatchHash(signer0PrivateKey, structHash);
        multisig.signBatch(batchHash, signature);

        // Try to sign again with same signer
        vm.expectRevert(abi.encodeWithSelector(ICrossChainMultisig.DuplicateSignatureException.selector, signers[0]));
        multisig.signBatch(batchHash, signature);
    }

    /// @notice U:[CCM-10]: Sign and execute proposal works correctly
    function test_U_CCM_10_SignAndExecuteProposal() public {
        vm.chainId(1); // Set to mainnet

        // Submit proposal
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({
            chainId: 0,
            target: address(multisig),
            callData: abi.encodeWithSelector(ICrossChainMultisig.setConfirmationThreshold.selector, 3)
        });

        vm.prank(owner);
        multisig.submitBatch("test", calls, bytes32(0));
        bytes32 batchHash = multisig.computeBatchHash("test", calls, bytes32(0));

        bytes32 structHash =
            keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes("test")), batchHash, bytes32(0)));

        // Sign with first signer
        bytes memory sig0 = _signBatchHash(signer0PrivateKey, structHash);
        multisig.signBatch(batchHash, sig0);

        // Sign with second signer which should trigger execution
        // Check events emitted during execution
        vm.expectEmit(true, true, true, true);
        emit ICrossChainMultisig.SignBatch(batchHash, vm.addr(signer1PrivateKey));

        vm.expectEmit(true, true, true, true);
        emit ICrossChainMultisig.ExecuteBatch(batchHash);
        bytes memory sig1 = _signBatchHash(signer1PrivateKey, structHash);
        multisig.signBatch(batchHash, sig1);

        // Verify batch was executed
        assertEq(multisig.lastBatchHash(), batchHash, "lastBatchHash");
        assertEq(multisig.getExecutedBatchHashes()[0], batchHash, "executedBatchHashes");
    }

    /// @notice U:[CCM-11]: Batch validation works correctly
    function test_U_CCM_11_BatchValidation() public {
        vm.chainId(5); // Set to non-mainnet chain

        // Test empty batch
        CrossChainCall[] memory emptyCalls = new CrossChainCall[](0);
        vm.expectRevert(ICrossChainMultisig.InvalidBatchException.selector);
        multisig.executeBatch(
            SignedBatch({name: "test", calls: emptyCalls, prevHash: bytes32(0), signatures: new bytes[](0)})
        );

        // Test invalid prev hash
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 5, target: makeAddr("target"), callData: hex"1234"});
        vm.expectRevert(ICrossChainMultisig.InvalidPrevHashException.selector);
        multisig.executeBatch(
            SignedBatch({name: "test", calls: calls, prevHash: bytes32(uint256(1)), signatures: new bytes[](0)})
        );

        // Test local self-call
        calls[0] = CrossChainCall({chainId: 5, target: address(multisig), callData: hex"1234"});
        vm.expectRevert(ICrossChainMultisig.InvalidBatchException.selector);
        multisig.executeBatch(
            SignedBatch({name: "test", calls: calls, prevHash: bytes32(0), signatures: new bytes[](0)})
        );

        // Test disableRecoveryMode not being the only call
        CrossChainCall[] memory mixedCalls = new CrossChainCall[](2);
        mixedCalls[0] = CrossChainCall({
            chainId: 0,
            target: address(multisig),
            callData: abi.encodeWithSelector(ICrossChainMultisig.disableRecoveryMode.selector, block.chainid)
        });
        mixedCalls[1] = CrossChainCall({chainId: 5, target: makeAddr("target"), callData: hex"1234"});
        vm.expectRevert(ICrossChainMultisig.InvalidBatchException.selector);
        multisig.executeBatch(
            SignedBatch({name: "test", calls: mixedCalls, prevHash: bytes32(0), signatures: new bytes[](0)})
        );
    }

    /// @notice U:[CCM-12]: _verifyBatch succeeds with valid calls
    function test_U_CCM_12_VerifyBatchValidCalls() public view {
        CrossChainCall[] memory calls = new CrossChainCall[](3);

        // Valid call on same chain
        calls[0] = CrossChainCall({chainId: 0, target: address(multisig), callData: hex"1234"});

        // Valid call to different contract on another chain
        calls[1] = CrossChainCall({chainId: 5, target: address(0x123), callData: hex"5678"});

        // Valid call to different contract on same chain
        calls[2] = CrossChainCall({chainId: 0, target: address(0x456), callData: hex"9abc"});

        // Should not revert
        multisig.exposed_verifyBatch(calls, bytes32(0));
    }

    /// @notice U:[CCM-13]: _verifySignatures returns 0 for empty signatures array
    function test_U_CCM_13_VerifySignaturesEmptyArray() public view {
        bytes[] memory signatures = new bytes[](0);
        bytes32 batchHash = keccak256("test");

        uint256 validCount = multisig.exposed_verifySignatures(signatures, batchHash);
        assertEq(validCount, 0);
    }

    /// @notice U:[CCM-14]: _verifySignatures correctly counts valid signatures
    function test_U_CCM_14_VerifySignaturesValidSignatures() public {
        vm.chainId(1); // Set to mainnet
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 1, target: address(0x123), callData: hex"1234"});

        vm.prank(owner);
        multisig.submitBatch("test", calls, bytes32(0));
        bytes32 batchHash = multisig.computeBatchHash("test", calls, bytes32(0));

        bytes32 structHash =
            keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes("test")), batchHash, bytes32(0)));

        // Create array with 2 valid signatures
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signBatchHash(signer0PrivateKey, structHash);
        signatures[1] = _signBatchHash(signer1PrivateKey, structHash);

        uint256 validCount = multisig.exposed_verifySignatures(signatures, _getDigest(structHash));
        assertEq(validCount, 2);
    }

    /// @notice U:[CCM-15]: _verifySignatures ignores invalid signatures
    function test_U_CCM_15_VerifySignaturesInvalidSignatures() public {
        vm.chainId(1); // Set to mainnet
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 1, target: address(0x123), callData: hex"1234"});

        vm.prank(owner);
        multisig.submitBatch("test", calls, bytes32(0));
        bytes32 batchHash = multisig.computeBatchHash("test", calls, bytes32(0));

        bytes32 structHash =
            keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes("test")), batchHash, bytes32(0)));

        // Create array with 1 valid and 1 invalid signature
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signBatchHash(signer0PrivateKey, structHash);

        // Create invalid signature by signing different hash
        signatures[1] = _signBatchHash(signer1PrivateKey, keccak256("wrong hash"));

        uint256 validCount = multisig.exposed_verifySignatures(signatures, _getDigest(structHash));
        assertEq(validCount, 1);
    }

    /// @notice U:[CCM-16]: _verifySignatures reverts with DuplicateSignatureException on duplicate signatures from same signer
    function test_U_CCM_16_VerifySignaturesDuplicateSigner() public {
        vm.chainId(1); // Set to mainnet
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 1, target: address(0x123), callData: hex"1234"});

        vm.prank(owner);
        multisig.submitBatch("test", calls, bytes32(0));
        bytes32 batchHash = multisig.computeBatchHash("test", calls, bytes32(0));

        bytes32 structHash =
            keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes("test")), batchHash, bytes32(0)));

        // Create array with 2 signatures from same signer
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signBatchHash(signer0PrivateKey, structHash);
        signatures[1] = _signBatchHash(signer0PrivateKey, structHash);

        bytes32 digest = _getDigest(structHash);

        vm.expectRevert(abi.encodeWithSelector(ICrossChainMultisig.DuplicateSignatureException.selector, signers[0]));
        multisig.exposed_verifySignatures(signatures, digest);
    }

    /// @notice U:[CCM-17]: _verifySignatures ignores signatures from non-signers
    function test_U_CCM_17_VerifySignaturesNonSigner() public {
        vm.chainId(1); // Set to mainnet
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 1, target: address(0x123), callData: hex"1234"});

        vm.prank(owner);
        multisig.submitBatch("test", calls, bytes32(0));
        bytes32 batchHash = multisig.computeBatchHash("test", calls, bytes32(0));

        bytes32 structHash =
            keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes("test")), batchHash, bytes32(0)));

        // Create random non-signer private key
        uint256 nonSignerKey = uint256(keccak256("non-signer"));

        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signBatchHash(signer0PrivateKey, structHash); // Valid signer
        signatures[1] = _signBatchHash(nonSignerKey, structHash); // Non-signer

        uint256 validCount = multisig.exposed_verifySignatures(signatures, _getDigest(structHash));
        assertEq(validCount, 1);
    }

    /// @notice U:[CCM-18]: _verifySignatures reverts on malformed signatures
    function test_U_CCM_18_VerifySignaturesMalformedSignature() public {
        bytes32 batchHash = keccak256("test");

        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signBatchHash(signer0PrivateKey, batchHash); // Valid signature
        signatures[1] = hex"1234"; // Malformed signature

        vm.expectRevert("ECDSA: invalid signature length");
        multisig.exposed_verifySignatures(signatures, batchHash);
    }

    /// @notice U:[CCM-19]: Cannot reduce signers below threshold
    function test_U_CCM_19_CannotReduceSignersBelowThreshold() public {
        vm.prank(address(multisig));
        multisig.removeSigner(signers[0]);

        vm.expectRevert(ICrossChainMultisig.InvalidConfirmationThresholdException.selector);
        vm.prank(address(multisig));
        multisig.removeSigner(signers[1]);
    }

    /// @notice U:[CCM-20]: Recovery mode can be enabled with valid signatures
    function test_U_CCM_20_EnableRecoveryMode() public {
        vm.chainId(5); // Set to non-mainnet chain

        address target = makeAddr("target");
        vm.etch(target, hex"ff"); // Put some code there to make call possible
        vm.mockCall(target, bytes(hex"1234"), "");

        // First execute a batch to have non-zero lastBatchHash
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 5, target: target, callData: hex"1234"});

        SignedBatch memory batch =
            SignedBatch({name: "test", calls: calls, prevHash: bytes32(0), signatures: new bytes[](2)});

        bytes32 batchHash = multisig.computeBatchHash("test", calls, bytes32(0));
        bytes32 structHash =
            keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes("test")), batchHash, bytes32(0)));

        batch.signatures[0] = _signBatchHash(signer0PrivateKey, structHash);
        batch.signatures[1] = _signBatchHash(signer1PrivateKey, structHash);

        multisig.executeBatch(batch);

        // Now enable recovery mode
        bytes32 recoveryHash = keccak256(abi.encode(RECOVERY_MODE_TYPEHASH, block.chainid, batchHash));

        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signBatchHash(signer0PrivateKey, recoveryHash);
        signatures[1] = _signBatchHash(signer1PrivateKey, recoveryHash);

        vm.expectEmit(true, false, false, false);
        emit ICrossChainMultisig.EnableRecoveryMode(batchHash);

        multisig.enableRecoveryMode(
            SignedRecoveryModeMessage({chainId: block.chainid, startingBatchHash: batchHash, signatures: signatures})
        );

        assertTrue(multisig.isRecoveryModeEnabled());
    }

    /// @notice U:[CCM-21]: Recovery mode skips non-self calls during execution
    function test_U_CCM_21_RecoveryModeSkipsExecution() public {
        vm.chainId(5); // Set to non-mainnet chain

        // Setup and enable recovery mode first
        bytes32 lastHash = _setupRecoveryMode();
        assertTrue(multisig.isRecoveryModeEnabled());

        address target = makeAddr("target");
        vm.mockCallRevert(target, bytes(hex"1234"), ""); // This call should be skipped

        // Create batch with both self and external calls
        CrossChainCall[] memory calls = new CrossChainCall[](2);
        calls[0] = CrossChainCall({
            chainId: 5,
            target: target,
            callData: hex"1234" // This should be skipped
        });
        calls[1] = CrossChainCall({
            chainId: 0,
            target: address(multisig),
            callData: abi.encodeWithSelector(ICrossChainMultisig.setConfirmationThreshold.selector, 3)
        });

        SignedBatch memory batch =
            SignedBatch({name: "test", calls: calls, prevHash: lastHash, signatures: new bytes[](2)});

        bytes32 batchHash = multisig.computeBatchHash("test", calls, lastHash);
        bytes32 structHash =
            keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes("test")), batchHash, lastHash));

        batch.signatures[0] = _signBatchHash(signer0PrivateKey, structHash);
        batch.signatures[1] = _signBatchHash(signer1PrivateKey, structHash);

        // Execute batch and verify only self-call was executed
        multisig.executeBatch(batch);
        assertEq(multisig.confirmationThreshold(), 3); // Self-call executed
    }

    /// @notice U:[CCM-22]: Recovery mode can be disabled through dedicated batch
    function test_U_CCM_22_DisableRecoveryMode() public {
        vm.chainId(5); // Set to non-mainnet chain

        // Setup and enable recovery mode first
        bytes32 lastHash = _setupRecoveryMode();
        assertTrue(multisig.isRecoveryModeEnabled());

        // Create batch with single disableRecoveryMode call
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({
            chainId: 0,
            target: address(multisig),
            callData: abi.encodeWithSelector(ICrossChainMultisig.disableRecoveryMode.selector, block.chainid)
        });

        SignedBatch memory batch =
            SignedBatch({name: "test", calls: calls, prevHash: lastHash, signatures: new bytes[](2)});

        bytes32 batchHash = multisig.computeBatchHash("test", calls, lastHash);
        bytes32 structHash =
            keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes("test")), batchHash, lastHash));

        batch.signatures[0] = _signBatchHash(signer0PrivateKey, structHash);
        batch.signatures[1] = _signBatchHash(signer1PrivateKey, structHash);

        vm.expectEmit(false, false, false, true);
        emit ICrossChainMultisig.DisableRecoveryMode();

        multisig.executeBatch(batch);
        assertFalse(multisig.isRecoveryModeEnabled());
    }

    /// @notice U:[CCM-23]: Recovery mode cannot be enabled on mainnet
    function test_U_CCM_23_EnableRecoveryModeOnMainnet() public {
        vm.chainId(1); // Set to mainnet

        bytes32 batchHash = bytes32(uint256(1));
        bytes32 recoveryHash = keccak256(abi.encode(RECOVERY_MODE_TYPEHASH, block.chainid, batchHash));

        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signBatchHash(signer0PrivateKey, recoveryHash);
        signatures[1] = _signBatchHash(signer1PrivateKey, recoveryHash);

        vm.expectRevert(ICrossChainMultisig.CantBeExecutedOnCurrentChainException.selector);
        multisig.enableRecoveryMode(
            SignedRecoveryModeMessage({chainId: block.chainid, startingBatchHash: batchHash, signatures: signatures})
        );
    }

    /// @notice U:[CCM-24]: Recovery mode message must match current chain
    function test_U_CCM_24_EnableRecoveryModeWrongChain() public {
        vm.chainId(5); // Set to non-mainnet chain

        bytes32 batchHash = bytes32(uint256(1));
        // Create recovery message for wrong chain
        bytes32 recoveryHash = keccak256(abi.encode(RECOVERY_MODE_TYPEHASH, uint256(137), batchHash));

        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signBatchHash(signer0PrivateKey, recoveryHash);
        signatures[1] = _signBatchHash(signer1PrivateKey, recoveryHash);

        // Should silently return without enabling recovery mode
        multisig.enableRecoveryMode(
            SignedRecoveryModeMessage({
                chainId: 137, // Different chain
                startingBatchHash: batchHash,
                signatures: signatures
            })
        );
        assertFalse(multisig.isRecoveryModeEnabled());
    }

    /// Helper function to setup recovery mode
    function _setupRecoveryMode() internal returns (bytes32) {
        address target = makeAddr("target");
        vm.etch(target, hex"ff"); // Put some code there to make call possible
        vm.mockCall(target, bytes(hex"1234"), "");

        // First execute a batch to have non-zero lastBatchHash
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({chainId: 5, target: target, callData: hex"1234"});

        SignedBatch memory batch =
            SignedBatch({name: "test", calls: calls, prevHash: bytes32(0), signatures: new bytes[](2)});

        bytes32 batchHash = multisig.computeBatchHash("test", calls, bytes32(0));
        bytes32 structHash =
            keccak256(abi.encode(COMPACT_BATCH_TYPEHASH, keccak256(bytes("test")), batchHash, bytes32(0)));

        batch.signatures[0] = _signBatchHash(signer0PrivateKey, structHash);
        batch.signatures[1] = _signBatchHash(signer1PrivateKey, structHash);

        multisig.executeBatch(batch);

        // Enable recovery mode
        bytes32 recoveryHash = keccak256(abi.encode(RECOVERY_MODE_TYPEHASH, block.chainid, batchHash));
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signBatchHash(signer0PrivateKey, recoveryHash);
        signatures[1] = _signBatchHash(signer1PrivateKey, recoveryHash);

        multisig.enableRecoveryMode(
            SignedRecoveryModeMessage({chainId: block.chainid, startingBatchHash: batchHash, signatures: signatures})
        );

        return batchHash;
    }
}
