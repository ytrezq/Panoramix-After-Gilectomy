// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Hooks} from "../../../src/interface/IHook.sol";
import {StandardHookV1Mock} from "../../mock/StandardHookV1.sol";
import {ConcreteStandardVaultImplBaseSetup} from "../../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {HooksLibV1} from "../../../src/lib/Hooks.sol";

contract HooksUnitTest is ConcreteStandardVaultImplBaseSetup {
    address alice;
    address bob;
    uint256 depositLimit;
    StandardHookV1Mock mockHook;

    function setUp() public override {
        ConcreteStandardVaultImplBaseSetup.setUp();
        depositLimit = 1 ether;
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        mockHook = new StandardHookV1Mock(depositLimit);
        // mint some funds to alice
        asset.mint(alice, 10 ether);
    }

    function set_flag(uint8 flag) public pure returns (uint96) {
        return uint96(1 << flag);
    }

    // test pre-deposit hook
    function test_preDeposit_withHooks() public {
        uint96 flags = set_flag(HooksLibV1.PRE_DEPOSIT);
        Hooks memory hooks = Hooks({target: address(mockHook), flags: flags});
        // imposter the vault manager
        vm.prank(hookManager);
        concreteStandardVault.setHooks(hooks);
        // deposit some assets to alice
        vm.startPrank(alice);
        // approve the vault to spend the assets
        asset.approve(address(concreteStandardVault), 1 ether);
        // deposit some assets to alice
        concreteStandardVault.deposit(1 ether, alice);
        vm.stopPrank();
        // expect the hook to be called
        assertEq(mockHook.depositLimit(), depositLimit);
        assertEq(concreteStandardVault.balanceOf(alice), 1 ether);
    }

    function test_preDeposit_withHooks_fail() public {
        uint96 flags = set_flag(HooksLibV1.PRE_DEPOSIT);
        Hooks memory hooks = Hooks({target: address(mockHook), flags: flags});
        // imposter the vault manager
        vm.prank(hookManager);
        concreteStandardVault.setHooks(hooks);
        vm.startPrank(alice);
        // approve the vault to spend the assets
        asset.approve(address(concreteStandardVault), 10 ether);
        // deposit some assets to alice
        // expect revert DepositLimitExceeded
        vm.expectRevert(
            abi.encodeWithSelector(StandardHookV1Mock.DepositLimitExceeded.selector, 10 ether, depositLimit)
        );
        concreteStandardVault.deposit(10 ether, alice);
        vm.stopPrank();
    }

    function test_postMint_withHooks() public {
        uint96 flags = set_flag(HooksLibV1.POST_MINT);
        Hooks memory hooks = Hooks({target: address(mockHook), flags: flags});
        // imposter the vault manager
        vm.prank(hookManager);
        concreteStandardVault.setHooks(hooks);
        // mint some assets to alice
        vm.startPrank(alice);
        // approve the vault to spend the assets
        asset.approve(address(concreteStandardVault), 1 ether);
        // deposit some assets to alice
        concreteStandardVault.mint(1 ether, alice);
        vm.stopPrank();
    }

    function test_postMint_withHooks_fail() public {
        uint96 flags = set_flag(HooksLibV1.POST_MINT);
        Hooks memory hooks = Hooks({target: address(mockHook), flags: flags});
        // imposter the vault manager
        vm.prank(hookManager);
        concreteStandardVault.setHooks(hooks);
        vm.startPrank(alice);
        // approve the vault to spend the assets
        asset.approve(address(concreteStandardVault), 10 ether);
        // deposit some assets to alice
        // expect revert DepositLimitExceeded
        vm.expectRevert(
            abi.encodeWithSelector(StandardHookV1Mock.DepositLimitExceeded.selector, 10 ether, depositLimit)
        );
        concreteStandardVault.mint(10 ether, alice);
        vm.stopPrank();
    }

    function test_preWithdraw_withHooks() public {
        uint96 flags = set_flag(HooksLibV1.PRE_WITHDRAW);
        Hooks memory hooks = Hooks({target: address(mockHook), flags: flags});
        // imposter the vault manager
        vm.prank(hookManager);
        concreteStandardVault.setHooks(hooks);
        vm.startPrank(alice);
        // approve the vault to spend the assets
        asset.approve(address(concreteStandardVault), 1 ether);
        // deposit some assets to alice
        concreteStandardVault.deposit(1 ether, alice);
        // withdraw some assets from alice
        concreteStandardVault.withdraw(1 ether, alice, alice);
        vm.stopPrank();
        // expect the hook to be called
    }

    function test_preWithdraw_withHooks_fail() public {
        uint96 flags = set_flag(HooksLibV1.PRE_WITHDRAW);
        Hooks memory hooks = Hooks({target: address(mockHook), flags: flags});
        // imposter the vault manager
        vm.prank(hookManager);
        concreteStandardVault.setHooks(hooks);
        vm.startPrank(alice);
        // approve the vault to spend the assets
        asset.approve(address(concreteStandardVault), 1 ether);
        // deposit some assets to alice
        concreteStandardVault.deposit(1 ether, alice);
        // approve bob to spend the assets
        concreteStandardVault.approve(bob, 1 ether);
        // withdraw some assets from alice
        // expect revert NotOwner
        vm.stopPrank();

        vm.startPrank(bob);
        // withdraw some assets from alice
        // expect revert NotOwner
        vm.expectRevert(abi.encodeWithSelector(StandardHookV1Mock.NotOwner.selector));
        concreteStandardVault.withdraw(1 ether, alice, alice);
        vm.stopPrank();
    }

    function test_preRedeem_withHooks() public {
        uint96 flags = set_flag(HooksLibV1.PRE_REDEEM);
        Hooks memory hooks = Hooks({target: address(mockHook), flags: flags});
        // imposter the vault manager
        vm.prank(hookManager);
        concreteStandardVault.setHooks(hooks);
        vm.startPrank(alice);
        // approve the vault to spend the assets
        asset.approve(address(concreteStandardVault), 1 ether);
        // deposit some assets to alice
        concreteStandardVault.deposit(1 ether, alice);
        // redeem some assets from alice
        concreteStandardVault.redeem(1 ether, alice, alice);
        vm.stopPrank();
        // expect the hook to be called
    }

    function test_preRedeem_withHooks_fail() public {
        uint96 flags = set_flag(HooksLibV1.PRE_REDEEM);
        Hooks memory hooks = Hooks({target: address(mockHook), flags: flags});
        // imposter the vault manager
        vm.prank(hookManager);
        concreteStandardVault.setHooks(hooks);
        vm.startPrank(alice);
        // approve the vault to spend the assets
        asset.approve(address(concreteStandardVault), 1 ether);
        // deposit some assets to alice
        concreteStandardVault.deposit(1 ether, alice);
        // approve bob to spend the assets
        concreteStandardVault.approve(bob, 1 ether);
        // redeem some assets from alice
        // expect revert NotOwner
        vm.stopPrank();

        vm.startPrank(bob);
        // redeem some assets from alice
        // expect revert NotOwner
        vm.expectRevert(abi.encodeWithSelector(StandardHookV1Mock.NotOwner.selector));
        concreteStandardVault.redeem(1 ether, alice, alice);
        vm.stopPrank();
    }
}
