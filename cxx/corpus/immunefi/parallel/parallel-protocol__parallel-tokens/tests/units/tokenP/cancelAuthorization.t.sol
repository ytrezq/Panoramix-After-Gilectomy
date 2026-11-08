// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Units.t.sol";

import {EIP3009} from "contracts/tokens/TokenP/EIP3009.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract TokenP_CancelAuthorization_Units_Test is Units_Test {
    bytes32 constant CANCEL_AUTHORIZATION_TYPEHASH =
        0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;

    bytes32 constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    uint256 constant TRANSFER_AMOUNT = 1_000e18;

    function setUp() public override {
        super.setUp();
        vm.prank(users.admin.addr);
        aEURp.mint(users.alice.addr, INITIAL_BALANCE);
    }

    function _signCancelAuthorization(
        Vm.Wallet memory signer,
        address authorizer,
        bytes32 nonce
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = aEURp.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce)
        );
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
        (v, r, s) = vm.sign(signer.privateKey, digest);
    }

    function _signTransferAuthorization(
        Vm.Wallet memory signer,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = aEURp.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
        (v, r, s) = vm.sign(signer.privateKey, digest);
    }

    // --- cancelAuthorization (v, r, s) ---

    function test_cancelAuthorization() external {
        bytes32 nonce = bytes32(uint256(1));

        (uint8 v, bytes32 r, bytes32 s) = _signCancelAuthorization(users.alice, users.alice.addr, nonce);

        assertFalse(aEURp.authorizationState(users.alice.addr, nonce));

        aEURp.cancelAuthorization(users.alice.addr, nonce, v, r, s);

        assertTrue(aEURp.authorizationState(users.alice.addr, nonce));
    }

    function test_cancelAuthorization_emitsEvent() external {
        bytes32 nonce = bytes32(uint256(2));

        (uint8 v, bytes32 r, bytes32 s) = _signCancelAuthorization(users.alice, users.alice.addr, nonce);

        vm.expectEmit(true, true, false, false, address(aEURp));
        emit EIP3009.AuthorizationCanceled(users.alice.addr, nonce);

        aEURp.cancelAuthorization(users.alice.addr, nonce, v, r, s);
    }

    function test_cancelAuthorization_preventsTransfer() external {
        bytes32 nonce = bytes32(uint256(3));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 tv, bytes32 tr, bytes32 ts) =
            _signTransferAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        (uint8 cv, bytes32 cr, bytes32 cs) = _signCancelAuthorization(users.alice, users.alice.addr, nonce);
        aEURp.cancelAuthorization(users.alice.addr, nonce, cv, cr, cs);

        vm.expectRevert(abi.encodeWithSelector(EIP3009.AuthorizationAlreadyUsed.selector, nonce));
        aEURp.transferWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, tv, tr, ts);
    }

    function test_revertWhen_cancelAuthorization_nonceAlreadyUsed() external {
        bytes32 nonce = bytes32(uint256(4));

        (uint8 v, bytes32 r, bytes32 s) = _signCancelAuthorization(users.alice, users.alice.addr, nonce);

        aEURp.cancelAuthorization(users.alice.addr, nonce, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(EIP3009.AuthorizationAlreadyUsed.selector, nonce));
        aEURp.cancelAuthorization(users.alice.addr, nonce, v, r, s);
    }

    function test_revertWhen_cancelAuthorization_invalidSignature() external {
        bytes32 nonce = bytes32(uint256(5));

        (uint8 v, bytes32 r, bytes32 s) = _signCancelAuthorization(users.hacker, users.alice.addr, nonce);

        vm.expectRevert(EIP3009.InvalidSignature.selector);
        aEURp.cancelAuthorization(users.alice.addr, nonce, v, r, s);
    }

    // --- cancelAuthorization (bytes signature) ---

    function test_cancelAuthorization_bytesSignature() external {
        bytes32 nonce = bytes32(uint256(6));

        (uint8 v, bytes32 r, bytes32 s) = _signCancelAuthorization(users.alice, users.alice.addr, nonce);
        bytes memory signature = abi.encodePacked(r, s, v);

        aEURp.cancelAuthorization(users.alice.addr, nonce, signature);

        assertTrue(aEURp.authorizationState(users.alice.addr, nonce));
    }
}
