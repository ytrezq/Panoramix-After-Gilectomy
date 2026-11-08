// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    IConcreteStandardVaultImpl,
    ConcreteStandardVaultImplBaseSetup
} from "../../common/ConcreteStandardVaultImplBaseSetup.t.sol";

contract UserInteractionsUnitTest is ConcreteStandardVaultImplBaseSetup {
    address public user1;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");

        // fund user account
        asset.mint(user1, 2000000e18);

        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), 2000000e18);
        concreteStandardVault.deposit(1000000e18, user1);
        vm.stopPrank();
    }

    function testDepositInvalidReceiver() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IConcreteStandardVaultImpl.InvalidReceiver.selector));
        concreteStandardVault.deposit(1000000e18, address(0));
        vm.stopPrank();
    }

    function testDepositInvalidUpperLimitAmount() public {
        vm.prank(vaultManager);
        concreteStandardVault.setDepositLimits(0, 1000000e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user1, 1000000e19, 0, 1000000e18
            )
        );
        vm.startPrank(user1);
        concreteStandardVault.deposit(1000000e19, user1);
        vm.stopPrank();
    }

    function testDepositInvalidLowerLimitAmount() public {
        vm.prank(vaultManager);
        concreteStandardVault.setDepositLimits(1000000e18, 1000000e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user1, 1000000e17, 1000000e18, 1000000e18
            )
        );
        vm.startPrank(user1);
        concreteStandardVault.deposit(1000000e17, user1);
        vm.stopPrank();
    }

    function testMintInvalidReceiver() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IConcreteStandardVaultImpl.InvalidReceiver.selector));
        concreteStandardVault.mint(1000000e18, address(0));
        vm.stopPrank();
    }

    function testMintInvalidUpperLimitAmount() public {
        vm.prank(vaultManager);
        concreteStandardVault.setDepositLimits(0, 1000000e16);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user1, 1000000e17, 0, 1000000e16
            )
        );
        vm.startPrank(user1);
        concreteStandardVault.mint(1000000e17, user1);
        vm.stopPrank();
    }

    function testMintInvalidLowerLimitAmount() public {
        vm.prank(vaultManager);
        concreteStandardVault.setDepositLimits(1000000e18, 1000000e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user1, 1000000e17, 1000000e18, 1000000e18
            )
        );
        vm.startPrank(user1);
        concreteStandardVault.mint(1000000e17, user1);
        vm.stopPrank();
    }

    function testWithdrawInvalidReceiver() public {
        vm.startPrank(user1);

        vm.expectRevert(abi.encodeWithSelector(IConcreteStandardVaultImpl.InvalidReceiver.selector));
        concreteStandardVault.withdraw(1000000e18, address(0), user1);

        vm.stopPrank();
    }

    function testWithdrawInvalidUpperLimitAmount() public {
        // First deposit to have assets to withdraw
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), 1000000e18);
        concreteStandardVault.deposit(1000000e18, user1);

        // Verify the deposit worked
        uint256 userShares = concreteStandardVault.balanceOf(user1);
        uint256 userAssets = concreteStandardVault.previewRedeem(userShares);
        assertGt(userShares, 0, "User should have shares after deposit");
        assertGt(userAssets, 0, "User should have assets after deposit");
        vm.stopPrank();

        vm.prank(vaultManager);
        concreteStandardVault.setWithdrawLimits(0, 1000000e17);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user1, 1000000e18, 0, 1000000e17
            )
        );
        vm.startPrank(user1);
        concreteStandardVault.withdraw(1000000e18, user1, user1);
        vm.stopPrank();
    }

    function testWithdrawInvalidLowerLimitAmount() public {
        // First deposit to have assets to withdraw
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), 1000000e18);
        concreteStandardVault.deposit(1000000e18, user1);

        // Verify the deposit worked
        uint256 userShares = concreteStandardVault.balanceOf(user1);
        uint256 userAssets = concreteStandardVault.previewRedeem(userShares);
        assertGt(userShares, 0, "User should have shares after deposit");
        assertGt(userAssets, 0, "User should have assets after deposit");
        vm.stopPrank();

        vm.prank(vaultManager);
        concreteStandardVault.setWithdrawLimits(1000000e18, 1000000e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user1, 1000000e17, 1000000e18, 1000000e18
            )
        );
        vm.startPrank(user1);
        concreteStandardVault.withdraw(1000000e17, user1, user1);
        vm.stopPrank();
    }

    function testRedeemInvalidReceiver() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IConcreteStandardVaultImpl.InvalidReceiver.selector));
        concreteStandardVault.redeem(1000000e18, address(0), user1);
        vm.stopPrank();
    }

    function testRedeemInvalidUpperLimitAmount() public {
        // First deposit to have shares to redeem
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), 1000000e18);
        concreteStandardVault.deposit(1000000e18, user1);

        // Verify the deposit worked
        uint256 userShares = concreteStandardVault.balanceOf(user1);
        assertGt(userShares, 0, "User should have shares after deposit");
        vm.stopPrank();

        vm.prank(vaultManager);
        concreteStandardVault.setWithdrawLimits(0, 1000000e17);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user1, 1000000e18, 0, 1000000e17
            )
        );
        vm.startPrank(user1);
        concreteStandardVault.redeem(1000000e18, user1, user1);
        vm.stopPrank();
    }

    function testRedeemInvalidLowerLimitAmount() public {
        // First deposit to have shares to redeem
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), 1000000e18);
        concreteStandardVault.deposit(1000000e18, user1);

        // Verify the deposit worked
        uint256 userShares = concreteStandardVault.balanceOf(user1);
        assertGt(userShares, 0, "User should have shares after deposit");
        vm.stopPrank();

        vm.prank(vaultManager);
        concreteStandardVault.setWithdrawLimits(1000000e18, 1000000e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user1, 1000000e17, 1000000e18, 1000000e18
            )
        );
        vm.startPrank(user1);
        concreteStandardVault.redeem(1000000e17, user1, user1);
        vm.stopPrank();
    }

    function testDepositInsufficientShares() public {
        vm.prank(user1);
        concreteStandardVault.deposit(1e18, user1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IConcreteStandardVaultImpl.InsufficientShares.selector));
        concreteStandardVault.deposit(0, user1); // Zero amount should result in 0 shares
    }

    function testRedeemInsufficientAssets() public {
        vm.prank(user1);
        concreteStandardVault.deposit(1000000e18, user1);

        vm.expectRevert(abi.encodeWithSelector(IConcreteStandardVaultImpl.InsufficientAssets.selector));
        vm.prank(user1);
        concreteStandardVault.redeem(0, user1, user1); // Zero shares should result in 0 assets
    }
}
