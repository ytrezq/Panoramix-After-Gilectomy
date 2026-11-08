// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcretePredepositVaultImplBaseSetup} from "../../common/ConcretePredepositVaultImplBaseSetup.t.sol";
import {IConcretePredepositVaultImpl} from "../../../src/interface/IConcretePredepositVaultImpl.sol";
import {IConcreteStandardVaultImpl} from "../../../src/interface/IConcreteStandardVaultImpl.sol";
import {IAccessControl} from "@openzeppelin-contracts/access/IAccessControl.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../../src/lib/Roles.sol";

contract WithdrawalLockUnitTest is ConcretePredepositVaultImplBaseSetup {
    address public user1;
    address public user2;

    event WithdrawLimitsUpdated(uint256 maxWithdrawAmount, uint256 minWithdrawAmount);

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Fund user accounts
        asset.mint(user1, 10000e18);
        asset.mint(user2, 10000e18);

        // Approve vault (using predepositVault as the main test vault)
        vm.prank(user1);
        asset.approve(address(predepositVault), 10000e18);

        vm.prank(user2);
        asset.approve(address(predepositVault), 10000e18);

        // User1 deposits
        vm.prank(user1);
        predepositVault.deposit(5000e18, user1);

        // User2 deposits
        vm.prank(user2);
        predepositVault.deposit(3000e18, user2);
    }

    function testInitialWithdrawLimits() public view {
        (uint256 maxWithdraw, uint256 minWithdraw) = predepositVault.getWithdrawLimits();
        assertEq(maxWithdraw, type(uint256).max, "Initial max withdraw should be unlimited");
        assertEq(minWithdraw, 0, "Initial min withdraw should be 0");
    }

    function testSetWithdrawLimitsToLock() public {
        // Set max withdraw to 0 to effectively "lock" withdrawals
        // Event signature is (maxWithdrawAmount, minWithdrawAmount)
        vm.expectEmit(true, true, true, true);
        emit WithdrawLimitsUpdated(0, 0);
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, 0);

        (uint256 maxWithdraw, uint256 minWithdraw) = predepositVault.getWithdrawLimits();
        assertEq(maxWithdraw, 0, "Max withdraw should be 0");
        assertEq(minWithdraw, 0, "Min withdraw should be 0");

        // Unlock by setting limits back to normal
        vm.expectEmit(true, true, true, true);
        emit WithdrawLimitsUpdated(type(uint256).max, 0);
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, type(uint256).max);

        (maxWithdraw, minWithdraw) = predepositVault.getWithdrawLimits();
        assertEq(maxWithdraw, type(uint256).max, "Max withdraw should be unlimited");
        assertEq(minWithdraw, 0, "Min withdraw should be 0");
    }

    function testSetWithdrawLimitsOnlyVaultManager() public {
        // Try with non-vault manager (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, RolesLib.VAULT_MANAGER
            )
        );
        vm.prank(user1);
        predepositVault.setWithdrawLimits(0, 0);

        // Try with vault manager (should succeed)
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, 0);

        (uint256 maxWithdraw,) = predepositVault.getWithdrawLimits();
        assertEq(maxWithdraw, 0, "Max withdraw should be 0");
    }

    function testWithdrawWhenLocked() public {
        // Lock withdrawals by setting max withdraw to 0
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, 0);

        // Try to withdraw (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user1, 1000e18, 0, 0)
        );
        vm.prank(user1);
        predepositVault.withdraw(1000e18, user1, user1);
    }

    function testWithdrawWhenUnlocked() public {
        // Withdrawals are unlocked by default
        uint256 balanceBefore = asset.balanceOf(user1);
        uint256 sharesBefore = predepositVault.balanceOf(user1);

        // Withdraw should succeed
        vm.prank(user1);
        uint256 sharesRedeemed = predepositVault.withdraw(1000e18, user1, user1);

        uint256 balanceAfter = asset.balanceOf(user1);
        uint256 sharesAfter = predepositVault.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, 1000e18, "User should receive 1000 assets");
        assertEq(sharesBefore - sharesAfter, sharesRedeemed, "Shares should be burned");
    }

    function testRedeemWhenLocked() public {
        uint256 sharesToRedeem = predepositVault.balanceOf(user1) / 2;
        uint256 expectedAssets = predepositVault.previewRedeem(sharesToRedeem);

        // Lock withdrawals by setting max withdraw to 0
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, 0);

        // Try to redeem (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(
                IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user1, expectedAssets, 0, 0
            )
        );
        vm.prank(user1);
        predepositVault.redeem(sharesToRedeem, user1, user1);
    }

    function testRedeemWhenUnlocked() public {
        uint256 sharesToRedeem = predepositVault.balanceOf(user1) / 2;
        uint256 balanceBefore = asset.balanceOf(user1);
        uint256 sharesBefore = predepositVault.balanceOf(user1);

        // Redeem should succeed
        vm.prank(user1);
        uint256 assetsReceived = predepositVault.redeem(sharesToRedeem, user1, user1);

        uint256 balanceAfter = asset.balanceOf(user1);
        uint256 sharesAfter = predepositVault.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, assetsReceived, "User should receive correct assets");
        assertEq(sharesBefore - sharesAfter, sharesToRedeem, "Correct shares should be burned");
    }

    function testMaxWithdrawWhenUnlocked() public view {
        // Before locking, user should have withdrawable assets
        uint256 maxWithdrawUnlocked = predepositVault.maxWithdraw(user1);
        assertGt(maxWithdrawUnlocked, 0, "User should have withdrawable assets when unlocked");
    }

    function testMaxWithdrawCalculation() public view {
        // maxWithdraw is based on available balance, not limits
        // Limits are enforced during actual withdraw
        uint256 maxWithdraw = predepositVault.maxWithdraw(user1);
        assertGt(maxWithdraw, 0, "User should have calculable max withdraw");
    }

    function testMaxRedeemWhenUnlocked() public view {
        // Before locking, user should have redeemable shares
        uint256 maxRedeemUnlocked = predepositVault.maxRedeem(user1);
        assertGt(maxRedeemUnlocked, 0, "User should have redeemable shares when unlocked");
    }

    function testMaxRedeemCalculation() public view {
        // maxRedeem is based on available shares, not limits
        // Limits are enforced during actual redeem
        uint256 maxRedeem = predepositVault.maxRedeem(user1);
        assertGt(maxRedeem, 0, "User should have calculable max redeem");
    }

    function testDepositStillWorksWhenWithdrawalsDisabled() public {
        // Disable withdrawals by setting max withdraw to 0
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, 0);

        // Deposits should still work
        uint256 sharesBefore = predepositVault.balanceOf(user1);
        uint256 depositAmount = 1000e18;

        vm.prank(user1);
        uint256 sharesReceived = predepositVault.deposit(depositAmount, user1);

        uint256 sharesAfter = predepositVault.balanceOf(user1);

        assertEq(sharesAfter - sharesBefore, sharesReceived, "User should receive shares");
        assertGt(sharesReceived, 0, "Should receive non-zero shares");
    }

    function testMintStillWorksWhenWithdrawalsDisabled() public {
        // Disable withdrawals by setting max withdraw to 0
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, 0);

        // Mints should still work
        uint256 sharesBefore = predepositVault.balanceOf(user1);
        uint256 sharesToMint = 1000e18;

        vm.prank(user1);
        uint256 assetsRequired = predepositVault.mint(sharesToMint, user1);

        uint256 sharesAfter = predepositVault.balanceOf(user1);

        assertEq(sharesAfter - sharesBefore, sharesToMint, "User should receive correct shares");
        assertGt(assetsRequired, 0, "Should require non-zero assets");
    }

    function testWithdrawAfterRestoringLimits() public {
        // Disable withdrawals
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, 0);

        // Restore normal limits
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, type(uint256).max);

        // Now withdraw should work
        uint256 balanceBefore = asset.balanceOf(user1);

        vm.prank(user1);
        predepositVault.withdraw(1000e18, user1, user1);

        uint256 balanceAfter = asset.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, 1000e18, "User should receive assets after restoring limits");
    }

    function testRedeemAfterRestoringLimits() public {
        uint256 sharesToRedeem = predepositVault.balanceOf(user1) / 2;

        // Disable withdrawals
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, 0);

        // Restore normal limits
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, type(uint256).max);

        // Now redeem should work
        uint256 balanceBefore = asset.balanceOf(user1);

        vm.prank(user1);
        uint256 assetsReceived = predepositVault.redeem(sharesToRedeem, user1, user1);

        uint256 balanceAfter = asset.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, assetsReceived, "User should receive assets after restoring limits");
        assertGt(assetsReceived, 0, "Should receive non-zero assets");
    }

    function testMultipleUsersCannotWithdrawWhenLocked() public {
        // Disable withdrawals
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, 0);

        // User1 cannot withdraw
        vm.expectRevert(
            abi.encodeWithSelector(IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user1, 100e18, 0, 0)
        );
        vm.prank(user1);
        predepositVault.withdraw(100e18, user1, user1);

        // User2 cannot withdraw
        vm.expectRevert(
            abi.encodeWithSelector(IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector, user2, 100e18, 0, 0)
        );
        vm.prank(user2);
        predepositVault.withdraw(100e18, user2, user2);
    }

    function testPreviewWithdrawStillWorksWhenLocked() public {
        uint256 previewUnlocked = predepositVault.previewWithdraw(1000e18);

        // Disable withdrawals
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, 0);

        // Preview should still work (it's a view function)
        uint256 previewLocked = predepositVault.previewWithdraw(1000e18);

        // Preview results should be the same (limits don't affect the preview)
        assertEq(previewLocked, previewUnlocked, "Preview should still work when locked");
    }

    function testPreviewRedeemStillWorksWhenLocked() public {
        uint256 sharesToPreview = 1000e18;
        uint256 previewUnlocked = predepositVault.previewRedeem(sharesToPreview);

        // Disable withdrawals
        vm.prank(vaultManager);
        predepositVault.setWithdrawLimits(0, 0);

        // Preview should still work (it's a view function)
        uint256 previewLocked = predepositVault.previewRedeem(sharesToPreview);

        // Preview results should be the same
        assertEq(previewLocked, previewUnlocked, "Preview should still work when locked");
    }
}
