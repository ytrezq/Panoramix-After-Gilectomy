// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Units.t.sol";

import {EIP3009} from "contracts/tokens/TokenP/EIP3009.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract TokenP_ReceiveWithAuthorization_Units_Test is Units_Test {
    bytes32 constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

    uint256 constant TRANSFER_AMOUNT = 1_000e18;

    function setUp() public override {
        super.setUp();
        vm.prank(users.admin.addr);
        aEURp.mint(users.alice.addr, INITIAL_BALANCE);
    }

    function _signReceiveAuthorization(
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
            abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
        (v, r, s) = vm.sign(signer.privateKey, digest);
    }

    // --- receiveWithAuthorization (v, r, s) ---

    function test_receiveWithAuthorization() external {
        bytes32 nonce = bytes32(uint256(1));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        vm.prank(users.bob.addr);
        aEURp.receiveWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);

        assertEq(aEURp.balanceOf(users.bob.addr), TRANSFER_AMOUNT);
        assertEq(aEURp.balanceOf(users.alice.addr), INITIAL_BALANCE - TRANSFER_AMOUNT);
        assertTrue(aEURp.authorizationState(users.alice.addr, nonce));
    }

    function test_receiveWithAuthorization_emitsEvent() external {
        bytes32 nonce = bytes32(uint256(2));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        vm.expectEmit(true, true, false, false, address(aEURp));
        emit EIP3009.AuthorizationUsed(users.alice.addr, nonce);

        vm.prank(users.bob.addr);
        aEURp.receiveWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);
    }

    function test_revertWhen_receiveWithAuthorization_callerIsNotPayee() external {
        bytes32 nonce = bytes32(uint256(3));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        vm.prank(users.hacker.addr);
        vm.expectRevert(EIP3009.CallerMustBePayee.selector);
        aEURp.receiveWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);
    }

    function test_revertWhen_receiveWithAuthorization_notYetValid() external {
        bytes32 nonce = bytes32(uint256(4));
        uint256 validAfter = block.timestamp + 1 hours;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        vm.prank(users.bob.addr);
        vm.expectRevert(EIP3009.AuthorizationNotYetValid.selector);
        aEURp.receiveWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);
    }

    function test_revertWhen_receiveWithAuthorization_expired() external {
        vm.warp(block.timestamp + 1 days);
        bytes32 nonce = bytes32(uint256(5));
        uint256 validAfter = block.timestamp - 2 hours;
        uint256 validBefore = block.timestamp - 1;

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        vm.prank(users.bob.addr);
        vm.expectRevert(EIP3009.AuthorizationExpired.selector);
        aEURp.receiveWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);
    }

    function test_revertWhen_receiveWithAuthorization_nonceAlreadyUsed() external {
        bytes32 nonce = bytes32(uint256(6));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        vm.prank(users.bob.addr);
        aEURp.receiveWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);

        vm.prank(users.bob.addr);
        vm.expectRevert(abi.encodeWithSelector(EIP3009.AuthorizationAlreadyUsed.selector, nonce));
        aEURp.receiveWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);
    }

    function test_revertWhen_receiveWithAuthorization_invalidSignature() external {
        bytes32 nonce = bytes32(uint256(7));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveAuthorization(users.hacker, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        vm.prank(users.bob.addr);
        vm.expectRevert(EIP3009.InvalidSignature.selector);
        aEURp.receiveWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s);
    }

    // --- receiveWithAuthorization (bytes signature) ---

    function test_receiveWithAuthorization_bytesSignature() external {
        bytes32 nonce = bytes32(uint256(8));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveAuthorization(users.alice, users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(users.bob.addr);
        aEURp.receiveWithAuthorization(users.alice.addr, users.bob.addr, TRANSFER_AMOUNT, validAfter, validBefore, nonce, signature);

        assertEq(aEURp.balanceOf(users.bob.addr), TRANSFER_AMOUNT);
        assertEq(aEURp.balanceOf(users.alice.addr), INITIAL_BALANCE - TRANSFER_AMOUNT);
    }
}
