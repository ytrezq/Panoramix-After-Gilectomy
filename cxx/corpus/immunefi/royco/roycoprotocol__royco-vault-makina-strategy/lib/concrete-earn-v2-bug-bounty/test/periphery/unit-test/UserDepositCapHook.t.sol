// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Hooks} from "../../../src/interface/IHook.sol";
import {UserDepositCapHook} from "../../../src/periphery/hooks/UserDepositCapHook.sol";
import {ConcreteStandardVaultImplBaseSetup} from "../../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {HooksLibV1} from "../../../src/lib/Hooks.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

contract UserDepositCapHookTest is ConcreteStandardVaultImplBaseSetup {
    UserDepositCapHook public hook;

    address alice;
    address bob;
    address charlie;
    address hookOwner;

    uint256 constant VAULT_CAP = 1000 ether;

    function setUp() public override {
        ConcreteStandardVaultImplBaseSetup.setUp();

        // Setup test accounts
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        hookOwner = makeAddr("hookOwner");

        // Deploy the hook
        hook = new UserDepositCapHook(hookOwner);

        // Configure the vault's deposit cap
        vm.prank(hookOwner);
        hook.setVaultDepositCap(address(concreteStandardVault), VAULT_CAP);

        // Mint assets to test users
        asset.mint(alice, 10000 ether);
        asset.mint(bob, 10000 ether);
        asset.mint(charlie, 10000 ether);

        // Setup hooks on vault
        uint96 flags = uint96(1 << HooksLibV1.PRE_DEPOSIT) | uint96(1 << HooksLibV1.PRE_MINT);
        Hooks memory hooks = Hooks({target: address(hook), flags: flags});

        vm.prank(hookManager);
        concreteStandardVault.setHooks(hooks);
    }

    function set_flag(uint8 flag) public pure returns (uint96) {
        return uint96(1 << flag);
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Constructor Tests
    // ═════════════════════════════════════════════════════════════════════════════

    function test_constructor_noDefaultCap() public {
        UserDepositCapHook newHook = new UserDepositCapHook(hookOwner);
        assertEq(newHook.getUserDepositCap(address(concreteStandardVault)), 0);
    }

    function test_constructor_revertsInvalidOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new UserDepositCapHook(address(0));
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Set Vault Deposit Cap Tests
    // ═════════════════════════════════════════════════════════════════════════════

    function test_setVaultDepositCap() public {
        address newVault = makeAddr("newVault");
        uint256 newCap = 5000 ether;

        vm.expectEmit(true, true, true, true);
        emit UserDepositCapHook.VaultDepositCapSet(newVault, 0, newCap);

        vm.prank(hookOwner);
        hook.setVaultDepositCap(newVault, newCap);

        assertEq(hook.getUserDepositCap(newVault), newCap);
    }

    function test_setVaultDepositCap_updateExisting() public {
        uint256 newCap = 2000 ether;

        vm.expectEmit(true, true, true, true);
        emit UserDepositCapHook.VaultDepositCapSet(address(concreteStandardVault), VAULT_CAP, newCap);

        vm.prank(hookOwner);
        hook.setVaultDepositCap(address(concreteStandardVault), newCap);

        assertEq(hook.getUserDepositCap(address(concreteStandardVault)), newCap);
    }

    function test_setVaultDepositCap_reverts() public {
        //test non-owner reverts
        vm.prank(alice);
        vm.expectRevert();
        hook.setVaultDepositCap(address(concreteStandardVault), 2000 ether);

        //test zero address reverts
        vm.prank(hookOwner);
        vm.expectRevert(abi.encodeWithSelector(UserDepositCapHook.ZeroAddress.selector));
        hook.setVaultDepositCap(address(0), 1000 ether);
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Deposit Tests - Vault Cap
    // ═════════════════════════════════════════════════════════════════════════════

    function test_deposit_withinVaultCap() public {
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), VAULT_CAP);

        //test deposit within cap succeeds
        concreteStandardVault.deposit(VAULT_CAP, alice);

        assertEq(concreteStandardVault.balanceOf(alice), VAULT_CAP);
        vm.stopPrank();
    }

    function test_deposit_exceedsVaultCap() public {
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), VAULT_CAP + 1);

        // Should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                UserDepositCapHook.UserDepositLimitExceeded.selector, alice, VAULT_CAP + 1, VAULT_CAP
            )
        );
        concreteStandardVault.deposit(VAULT_CAP + 1, alice);
        vm.stopPrank();
    }

    function test_deposit_multipleDepositsWithinCap() public {
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), VAULT_CAP);

        // First deposit
        concreteStandardVault.deposit(500 ether, alice);
        assertEq(concreteStandardVault.balanceOf(alice), 500 ether);

        // Second deposit - should succeed
        concreteStandardVault.deposit(500 ether, alice);
        assertEq(concreteStandardVault.balanceOf(alice), VAULT_CAP);
        vm.stopPrank();
    }

    function test_deposit_multipleDepositsExceedCap() public {
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), VAULT_CAP + 1);

        // First deposit
        concreteStandardVault.deposit(500 ether, alice);

        // Second deposit - should revert
        vm.expectRevert(
            abi.encodeWithSelector(UserDepositCapHook.UserDepositLimitExceeded.selector, alice, 1001 ether, VAULT_CAP)
        );
        concreteStandardVault.deposit(501 ether, alice);
        vm.stopPrank();
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Mint Tests
    // ═════════════════════════════════════════════════════════════════════════════

    function test_mint_withinVaultCap() public {
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), VAULT_CAP);

        // Should succeed
        concreteStandardVault.mint(VAULT_CAP, alice);

        assertEq(concreteStandardVault.balanceOf(alice), VAULT_CAP);
        vm.stopPrank();
    }

    function test_mint_exceedsVaultCap() public {
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), VAULT_CAP + 1);

        // first mint should succeed
        concreteStandardVault.mint(500 ether, alice);

        // second mint should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                UserDepositCapHook.UserDepositLimitExceeded.selector, alice, VAULT_CAP + 500 ether, VAULT_CAP
            )
        );
        concreteStandardVault.mint(VAULT_CAP, alice);
        vm.stopPrank();
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // View Function Tests
    // ═════════════════════════════════════════════════════════════════════════════

    function test_canUserDeposit() public {
        // Alice has no deposits yet
        bool canDeposit = hook.canUserDeposit(address(concreteStandardVault), alice, 500 ether);

        assertTrue(canDeposit);

        // Make a deposit
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), 500 ether);
        concreteStandardVault.deposit(500 ether, alice);
        vm.stopPrank();

        // Check if alice can deposit another 500
        canDeposit = hook.canUserDeposit(address(concreteStandardVault), alice, 500 ether);

        assertTrue(canDeposit);

        // expect revert
        vm.expectRevert();
        hook.canUserDeposit(address(concreteStandardVault), alice, 501 ether);
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Multiple Users Tests
    // ═════════════════════════════════════════════════════════════════════════════

    function test_multipleUsers_sameCapForAll() public {
        // Both users should be able to deposit up to vault cap independently
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), VAULT_CAP);
        concreteStandardVault.deposit(VAULT_CAP, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        asset.approve(address(concreteStandardVault), VAULT_CAP);
        concreteStandardVault.deposit(VAULT_CAP, bob);
        vm.stopPrank();

        assertEq(concreteStandardVault.balanceOf(alice), VAULT_CAP);
        assertEq(concreteStandardVault.balanceOf(bob), VAULT_CAP);
    }

    function test_multipleUsers_cannotExceedCap() public {
        // Alice deposits up to cap
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), VAULT_CAP);
        concreteStandardVault.deposit(VAULT_CAP, alice);
        vm.stopPrank();

        // Bob deposits up to cap
        vm.startPrank(bob);
        asset.approve(address(concreteStandardVault), VAULT_CAP);
        concreteStandardVault.deposit(VAULT_CAP, bob);
        vm.stopPrank();

        // Alice tries to deposit more - should fail
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                UserDepositCapHook.UserDepositLimitExceeded.selector, alice, VAULT_CAP + 1, VAULT_CAP
            )
        );
        concreteStandardVault.deposit(1, alice);
        vm.stopPrank();
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Withdrawal Tests
    // ═════════════════════════════════════════════════════════════════════════════

    function test_withdraw_allowedRegardlessOfCap() public {
        // Alice deposits up to cap
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), VAULT_CAP);
        concreteStandardVault.deposit(VAULT_CAP, alice);

        // Alice withdraws some funds
        concreteStandardVault.withdraw(500 ether, alice, alice);

        assertEq(concreteStandardVault.balanceOf(alice), 500 ether);
        vm.stopPrank();
    }

    function test_depositAfterWithdraw_respectsCap() public {
        // Alice deposits up to cap
        vm.startPrank(alice);
        asset.approve(address(concreteStandardVault), VAULT_CAP);
        concreteStandardVault.deposit(VAULT_CAP, alice);

        // Alice withdraws 500
        concreteStandardVault.withdraw(500 ether, alice, alice);

        // Alice can now deposit 500 more (back to cap)
        asset.approve(address(concreteStandardVault), 500 ether);
        concreteStandardVault.deposit(500 ether, alice);

        assertEq(concreteStandardVault.balanceOf(alice), VAULT_CAP);
        vm.stopPrank();
    }
}
