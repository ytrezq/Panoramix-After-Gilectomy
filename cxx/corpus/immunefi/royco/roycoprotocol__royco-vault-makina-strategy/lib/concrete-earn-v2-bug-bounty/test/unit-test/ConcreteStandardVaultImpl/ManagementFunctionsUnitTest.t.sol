// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    IConcreteStandardVaultImpl,
    ConcreteStandardVaultImplBaseSetup
} from "../../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../../src/lib/Roles.sol";
import {IAccessControl} from "@openzeppelin-contracts/access/IAccessControl.sol";
import {IUpgradeableVault} from "../../../src/interface/IUpgradeableVault.sol";

import {ConcreteV2FeeParamsLib} from "../../../src/lib/Constants.sol";

contract ManagementFunctionsUnitTest is ConcreteStandardVaultImplBaseSetup {
    address public user1;
    address public user2;
    address public feeRecipient;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        feeRecipient = makeAddr("feeRecipient");

        // Fund user accounts
        asset.mint(user1, 1000000e18);
        asset.mint(user2, 1000000e18);

        // Setup initial state
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), 1000000e18);
        concreteStandardVault.deposit(1000000e18, user1);
        vm.stopPrank();
    }

    // ============================================================================
    // UPDATE MANAGEMENT FEE TESTS
    // ============================================================================

    function testUpdateManagementFee() public {
        vm.prank(factoryOwner);
        concreteStandardVault.updateManagementFeeRecipient(feeRecipient);

        vm.expectEmit(true, true, false, true);
        emit IConcreteStandardVaultImpl.ManagementFeeUpdated(500);
        vm.prank(vaultManager);
        concreteStandardVault.updateManagementFee(500); // 5%

        (address recipient, uint16 fee, uint32 lastAccrual) = concreteStandardVault.managementFee();
        assertEq(fee, 500);
        assertEq(recipient, feeRecipient);
        assertGt(lastAccrual, 0);
    }

    function testUpdateManagementFeeZero() public {
        vm.prank(vaultManager);
        concreteStandardVault.updateManagementFee(0);

        (, uint16 fee,) = concreteStandardVault.managementFee();
        assertEq(fee, 0);
    }

    function testUpdateManagementFeeExceedsMaximum() public {
        vm.prank(factoryOwner);
        concreteStandardVault.updateManagementFeeRecipient(feeRecipient);
        vm.expectRevert(IConcreteStandardVaultImpl.ManagementFeeExceedsMaximum.selector);
        vm.prank(vaultManager);
        concreteStandardVault.updateManagementFee(ConcreteV2FeeParamsLib.MAX_MANAGEMENT_FEE + 1);
    }

    function testUpdateManagementFeeNoRecipient() public {
        vm.prank(vaultManager);
        vm.expectRevert(IConcreteStandardVaultImpl.FeeRecipientNotSet.selector);
        concreteStandardVault.updateManagementFee(500);
    }

    function testUpdateManagementFeeUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, RolesLib.VAULT_MANAGER
            )
        );
        concreteStandardVault.updateManagementFee(500);
    }

    function testUpdateManagementFeeRecipient() public {
        vm.expectEmit(true, true, false, true);
        emit IConcreteStandardVaultImpl.ManagementFeeRecipientUpdated(feeRecipient);
        vm.prank(factoryOwner);
        concreteStandardVault.updateManagementFeeRecipient(feeRecipient);

        (address recipient,, uint32 lastAccrual) = concreteStandardVault.managementFee();
        assertEq(recipient, feeRecipient);
        assertGt(lastAccrual, 0);
    }

    function testUpdateManagementFeeRecipientZeroAddress() public {
        vm.prank(factoryOwner);
        vm.expectRevert(IConcreteStandardVaultImpl.InvalidFeeRecipient.selector);
        concreteStandardVault.updateManagementFeeRecipient(address(0));
    }

    function testUpdateManagementFeeRecipientUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(IUpgradeableVault.InvalidFactoryOwner.selector);
        concreteStandardVault.updateManagementFeeRecipient(feeRecipient);
    }

    function testUpdatePerformanceFee() public {
        vm.prank(factoryOwner);
        concreteStandardVault.updatePerformanceFeeRecipient(feeRecipient);

        vm.expectEmit(true, true, false, true);
        emit IConcreteStandardVaultImpl.PerformanceFeeUpdated(300);
        vm.prank(vaultManager);
        concreteStandardVault.updatePerformanceFee(300); // 3%

        (address recipient, uint16 fee) = concreteStandardVault.performanceFee();
        assertEq(fee, 300);
        assertEq(recipient, feeRecipient);
    }

    function testUpdatePerformanceFeeZero() public {
        vm.prank(vaultManager);
        concreteStandardVault.updatePerformanceFee(0);

        (, uint16 fee) = concreteStandardVault.performanceFee();
        assertEq(fee, 0);
    }

    function testUpdatePerformanceFeeExceedsMaximum() public {
        vm.prank(factoryOwner);
        concreteStandardVault.updatePerformanceFeeRecipient(feeRecipient);
        vm.expectRevert(IConcreteStandardVaultImpl.PerformanceFeeExceedsMaximum.selector);
        vm.prank(vaultManager);
        concreteStandardVault.updatePerformanceFee(ConcreteV2FeeParamsLib.MAX_PERFORMANCE_FEE + 1);
    }

    function testUpdatePerformanceFeeNoRecipient() public {
        vm.prank(vaultManager);
        vm.expectRevert(IConcreteStandardVaultImpl.FeeRecipientNotSet.selector);
        concreteStandardVault.updatePerformanceFee(300);
    }

    function testUpdatePerformanceFeeUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, RolesLib.VAULT_MANAGER
            )
        );
        concreteStandardVault.updatePerformanceFee(300);
    }

    function testUpdatePerformanceFeeRecipient() public {
        vm.expectEmit(true, true, false, true);
        emit IConcreteStandardVaultImpl.PerformanceFeeRecipientUpdated(feeRecipient);
        vm.prank(factoryOwner);
        concreteStandardVault.updatePerformanceFeeRecipient(feeRecipient);

        (address recipient,) = concreteStandardVault.performanceFee();
        assertEq(recipient, feeRecipient);
    }

    function testUpdatePerformanceFeeRecipientZeroAddress() public {
        vm.prank(factoryOwner);
        vm.expectRevert(IConcreteStandardVaultImpl.InvalidFeeRecipient.selector);
        concreteStandardVault.updatePerformanceFeeRecipient(address(0));
    }

    function testUpdatePerformanceFeeRecipientUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(IUpgradeableVault.InvalidFactoryOwner.selector);
        concreteStandardVault.updatePerformanceFeeRecipient(feeRecipient);
    }

    function testUpdateFeesTriggersYieldAccrual() public {
        // Set management fee and recipient
        vm.prank(factoryOwner);
        concreteStandardVault.updateManagementFeeRecipient(feeRecipient);
        vm.prank(vaultManager);
        concreteStandardVault.updateManagementFee(100);

        // Set performance fee and recipient
        vm.prank(factoryOwner);
        concreteStandardVault.updatePerformanceFeeRecipient(feeRecipient);
        vm.prank(vaultManager);
        concreteStandardVault.updatePerformanceFee(100);

        // Fast forward time
        vm.warp(block.timestamp + 1 days);

        // Update fees again - should trigger yield accrual
        vm.prank(vaultManager);
        concreteStandardVault.updateManagementFee(200);

        // Check that lastManagementFeeAccrual was updated
        (,, uint32 lastAccrual) = concreteStandardVault.managementFee();
        assertEq(lastAccrual, block.timestamp);
    }

    function testSetDepositLimits() public {
        vm.prank(vaultManager);
        concreteStandardVault.setDepositLimits(1000000e18, 1000000e18);

        (uint256 maxDepositAmount, uint256 minDepositAmount) = concreteStandardVault.getDepositLimits();
        assertEq(maxDepositAmount, 1000000e18);
        assertEq(minDepositAmount, 1000000e18);
    }

    function testSetDepositLimitsUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, RolesLib.VAULT_MANAGER
            )
        );
        concreteStandardVault.setDepositLimits(1000000e18, 1000000e18);
    }

    function testSetDepositLimitsInvalidLimits() public {
        vm.prank(vaultManager);
        vm.expectRevert(IConcreteStandardVaultImpl.InvalidDepositLimits.selector);
        concreteStandardVault.setDepositLimits(1000000e18, 1000000e17);
    }

    function testSetWithdrawLimits() public {
        vm.prank(vaultManager);
        concreteStandardVault.setWithdrawLimits(1000000e18, 1000000e18);

        (uint256 maxWithdrawAmount, uint256 minWithdrawAmount) = concreteStandardVault.getWithdrawLimits();
        assertEq(maxWithdrawAmount, 1000000e18);
        assertEq(minWithdrawAmount, 1000000e18);
    }

    function testSetWithdrawLimitsUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, RolesLib.VAULT_MANAGER
            )
        );
        concreteStandardVault.setWithdrawLimits(1000000e18, 1000000e18);
    }

    function testSetWithdrawLimitsInvalidLimits() public {
        vm.prank(vaultManager);
        vm.expectRevert(IConcreteStandardVaultImpl.InvalidWithdrawLimits.selector);
        concreteStandardVault.setWithdrawLimits(1000000e18, 1000000e17);
    }
}
