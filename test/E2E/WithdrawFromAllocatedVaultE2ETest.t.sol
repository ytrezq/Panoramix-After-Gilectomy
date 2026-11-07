// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ConcreteStandardVaultImplBaseSetup} from "../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {IAllocateModule} from "../../src/interface/IAllocateModule.sol";
import {ERC4626StrategyMock} from "../mock/ERC4626StrategyMock.sol";
import {IConcreteStandardVaultImpl} from "../../src/interface/IConcreteStandardVaultImpl.sol";
import {AddStrategyWithDeallocationOrder} from "../common/AddStrategyWithDeallocationOrder.sol";

contract WithdrawFromAllocatedVaultE2ETest is ConcreteStandardVaultImplBaseSetup, AddStrategyWithDeallocationOrder {
    address public user1;
    address public user2;
    address public user3;

    ERC4626StrategyMock public strategy1;
    ERC4626StrategyMock public strategy2;
    ERC4626StrategyMock public strategy3;

    uint256 public constant INITIAL_DEPOSIT = 1000e18;
    uint256 public constant STRATEGY_ALLOCATION = 300e18;

    function setUp() public override {
        ConcreteStandardVaultImplBaseSetup.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy strategies
        strategy1 = new ERC4626StrategyMock(address(asset));
        strategy2 = new ERC4626StrategyMock(address(asset));
        strategy3 = new ERC4626StrategyMock(address(asset));

        vm.label(address(strategy1), "strategy1");
        vm.label(address(strategy2), "strategy2");
        vm.label(address(strategy3), "strategy3");
        vm.label(user1, "user1");
        vm.label(user2, "user2");
        vm.label(user3, "user3");

        // Add strategies to vault
        addStrategyWithDeallocationOrder(
            address(strategy1), address(concreteStandardVault), allocator, strategyOperator
        );
        addStrategyWithDeallocationOrder(
            address(strategy2), address(concreteStandardVault), allocator, strategyOperator
        );
        addStrategyWithDeallocationOrder(
            address(strategy3), address(concreteStandardVault), allocator, strategyOperator
        );

        // Give users some tokens
        asset.mint(user1, INITIAL_DEPOSIT * 2);
        asset.mint(user2, INITIAL_DEPOSIT * 2);
        asset.mint(user3, INITIAL_DEPOSIT * 2);

        // Give strategies some tokens for yield simulation
        asset.mint(address(this), INITIAL_DEPOSIT * 10);
    }

    function testWithdrawFromIdleFundsOnly() public {
        // Setup: Users deposit, some funds allocated, some remain idle
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);

        // Allocate only part of the funds
        _allocateToStrategy(address(strategy1), STRATEGY_ALLOCATION);

        uint256 idleFunds = asset.balanceOf(address(concreteStandardVault));
        assertEq(idleFunds, INITIAL_DEPOSIT * 2 - STRATEGY_ALLOCATION);

        // User1 tries to withdraw amount covered by idle funds
        uint256 withdrawAmount = idleFunds / 2; // Should be covered by idle funds

        // Capture balance before withdrawal
        uint256 user1BalanceBefore = asset.balanceOf(user1);

        // Preview the shares that will be burned
        uint256 expectedSharesBurned = concreteStandardVault.previewWithdraw(withdrawAmount);

        vm.prank(user1);
        uint256 sharesBurned = concreteStandardVault.withdraw(withdrawAmount, user1, user1);

        // withdraw() returns shares burned, should match preview
        assertEq(sharesBurned, expectedSharesBurned);

        uint256 user1BalanceAfter = asset.balanceOf(user1);
        // User should have received exactly the withdrawn amount
        assertEq(user1BalanceAfter, user1BalanceBefore + withdrawAmount);

        // Vault should still have idle funds remaining
        uint256 remainingIdle = asset.balanceOf(address(concreteStandardVault));
        assertEq(remainingIdle, idleFunds - withdrawAmount);
    }

    // write a test that first deposits user 1, then allocates to strategy 1 and 2 50/50. then the strategy 1 makes some profit, then user 1 withdraws with the
    // deallocation order 1 and 2 (which is the default order) my suspicion is that it will revert.
    function testWithdrawWithProfitInStrategyAndWithdraw() public {
        // Setup: Deposit and allocate
        _depositAsUser(user1, 2 * INITIAL_DEPOSIT);

        _allocateToStrategy(address(strategy1), INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy2), INITIAL_DEPOSIT);

        // Simulate yield: 10% yield on first strategy
        uint256 yieldAmount1 = INITIAL_DEPOSIT * 10 / 100;

        asset.approve(address(strategy1), yieldAmount1);
        strategy1.simulateYield(yieldAmount1);
    }

    function testWithdrawRequiringStrategyDeallocation() public {
        // Setup: Users deposit and allocate most funds
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);

        uint256 totalDeposited = INITIAL_DEPOSIT * 2;
        uint256 largeAllocation = totalDeposited - 100e18; // Leave only 100 tokens idle

        _allocateToStrategy(address(strategy1), largeAllocation);

        // User1 tries to withdraw more than idle funds
        uint256 withdrawAmount = 500e18; // Requires strategy deallocation

        uint256 user1BalanceBefore = asset.balanceOf(user1);

        // Preview the shares that will be burned
        uint256 expectedSharesBurned = concreteStandardVault.previewWithdraw(withdrawAmount);

        vm.prank(user1);
        uint256 sharesBurned = concreteStandardVault.withdraw(withdrawAmount, user1, user1);

        // withdraw() returns shares burned, should match preview
        assertEq(sharesBurned, expectedSharesBurned);
        uint256 user1BalanceAfter = asset.balanceOf(user1);
        assertEq(user1BalanceAfter, user1BalanceBefore + withdrawAmount);

        // Strategy should have been deallocated from
        uint256 expectedRemainingAllocation = largeAllocation - (withdrawAmount - 100e18);
        assertEq(strategy1.totalAllocatedValue(), expectedRemainingAllocation);
    }

    function testWithdrawFromMultipleStrategies() public {
        // Setup: Allocate to multiple strategies
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);
        _depositAsUser(user3, INITIAL_DEPOSIT);

        uint256 totalDeposited = INITIAL_DEPOSIT * 3;

        // Allocate MOST funds, leaving very little idle
        uint256 largeAllocation = totalDeposited - 50e18; // Leave only 50e18 idle
        _allocateToStrategy(address(strategy1), largeAllocation);

        // Withdraw amount that requires strategy deallocation
        uint256 withdrawAmount = 200e18; // More than 50e18 idle, so requires deallocation

        uint256 initialAllocation = strategy1.totalAllocatedValue();

        // Preview the shares that will be burned
        uint256 expectedSharesBurned = concreteStandardVault.previewWithdraw(withdrawAmount);

        vm.prank(user1);
        uint256 sharesBurned = concreteStandardVault.withdraw(withdrawAmount, user1, user1);

        // withdraw() returns shares burned, should match preview
        assertEq(sharesBurned, expectedSharesBurned);

        // Verify deallocation happened - strategy should have less than initial
        uint256 finalAllocation = strategy1.totalAllocatedValue();
        assertLt(finalAllocation, initialAllocation);
    }

    function testWithdrawWithYieldInStrategies() public {
        uint256 deposit1 = 1000e18;
        uint256 deposit2 = 1000e18;

        _depositAsUser(user1, deposit1);
        _depositAsUser(user2, deposit2);

        uint256 allocation1 = 400e18; // Allocate 400 to strategy1
        uint256 allocation2 = 400e18; // Allocate 400 to strategy2

        _allocateToStrategy(address(strategy1), allocation1);
        _allocateToStrategy(address(strategy2), allocation2);

        // Simulate yield: 10% yield on each strategy (40e18 each)
        uint256 yieldAmount1 = 40e18; // 10% of 400e18
        uint256 yieldAmount2 = 40e18; // 10% of 400e18

        asset.approve(address(strategy1), yieldAmount1);
        strategy1.simulateYield(yieldAmount1);

        asset.approve(address(strategy2), yieldAmount2);
        strategy2.simulateYield(yieldAmount2);

        // Verify strategy values after yield
        assertGt(strategy1.totalAllocatedValue(), allocation1);
        assertGt(strategy2.totalAllocatedValue(), allocation2);
        yieldAmount1 =
            strategy1.totalAllocatedValue() - concreteStandardVault.getStrategyData(address(strategy1)).allocated;
        yieldAmount2 =
            strategy2.totalAllocatedValue() - concreteStandardVault.getStrategyData(address(strategy2)).allocated;

        // Check what user1 can withdraw
        uint256 maxRedeemableShares = concreteStandardVault.maxRedeem(user1);
        uint256 expectedWithdrawable = concreteStandardVault.previewRedeem(maxRedeemableShares);

        // Withdraw user1's available position
        vm.prank(user1);
        uint256 actualWithdrawn = concreteStandardVault.redeem(maxRedeemableShares, user1, user1);

        // The user should get exactly what preview says
        assertEq(actualWithdrawn, expectedWithdrawable);

        // Calculate expected withdrawal with yield (allowing for small rounding)
        // Total deposits: 2000e18, Total yield: 80e18 (40e18 + 40e18)
        // User1's share: 1000e18 / 2000e18 = 50%
        // User1's expected withdrawal: 1000e18 + (80e18 * 50%) = 1000e18 + 40e18 = 1040e18
        uint256 totalYield = yieldAmount1 + yieldAmount2;
        uint256 user1ExpectedWithdrawal = deposit1 + (totalYield * deposit1 / (deposit1 + deposit2));
        // Allow for small rounding differences (±2 wei) due to ERC4626 share calculations
        assertApproxEqAbs(actualWithdrawn, user1ExpectedWithdrawal, 2);
    }

    function testWithdrawWithLossInStrategies() public {
        uint256 deposit1 = 1000e18;
        uint256 deposit2 = 1000e18;

        _depositAsUser(user1, deposit1);
        _depositAsUser(user2, deposit2);

        uint256 allocation1 = 400e18; // Allocate 400 to strategy1
        uint256 allocation2 = 400e18; // Allocate 400 to strategy2

        _allocateToStrategy(address(strategy1), allocation1);
        _allocateToStrategy(address(strategy2), allocation2);

        // Simulate losses: 5% loss on each strategy (20e18 each)
        uint256 lossAmount1 = 20e18;
        uint256 lossAmount2 = 20e18;

        strategy1.simulateLoss(lossAmount1);
        strategy2.simulateLoss(lossAmount2);

        assertEq(strategy1.totalAllocatedValue(), allocation1 - lossAmount1);
        assertEq(strategy2.totalAllocatedValue(), allocation2 - lossAmount2);

        // Check what user1 can withdraw (should reflect their share of losses)
        uint256 maxRedeemableShares = concreteStandardVault.maxRedeem(user1);
        uint256 expectedWithdrawable = concreteStandardVault.previewRedeem(maxRedeemableShares);

        // Withdraw user1's available position
        vm.prank(user1);
        uint256 actualWithdrawn = concreteStandardVault.redeem(maxRedeemableShares, user1, user1);

        // The user should get exactly what preview says
        assertEq(actualWithdrawn, expectedWithdrawable);

        // Calculate expected withdrawal with losses (allowing for small rounding)
        // Total deposits: 2000e18, Total losses: 40e18 (20e18 + 20e18)
        // User1's share: 1000e18 / 2000e18 = 50%
        // User1's expected withdrawal: 1000e18 - (40e18 * 50%) = 1000e18 - 20e18 = 980e18
        uint256 totalLoss = lossAmount1 + lossAmount2;
        uint256 user1ExpectedWithdrawal = deposit1 - (totalLoss * deposit1 / (deposit1 + deposit2));
        // Allow for small rounding differences (±2 wei) due to ERC4626 share calculations
        assertApproxEqAbs(actualWithdrawn, user1ExpectedWithdrawal, 2);
    }

    function testWithdrawWithInsufficientLiquidity() public {
        // Setup: Deposit and allocate all funds
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);

        uint256 totalDeposited = INITIAL_DEPOSIT * 2;

        // Allocate all funds to strategy
        _allocateToStrategy(address(strategy1), totalDeposited);

        // Simulate insufficient liquidity in underlying protocol (high utilization ratio)
        // Mock the strategy's maxWithdraw to return much less than allocated
        uint256 limitedLiquidity = 200e18; // Only 200 tokens available due to high utilization
        vm.mockCall(
            address(strategy1), abi.encodeWithSelector(strategy1.maxWithdraw.selector), abi.encode(limitedLiquidity)
        );

        // Check what user1 can actually withdraw (should be limited by strategy liquidity)
        uint256 maxWithdrawable = concreteStandardVault.maxWithdraw(user1);

        // Verify that maxWithdraw is significantly less than user's deposit due to liquidity constraints
        assertLt(maxWithdrawable, INITIAL_DEPOSIT);
        // maxWithdraw should be limited by the strategy's maxWithdraw
        assertEq(maxWithdrawable, limitedLiquidity);

        // Should be able to withdraw up to the maximum available
        vm.prank(user1);
        concreteStandardVault.withdraw(maxWithdrawable, user1, user1);

        // Try to withdraw more than maxWithdraw - should revert
        uint256 excessiveAmount = maxWithdrawable + 1;

        vm.prank(user1);
        vm.expectRevert(); // Should revert when trying to withdraw more than maxWithdraw
        concreteStandardVault.withdraw(excessiveAmount, user1, user1);
    }

    function testMaxWithdrawCalculations() public {
        // Setup: Multiple users with different deposit amounts
        uint256 user1Deposit = 600e18;
        uint256 user2Deposit = 400e18;

        _depositAsUser(user1, user1Deposit);
        _depositAsUser(user2, user2Deposit);

        // Allocate partial funds
        _allocateToStrategy(address(strategy1), 500e18);
        _allocateToStrategy(address(strategy2), 300e18);

        // Test maxWithdraw for each user
        uint256 user1MaxWithdraw = concreteStandardVault.maxWithdraw(user1);
        uint256 user2MaxWithdraw = concreteStandardVault.maxWithdraw(user2);

        // Each user should be able to withdraw their proportional share
        assertEq(user1MaxWithdraw, user1Deposit);
        assertEq(user2MaxWithdraw, user2Deposit);
    }

    function testWithdrawTriggersYieldAccrual() public {
        // Setup: Deposit and allocate
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);

        _allocateToStrategy(address(strategy1), STRATEGY_ALLOCATION);

        // Simulate yield that hasn't been accrued yet
        uint256 yieldAmount = 40e18;
        asset.approve(address(strategy1), yieldAmount);
        strategy1.simulateYield(yieldAmount);

        yieldAmount =
            strategy1.totalAllocatedValue() - concreteStandardVault.getStrategyData(address(strategy1)).allocated;

        // Withdrawal should trigger automatic yield accrual
        vm.expectEmit();
        emit IConcreteStandardVaultImpl.YieldAccrued(yieldAmount, 0);

        vm.prank(user1);
        concreteStandardVault.withdraw(100e18, user1, user1);

        // Verify yield accrual updated vault accounting
        uint256 expectedTotalAssets = (INITIAL_DEPOSIT * 2) + yieldAmount - 100e18;
        assertEq(concreteStandardVault.cachedTotalAssets(), expectedTotalAssets);
    }

    function testRedeemFromAllocatedStrategies() public {
        // Setup: Deposit and allocate ALL funds to force strategy deallocation
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);

        uint256 totalDeposited = INITIAL_DEPOSIT * 2;

        // Allocate ALL funds to strategy to ensure redeem requires deallocation
        _allocateToStrategy(address(strategy1), totalDeposited);

        uint256 user1Shares = concreteStandardVault.balanceOf(user1);
        uint256 halfShares = user1Shares / 2;

        // Use previewRedeem to get exact expected amount
        uint256 expectedAssets = concreteStandardVault.previewRedeem(halfShares);

        // Redeem half of user1's shares
        vm.prank(user1);
        uint256 assetsReceived = concreteStandardVault.redeem(halfShares, user1, user1);

        // Should receive exactly what preview says
        assertEq(assetsReceived, expectedAssets);

        // Verify strategy was deallocated from (should be less than full allocation)
        uint256 remainingAllocation = strategy1.totalAllocatedValue();
        assertLt(remainingAllocation, totalDeposited);
    }

    function testPartialWithdrawFromMultipleUsersWithStrategies() public {
        // Setup: Multiple users deposit
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);
        _depositAsUser(user3, INITIAL_DEPOSIT);

        uint256 totalDeposited = INITIAL_DEPOSIT * 3;

        // Allocate most funds
        _allocateToStrategy(address(strategy1), STRATEGY_ALLOCATION);
        _allocateToStrategy(address(strategy2), STRATEGY_ALLOCATION);

        // All users withdraw partial amounts
        uint256 withdrawAmount = 200e18;

        // Capture balances before withdrawals
        uint256 user1BalanceBefore = asset.balanceOf(user1);
        uint256 user2BalanceBefore = asset.balanceOf(user2);
        uint256 user3BalanceBefore = asset.balanceOf(user3);

        vm.prank(user1);
        concreteStandardVault.withdraw(withdrawAmount, user1, user1);

        vm.prank(user2);
        concreteStandardVault.withdraw(withdrawAmount, user2, user2);

        vm.prank(user3);
        concreteStandardVault.withdraw(withdrawAmount, user3, user3);

        // Verify all withdrawals succeeded
        assertEq(asset.balanceOf(user1), user1BalanceBefore + withdrawAmount);
        assertEq(asset.balanceOf(user2), user2BalanceBefore + withdrawAmount);
        assertEq(asset.balanceOf(user3), user3BalanceBefore + withdrawAmount);

        // Check actual total assets after withdrawals
        uint256 actualTotalAssets = concreteStandardVault.cachedTotalAssets();
        uint256 expectedTotalAssets = totalDeposited - (withdrawAmount * 3);
        assertEq(actualTotalAssets, expectedTotalAssets);
    }

    // Helper functions

    function _depositAsUser(address user, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(concreteStandardVault), amount);
        concreteStandardVault.deposit(amount, user);
        vm.stopPrank();
    }

    function _allocateToStrategy(address strategy, uint256 amount) internal {
        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] = IAllocateModule.AllocateParams({strategy: strategy, isDeposit: true, extraData: abi.encode(amount)});

        bytes memory allocateData = abi.encode(params);

        vm.prank(allocator);
        concreteStandardVault.allocate(allocateData);
    }

    function _deallocateFromStrategy(address strategy, uint256 amount) internal {
        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] =
            IAllocateModule.AllocateParams({strategy: strategy, isDeposit: false, extraData: abi.encode(amount)});

        bytes memory deallocateData = abi.encode(params);

        vm.prank(allocator);
        concreteStandardVault.allocate(deallocateData);
    }
}
