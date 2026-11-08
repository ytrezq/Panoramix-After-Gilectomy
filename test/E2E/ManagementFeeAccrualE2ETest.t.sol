// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcreteStandardVaultImplBaseSetup} from "../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {ERC4626StrategyMock} from "../mock/ERC4626StrategyMock.sol";
import {console} from "forge-std/console.sol";
import {InvariantUtils} from "../invariant/helpers/InvariantUtils.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {AddStrategyWithDeallocationOrder} from "../common/AddStrategyWithDeallocationOrder.sol";

contract ManagementFeeAccrualTest is ConcreteStandardVaultImplBaseSetup, AddStrategyWithDeallocationOrder {
    address public user1;
    address public managementFeeRecipient;

    ERC4626StrategyMock public strategy;

    // Constants
    uint16 public constant MANAGEMENT_FEE_BPS = 500; // 5% in basis points
    uint16 public constant MANAGEMENT_FEE_BPS_E2E = 200; // 2% in basis points for E2E tests
    uint256 public constant LARGE_DEPOSIT = 1000000e18; // 1M tokens
    uint256 public constant INITIAL_DEPOSIT = 1000e18; // 1K tokens for E2E tests
    uint256 public constant ONE_YEAR = 365 days;
    uint256 public constant EPOCH_START = 1704067200;

    function setUp() public override {
        super.setUp();

        // Set a realistic block timestamp (January 1, 2024)
        vm.warp(EPOCH_START); // Unix timestamp for 2024-01-01 00:00:00 UTC

        user1 = makeAddr("user1");
        managementFeeRecipient = makeAddr("managementFeeRecipient");

        strategy = new ERC4626StrategyMock(address(asset));

        addStrategyWithDeallocationOrder(address(strategy), address(concreteStandardVault), allocator, strategyOperator);

        // Fund user account
        asset.mint(user1, LARGE_DEPOSIT * 2);

        // Set up management fee configuration
        setupManagementFee();
    }

    function setupManagementFee() internal {
        // Set management fee recipient first (requires owner)
        vm.prank(factoryOwner);
        concreteStandardVault.updateManagementFeeRecipient(managementFeeRecipient);

        // Then set management fee to 5% (requires MANAGER role)
        vm.prank(vaultManager);
        concreteStandardVault.updateManagementFee(MANAGEMENT_FEE_BPS);

        // Verify the fee is set correctly
        (
            address recipient,
            uint16 fee,
            /**
             * uint32 lastAccrual
             */
        ) = concreteStandardVault.managementFee();
        assertEq(fee, MANAGEMENT_FEE_BPS);
        assertEq(recipient, managementFeeRecipient);
    }

    function testAccrueManagementFee() public {
        // Set up for E2E test with 2% fee
        vm.prank(vaultManager);
        concreteStandardVault.updateManagementFee(MANAGEMENT_FEE_BPS_E2E);

        // Make initial deposit
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), INITIAL_DEPOSIT);
        concreteStandardVault.deposit(INITIAL_DEPOSIT, user1);
        vm.stopPrank();

        vm.warp(EPOCH_START + 2 days);

        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(managementFeeRecipient);
        uint256 totalSupplyBefore = concreteStandardVault.totalSupply();
        uint256 totalAssetsBefore = concreteStandardVault.cachedTotalAssets();

        // Calculate expected shares for 2 days
        (,, uint32 lastAccrual) = concreteStandardVault.managementFee();
        uint256 annualFeeAmount = (totalAssetsBefore * MANAGEMENT_FEE_BPS_E2E) / 10_000;
        uint256 expectedFeeAmount = (annualFeeAmount * (block.timestamp - lastAccrual)) / ONE_YEAR;
        uint256 expectedShares = InvariantUtils.convertToShares(
            expectedFeeAmount, totalSupplyBefore, totalAssetsBefore - expectedFeeAmount, Math.Rounding.Floor
        );

        // Trigger yield accrual which should accrue 2 days worth of management fees
        concreteStandardVault.accrueYield();

        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(managementFeeRecipient);
        uint256 totalSupplyAfter = concreteStandardVault.totalSupply();

        // Verify shares were minted to recipient for 2 days - should now be exact!
        assertEq(recipientBalanceAfter - recipientBalanceBefore, expectedShares);
        assertEq(totalSupplyAfter - totalSupplyBefore, expectedShares);

        // Verify timestamp was updated
        (,, lastAccrual) = concreteStandardVault.managementFee();
        assertEq(lastAccrual, block.timestamp);

        uint256 recipientBalanceBeforeDoubleTest = concreteStandardVault.balanceOf(managementFeeRecipient);
        concreteStandardVault.accrueYield();
        uint256 recipientBalanceAfterDoubleTest = concreteStandardVault.balanceOf(managementFeeRecipient);
        // No additional fees should be charged
        assertEq(recipientBalanceBeforeDoubleTest, recipientBalanceAfterDoubleTest);

        // advance final time to 1 YEAR
        vm.warp(EPOCH_START + (ONE_YEAR));

        recipientBalanceBefore = concreteStandardVault.balanceOf(managementFeeRecipient);
        totalSupplyBefore = concreteStandardVault.totalSupply();
        totalAssetsBefore = concreteStandardVault.cachedTotalAssets();

        // Calculate expected shares for 1 year
        (,, lastAccrual) = concreteStandardVault.managementFee();
        annualFeeAmount = (totalAssetsBefore * MANAGEMENT_FEE_BPS_E2E) / 10_000;
        expectedFeeAmount = (annualFeeAmount * (block.timestamp - lastAccrual)) / ONE_YEAR;
        expectedShares = InvariantUtils.convertToShares(
            expectedFeeAmount, totalSupplyBefore, totalAssetsBefore - expectedFeeAmount, Math.Rounding.Floor
        );

        concreteStandardVault.accrueYield();

        recipientBalanceAfter = concreteStandardVault.balanceOf(managementFeeRecipient);
        totalSupplyAfter = concreteStandardVault.totalSupply();

        assertEq(recipientBalanceAfter - recipientBalanceBefore, expectedShares);
        assertEq(totalSupplyAfter - totalSupplyBefore, expectedShares);
    }

    function testAccrueManagementFeeWhenNoTimeElapsed() public {
        // Make initial deposit
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), INITIAL_DEPOSIT);
        concreteStandardVault.deposit(INITIAL_DEPOSIT, user1);
        vm.stopPrank();

        concreteStandardVault.accrueYield();

        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(managementFeeRecipient);
        uint256 totalSupplyBefore = concreteStandardVault.totalSupply();

        concreteStandardVault.accrueYield();

        assertEq(concreteStandardVault.balanceOf(managementFeeRecipient), recipientBalanceBefore);
        assertEq(concreteStandardVault.totalSupply(), totalSupplyBefore);
    }

    function testAccrueManagementFeeDuringDeposit() public {
        uint256 depositAmount = 400e18;

        // Make initial deposit
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), INITIAL_DEPOSIT);
        concreteStandardVault.deposit(INITIAL_DEPOSIT, user1);
        vm.stopPrank();

        // Initial deposit already done - verify no management fee accrued yet
        assertEq(concreteStandardVault.balanceOf(managementFeeRecipient), 0);

        vm.warp(EPOCH_START + 1 days);

        // Preview deposit should not account for management fees yet
        uint256 previewedShares = concreteStandardVault.previewDeposit(depositAmount);

        // Record state before deposit
        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(managementFeeRecipient);
        uint256 totalSupplyBefore = concreteStandardVault.totalSupply();
        uint256 totalAssetsBefore = concreteStandardVault.cachedTotalAssets();

        (,, uint32 lastAccrual) = concreteStandardVault.managementFee();
        uint256 annualFeeAmount = (totalAssetsBefore * MANAGEMENT_FEE_BPS) / 10_000;
        uint256 expectedFeeAmount = (annualFeeAmount * (block.timestamp - lastAccrual)) / ONE_YEAR;
        uint256 expectedFeeShares = InvariantUtils.convertToShares(
            expectedFeeAmount, totalSupplyBefore, totalAssetsBefore - expectedFeeAmount, Math.Rounding.Floor
        );

        // Execute deposit (this should trigger management fee accrual)
        asset.mint(user1, depositAmount);
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), depositAmount);
        uint256 actualShares = concreteStandardVault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Verify management fee was accrued
        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(managementFeeRecipient);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, expectedFeeShares);

        // Verify previewDeposit() == deposit()
        assertEq(actualShares, previewedShares);

        // Verify total supply increased by both fee shares and user shares
        uint256 totalSupplyAfter = concreteStandardVault.totalSupply();
        assertEq(totalSupplyAfter - totalSupplyBefore, expectedFeeShares + actualShares);
    }

    function testAccrueManagementFeeWithZeroFee() public {
        // Set management fee to 0
        vm.prank(vaultManager);
        concreteStandardVault.updateManagementFee(0);

        // Verify fee is set to 0
        (address recipient, uint16 fee,) = concreteStandardVault.managementFee();
        assertEq(fee, 0, "Management fee should be set to 0");
        assertEq(recipient, managementFeeRecipient, "Recipient should remain the same");

        // Make initial deposit
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), INITIAL_DEPOSIT);
        concreteStandardVault.deposit(INITIAL_DEPOSIT, user1);
        vm.stopPrank();

        // Record initial state
        uint256 initialRecipientBalance = concreteStandardVault.balanceOf(managementFeeRecipient);
        // (,, /** uint32 initialLastAccrual*/) = concreteStandardVault.managementFee();

        // Advance time by 1 year
        vm.warp(EPOCH_START + ONE_YEAR);

        // Record state before yield accrual
        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(managementFeeRecipient);
        (,, uint32 lastAccrualBefore) = concreteStandardVault.managementFee();

        console.log("Time before accrual:", block.timestamp);
        console.log("Last accrual before:", lastAccrualBefore);
        console.log("Recipient balance before:", recipientBalanceBefore);

        // Force yield accrual (this should update timestamp even with 0 fee)
        concreteStandardVault.accrueYield();

        // Record state after yield accrual
        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(managementFeeRecipient);
        (,, uint32 lastAccrualAfter) = concreteStandardVault.managementFee();

        console.log("Last accrual after:", lastAccrualAfter);
        console.log("Recipient balance after:", recipientBalanceAfter);

        // Verify no fee shares were minted (since fee is 0)
        assertEq(recipientBalanceAfter, recipientBalanceBefore, "No fee shares should be minted when fee is 0");
        assertEq(recipientBalanceAfter, initialRecipientBalance, "Recipient balance should remain unchanged");

        // Verify the lastAccrual timestamp was updated
        assertEq(lastAccrualAfter, block.timestamp, "Last accrual timestamp should be updated even with 0 fee");
        assertGt(lastAccrualAfter, lastAccrualBefore, "Last accrual timestamp should be greater than before");

        // Verify that calling accrueYield again immediately doesn't change anything
        uint256 recipientBalanceBeforeSecond = concreteStandardVault.balanceOf(managementFeeRecipient);
        (,, uint32 lastAccrualBeforeSecond) = concreteStandardVault.managementFee();

        concreteStandardVault.accrueYield();

        uint256 recipientBalanceAfterSecond = concreteStandardVault.balanceOf(managementFeeRecipient);
        (,, uint32 lastAccrualAfterSecond) = concreteStandardVault.managementFee();

        // Verify no changes since no time elapsed
        assertEq(
            recipientBalanceAfterSecond,
            recipientBalanceBeforeSecond,
            "No fee shares should be minted when no time elapsed"
        );
        assertEq(lastAccrualAfterSecond, lastAccrualBeforeSecond, "Timestamp should not change when no time elapsed");

        console.log("Test passed - Last accrual timestamp updated correctly with 0 fee");
    }

    function testManagementFeeUpdateWithoutSync() public {
        // Start with 5% fee
        vm.prank(vaultManager);
        concreteStandardVault.updateManagementFee(500); // 5%

        // Verify fee is set to 5%
        (address recipient, uint16 fee,) = concreteStandardVault.managementFee();
        assertEq(fee, 500, "Initial management fee should be 5%");

        // Make initial deposit - should not charge any fee
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), INITIAL_DEPOSIT);
        concreteStandardVault.deposit(INITIAL_DEPOSIT, user1);
        vm.stopPrank();

        // Verify no fee was charged on initial deposit
        assertEq(
            concreteStandardVault.balanceOf(managementFeeRecipient),
            0,
            "No management fee should be charged on initial deposit"
        );

        // Record state before yield accrual
        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(managementFeeRecipient);
        (,, uint32 lastAccrual) = concreteStandardVault.managementFee();
        uint256 totalAssetsBefore = concreteStandardVault.cachedTotalAssets();
        uint256 totalSupplyBefore = concreteStandardVault.totalSupply();

        // Advance time by 30 days
        vm.warp(EPOCH_START + 30 days);

        // Update fee to 10% in protocol config
        vm.prank(vaultManager);
        concreteStandardVault.updateManagementFee(1000); // 10%

        // Verify the vault fee updated to 10%
        uint32 newLastAccrual;
        (recipient, fee, newLastAccrual) = concreteStandardVault.managementFee();
        assertEq(fee, 1000, "Vault fee updatet to 10%");

        // Verify fees were accrued for the first 30 days at 5%
        uint256 recipientBalanceAfterUpdate = concreteStandardVault.balanceOf(managementFeeRecipient);
        assertGt(recipientBalanceAfterUpdate, recipientBalanceBefore, "Fees should have been accrued during update");
        assertEq(newLastAccrual, EPOCH_START + 30 days, "Last accrual should be updated to current timestamp");

        // Advance time by another 30 days (total 60 days from start)
        //uint256 time2 = time1 + 30 days;
        vm.warp(EPOCH_START + 60 days);

        console.log("Time elapsed since last accrual:", block.timestamp - lastAccrual);
        console.log("Total assets before accrual:", totalAssetsBefore);
        console.log("Total supply before accrual:", totalSupplyBefore);

        // Force yield accrual
        concreteStandardVault.accrueYield();

        // Record state after yield accrual
        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(managementFeeRecipient);
        uint256 feeShares = recipientBalanceAfter - recipientBalanceBefore;
        uint256 feeAmount = concreteStandardVault.convertToAssets(feeShares);

        console.log("Fee shares minted:", feeShares);
        console.log("Fee amount in assets:", feeAmount);

        // Calculate expected fee for the full 60-day period:
        // - First 30 days at 5%
        // - Second 30 days at 10%
        uint256 firstPeriodDays = 30 days;
        uint256 secondPeriodDays = 30 days;

        // Fee for first 30 days at 5%
        uint256 annualFeeAmount5Percent = (totalAssetsBefore * 500) / 10000; // 5% of total assets
        uint256 expectedFeeFirstPeriod = (annualFeeAmount5Percent * firstPeriodDays) / ONE_YEAR;

        // Fee for second 30 days at 10%
        uint256 annualFeeAmount10Percent = (totalAssetsBefore * 1000) / 10000; // 10% of total assets
        uint256 expectedFeeSecondPeriod = (annualFeeAmount10Percent * secondPeriodDays) / ONE_YEAR;

        uint256 expectedTotalFee = expectedFeeFirstPeriod + expectedFeeSecondPeriod;

        console.log("Expected fee for first 30 days at 5%:", expectedFeeFirstPeriod);
        console.log("Expected fee for second 30 days at 10%:", expectedFeeSecondPeriod);
        console.log("Expected total fee:", expectedTotalFee);

        // Verify the fee charged is approximately correct for the total period
        assertApproxEqRel(
            feeAmount, expectedTotalFee, 0.01e18, "Total fee should be approximately correct for both periods"
        );

        // Verify that the fee is greater than what would be charged for just the first period
        assertGt(feeAmount, expectedFeeFirstPeriod, "Total fee should be greater than first period fee only");

        // Verify that the fee is greater than what would be charged for just the second period
        assertGt(feeAmount, expectedFeeSecondPeriod, "Total fee should be greater than second period fee only");

        console.log("Test passed - Total fee correctly reflects both periods (5% + 10%)");
    }

    function testManagementFeeAccrual_5Percent_LargeDeposit() public {
        console.log("Large deposit amount:", LARGE_DEPOSIT / 1e18);
        console.log("Management fee rate:", MANAGEMENT_FEE_BPS);

        (,, uint32 lastAccrual) = concreteStandardVault.managementFee();
        console.log("initial lastAccrual", lastAccrual);

        assertEq(lastAccrual, block.timestamp); // Should be deploy time initially

        // Record initial state
        uint256 initialTotalSupply = concreteStandardVault.totalSupply();
        uint256 initialRecipientBalance = concreteStandardVault.balanceOf(managementFeeRecipient);
        uint256 initialTotalAssets = concreteStandardVault.cachedTotalAssets();

        console.log("Initial total supply:", initialTotalSupply);
        console.log("Initial recipient balance:", initialRecipientBalance);
        console.log("Initial total assets:", initialTotalAssets);

        // Make large deposit
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), LARGE_DEPOSIT / 2);
        uint256 sharesReceived = concreteStandardVault.deposit(LARGE_DEPOSIT / 2, user1);
        vm.stopPrank();

        (,, lastAccrual) = concreteStandardVault.managementFee();
        console.log("lastAccrual after first deposit", lastAccrual);

        console.log("Shares received:", sharesReceived);
        console.log("Total supply after deposit:", concreteStandardVault.totalSupply());
        console.log("Total assets after deposit:", concreteStandardVault.cachedTotalAssets());

        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), LARGE_DEPOSIT / 2);
        sharesReceived = concreteStandardVault.deposit(LARGE_DEPOSIT / 2, user1);
        vm.stopPrank();

        console.log("Shares received:", sharesReceived);
        console.log("Total supply after deposit2:", concreteStandardVault.totalSupply());
        console.log("Total assets after deposit2:", concreteStandardVault.cachedTotalAssets());

        // Verify no management fee was charged on first deposit
        assertEq(
            concreteStandardVault.balanceOf(managementFeeRecipient),
            0,
            "No management fee should be charged on first deposit"
        );

        // Advance time by 1 year
        uint256 oneYearLater = EPOCH_START + ONE_YEAR;
        vm.warp(oneYearLater);

        console.log("Advanced time by 1 year to:", oneYearLater);

        // Record state before yield accrual
        uint256 totalSupplyBefore = concreteStandardVault.totalSupply();
        uint256 totalAssetsBefore = concreteStandardVault.cachedTotalAssets();
        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(managementFeeRecipient);

        console.log("Total supply before accrual:", totalSupplyBefore);
        console.log("Total assets before accrual:", totalAssetsBefore);
        console.log("Recipient balance before accrual:", recipientBalanceBefore);

        // Calculate expected management fee
        uint256 timeElapsed = ONE_YEAR;
        uint256 annualFeeAmount = (totalAssetsBefore * MANAGEMENT_FEE_BPS) / 10000; // 5% of total assets
        uint256 expectedFeeAmount = (annualFeeAmount * timeElapsed) / ONE_YEAR;

        // Calculate expected fee shares using the same formula as the contract
        uint256 expectedFeeShares = InvariantUtils.convertToShares(
            expectedFeeAmount, totalSupplyBefore, totalAssetsBefore - expectedFeeAmount, Math.Rounding.Floor
        );

        console.log("Time elapsed:", timeElapsed);
        console.log("Annual fee amount:", annualFeeAmount);
        console.log("Expected fee amount:", expectedFeeAmount);
        console.log("Expected fee shares:", expectedFeeShares);

        // Force yield accrual (this should trigger management fee accrual)
        concreteStandardVault.accrueYield();

        // Record state after yield accrual
        uint256 totalSupplyAfter = concreteStandardVault.totalSupply();
        uint256 totalAssetsAfter = concreteStandardVault.cachedTotalAssets();
        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(managementFeeRecipient);

        console.log("Total supply after accrual:", totalSupplyAfter);
        console.log("Total assets after accrual:", totalAssetsAfter);
        console.log("Recipient balance after accrual:", recipientBalanceAfter);
        console.log("previewRedeem fee shares", concreteStandardVault.previewRedeem(recipientBalanceAfter));

        // Calculate actual fee charged
        uint256 actualFeeShares = recipientBalanceAfter - initialRecipientBalance;
        uint256 actualFeeAmount = concreteStandardVault.convertToAssets(actualFeeShares);

        console.log("Fee shares minted:", actualFeeShares);
        console.log("Fee amount in assets:", actualFeeAmount);

        // Verify the fee was charged correctly
        assertGt(actualFeeShares, 0, "Management fee should have been charged");
        assertGt(actualFeeAmount, 0, "Management fee amount should be greater than 0");

        // Verify the actual fee matches the expected fee
        assertApproxEqRel(
            actualFeeAmount, expectedFeeAmount, 0.01e18, "Actual fee amount should match expected fee amount"
        );
        assertApproxEqRel(
            actualFeeShares, expectedFeeShares, 0.01e18, "Actual fee shares should match expected fee shares"
        );

        // Verify the fee is approximately 5% of the total assets
        uint256 expectedFeePercentage = (actualFeeAmount * 10000) / totalAssetsBefore;

        console.log("Fee as percentage of total assets:", expectedFeePercentage);

        // Allow for some rounding differences (within 1 basis point)
        assertApproxEqRel(expectedFeePercentage, 500, 0.01e18, "Fee should be approximately 5%");

        // Verify timestamp was updated
        (,, uint32 newLastAccrual) = concreteStandardVault.managementFee();
        assertEq(newLastAccrual, block.timestamp, "Last accrual timestamp should be updated");

        console.log("Test passed - 5% management fee correctly charged");
    }

    function testManagementFeeAccrual_NoTimeElapsed() public {
        // Make deposit
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), LARGE_DEPOSIT);
        concreteStandardVault.deposit(LARGE_DEPOSIT, user1);
        vm.stopPrank();

        // Record state before yield accrual
        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(managementFeeRecipient);

        // Force yield accrual immediately (no time elapsed)
        concreteStandardVault.accrueYield();

        // Record state after yield accrual
        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(managementFeeRecipient);

        // Verify no fee was charged when no time elapsed
        assertEq(
            recipientBalanceAfter, recipientBalanceBefore, "No management fee should be charged when no time elapsed"
        );
    }

    function testManagementFeeAccrual_OneDay() public {
        // Make deposit
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), LARGE_DEPOSIT);
        concreteStandardVault.deposit(LARGE_DEPOSIT, user1);
        vm.stopPrank();

        // Advance time by 1 day
        vm.warp(EPOCH_START + 1 days);

        // Record state before yield accrual
        uint256 totalAssetsBefore = concreteStandardVault.cachedTotalAssets();
        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(managementFeeRecipient);

        // Force yield accrual
        concreteStandardVault.accrueYield();

        // Record state after yield accrual
        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(managementFeeRecipient);
        uint256 feeShares = recipientBalanceAfter - recipientBalanceBefore;
        uint256 feeAmount = concreteStandardVault.convertToAssets(feeShares);

        // Calculate expected fee for 1 day
        uint256 expectedAnnualFee = (totalAssetsBefore * MANAGEMENT_FEE_BPS) / 10000;
        uint256 expectedDailyFee = (expectedAnnualFee * 1 days) / ONE_YEAR;

        console.log("Total assets:", totalAssetsBefore);
        console.log("Expected annual fee:", expectedAnnualFee);
        console.log("Expected daily fee:", expectedDailyFee);
        console.log("Actual fee charged:", feeAmount);
        console.log("Fee shares minted:", feeShares);

        // Verify the fee is approximately correct (allow for rounding)
        assertApproxEqRel(feeAmount, expectedDailyFee, 0.01e18, "Daily fee should be approximately correct");

        console.log("Daily management fee calculated correctly");
    }

    function testManagementFeeAccrual_MultipleAccruals() public {
        // Make deposit
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), LARGE_DEPOSIT);
        concreteStandardVault.deposit(LARGE_DEPOSIT, user1);
        vm.stopPrank();

        uint256 totalFeeShares = 0;
        // uint256 currentTotalAssets = LARGE_DEPOSIT;
        // uint256 currentTotalSupply = concreteStandardVault.totalSupply();

        uint256 currentTime = EPOCH_START;
        // Test multiple accruals over time
        for (uint256 i = 1; i <= 4; i++) {
            // Advance time by 3 months each time
            currentTime = currentTime + 91 days;
            vm.warp(currentTime);

            uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(managementFeeRecipient);

            // Force yield accrual
            concreteStandardVault.accrueYield();

            uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(managementFeeRecipient);
            uint256 feeShares = recipientBalanceAfter - recipientBalanceBefore;
            totalFeeShares += feeShares;

            console.log("Accrual", i, "fee shares:", feeShares);
        }

        console.log("Total fee shares over 1 year:", totalFeeShares);
        console.log("Total fee amount:", concreteStandardVault.convertToAssets(totalFeeShares));

        // Calculate the expected compounded fee percentage
        // For quarterly accruals, each subsequent accrual dilutes the value of previously minted shares
        // This results in a total fee percentage that is less than the simple annual rate
        uint256 expectedCompoundedFeeBps = calculateExpectedCompoundedFeeBps();

        // Verify total fee is approximately the compounded rate
        uint256 totalFeeAmount = concreteStandardVault.convertToAssets(totalFeeShares);
        uint256 feePercentage = (totalFeeAmount * 10000) / LARGE_DEPOSIT;

        console.log("Fee as percentage of deposit:", feePercentage, "basis points");
        console.log("Expected compounded fee percentage:", expectedCompoundedFeeBps, "basis points");
        assertApproxEqRel(
            feePercentage,
            expectedCompoundedFeeBps,
            0.01e18,
            "Total annual fee should be approximately the compounded rate"
        );
    }

    /**
     * @dev Calculate the expected compounded fee percentage for quarterly accruals over 1 year
     * @return The expected fee percentage in basis points
     */
    function calculateExpectedCompoundedFeeBps() internal pure returns (uint256) {
        uint256 annualFeeBps = MANAGEMENT_FEE_BPS; // 500 basis points (5%)
        uint256 quarterlyFeeBps = annualFeeBps / 4; // 125 basis points (1.25%) per quarter

        // Simulate the compounding effect by calculating each quarter's fee
        // and tracking the total fee shares and their asset value
        uint256 totalAssets = LARGE_DEPOSIT;
        uint256 totalShares = LARGE_DEPOSIT; // Initial shares equal to initial assets
        uint256 totalFeeShares = 0;

        for (uint256 i = 0; i < 4; i++) {
            // Calculate fee amount for this quarter
            uint256 quarterlyFeeAmount = (totalAssets * quarterlyFeeBps) / 10000;

            // Calculate fee shares using the same formula as the contract
            uint256 feeShares =
                Math.mulDiv(quarterlyFeeAmount, totalShares, totalAssets - quarterlyFeeAmount, Math.Rounding.Floor);

            // Update totals for next iteration
            totalFeeShares += feeShares;
            totalShares += feeShares;
            //totalAssets += quarterlyFeeAmount; // Assets increase by fee amount
        }

        // Calculate the final fee percentage
        uint256 totalFeeAmount = Math.mulDiv(totalFeeShares, totalAssets, totalShares, Math.Rounding.Floor);

        return (totalFeeAmount * 10000) / LARGE_DEPOSIT;
    }
}
