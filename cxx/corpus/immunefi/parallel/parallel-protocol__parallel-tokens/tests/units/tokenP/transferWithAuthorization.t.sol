// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Units.t.sol";

import {EIP3009} from "contracts/tokens/TokenP/EIP3009.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract TokenP_TransferWithAuthorization_Units_Test is Units_Test {
    bytes32 constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    uint256 constant TRANSFER_AMOUNT = 1_000e18;

    function setUp() public override {
        super.setUp();
        vm.prank(users.admin.addr);
        aEURp.mint(users.alice.addr, INITIAL_BALANCE);
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

    // --- transferWithAuthorization (v, r, s) ---

    function test_transferWithAuthorization() external {
        bytes32 nonce = bytes32(uint256(1));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        aEURp.transferWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);

        assertEq(aEURp.balanceOf(users.bob.addr), TRANSFER_AMOUNT);
        assertEq(aEURp.balanceOf(users.alice.addr), INITIAL_BALANCE - TRANSFER_AMOUNT);
        assertTrue(aEURp.authorizationState(users.alice.addr, nonce));
    }

    function test_transferWithAuthorization_emitsEvent() external {
        bytes32 nonce = bytes32(uint256(2));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        vm.expectEmit(true, true, false, false, address(aEURp));
        emit EIP3009.AuthorizationUsed(users.alice.addr, nonce);

        aEURp.transferWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);
    }

    function test_revertWhen_transferWithAuthorization_notYetValid() external {
        bytes32 nonce = bytes32(uint256(3));
        uint256 validAfter = block.timestamp + 1 hours;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        vm.expectRevert(EIP3009.AuthorizationNotYetValid.selector);
        aEURp.transferWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);
    }

    function test_revertWhen_transferWithAuthorization_expired() external {
        vm.warp(block.timestamp + 1 days);
        bytes32 nonce = bytes32(uint256(4));
        uint256 validAfter = block.timestamp - 2 hours;
        uint256 validBefore = block.timestamp - 1;

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        vm.expectRevert(EIP3009.AuthorizationExpired.selector);
        aEURp.transferWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);
    }

    function test_revertWhen_transferWithAuthorization_nonceAlreadyUsed() external {
        bytes32 nonce = bytes32(uint256(5));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        aEURp.transferWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(EIP3009.AuthorizationAlreadyUsed.selector, nonce));
        aEURp.transferWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);
    }

    function test_revertWhen_transferWithAuthorization_invalidSignature() external {
        bytes32 nonce = bytes32(uint256(6));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferAuthorization(users.hacker, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        vm.expectRevert(EIP3009.InvalidSignature.selector);
        aEURp.transferWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);
    }

    // --- transferWithAuthorization (bytes signature) ---

    function test_transferWithAuthorization_bytesSignature() external {
        bytes32 nonce = bytes32(uint256(7));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        bytes memory signature = abi.encodePacked(r, s, v);

        aEURp.transferWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, signature);

        assertEq(aEURp.balanceOf(users.bob.addr), TRANSFER_AMOUNT);
        assertEq(aEURp.balanceOf(users.alice.addr), INITIAL_BALANCE - TRANSFER_AMOUNT);
    }

    // --- Fuzz test ---

    function testFuzz_transferWithAuthorization(uint256 amount, bytes32 nonce) external {
        amount = bound(amount, 1, INITIAL_BALANCE);
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferAuthorization(users.alice, users.alice.addr, users.bob.addr, amount, validAfter, validBefore, nonce);

        aEURp.transferWithAuthorization(users.alice.addr, users.bob.addr, amount, validAfter, validBefore, nonce, v, r, s);

        assertEq(aEURp.balanceOf(users.bob.addr), amount);
        assertEq(aEURp.balanceOf(users.alice.addr), INITIAL_BALANCE - amount);
    }
}
