// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcreteStandardVaultImplBaseSetup} from "../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {ERC4626StrategyMock} from "../mock/ERC4626StrategyMock.sol";
import {IAllocateModule} from "../../src/interface/IAllocateModule.sol";
import {InvariantUtils} from "../invariant/helpers/InvariantUtils.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {AddStrategyWithDeallocationOrder} from "../common/AddStrategyWithDeallocationOrder.sol";

contract PerformanceFeeE2ETest is ConcreteStandardVaultImplBaseSetup, AddStrategyWithDeallocationOrder {
    uint16 public constant PERFORMANCE_FEE_BPS = 1000; // 10% performance fee
    uint256 public constant INITIAL_DEPOSIT = 1000e18;
    uint256 public constant YIELD_AMOUNT = 100e18; // 10% yield

    address public user1;
    address public user2;
    address public performanceFeeRecipient;
    ERC4626StrategyMock public strategy;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        performanceFeeRecipient = makeAddr("performanceFeeRecipient");

        vm.prank(factoryOwner);
        concreteStandardVault.updatePerformanceFeeRecipient(performanceFeeRecipient);

        vm.prank(vaultManager);
        concreteStandardVault.updatePerformanceFee(PERFORMANCE_FEE_BPS);

        strategy = new ERC4626StrategyMock(address(asset));

        addStrategyWithDeallocationOrder(address(strategy), address(concreteStandardVault), allocator, strategyOperator);

        asset.mint(user1, INITIAL_DEPOSIT);
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), INITIAL_DEPOSIT);
        concreteStandardVault.deposit(INITIAL_DEPOSIT, user1);
        vm.stopPrank();

        assertEq(concreteStandardVault.balanceOf(user1), INITIAL_DEPOSIT);
        assertEq(concreteStandardVault.cachedTotalAssets(), INITIAL_DEPOSIT);
    }

    function testPerformanceFeeAccrualOnYield() public {
        uint256 allocateAmount = 500e18;
        _allocateToStrategy(allocateAmount);

        _simulateYield(YIELD_AMOUNT);

        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(performanceFeeRecipient);
        uint256 totalSupplyBefore = concreteStandardVault.totalSupply();
        uint256 totalAssetsBefore = concreteStandardVault.cachedTotalAssets();

        uint256 netPositiveYield = _getActualYield();
        uint256 expectedFeeAmount = (netPositiveYield * PERFORMANCE_FEE_BPS) / 10_000;
        uint256 expectedFeeShares = InvariantUtils.convertToShares(
            expectedFeeAmount,
            totalSupplyBefore,
            totalAssetsBefore + netPositiveYield - expectedFeeAmount,
            Math.Rounding.Floor
        );

        concreteStandardVault.accrueYield();

        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(performanceFeeRecipient);
        uint256 totalSupplyAfter = concreteStandardVault.totalSupply();

        assertEq(recipientBalanceAfter - recipientBalanceBefore, expectedFeeShares);
        assertEq(totalSupplyAfter - totalSupplyBefore, expectedFeeShares);
        assertGt(recipientBalanceAfter, 0);
    }

    function testNoPerformanceFeeOnNoYield() public {
        uint256 allocateAmount = 500e18;
        _allocateToStrategy(allocateAmount);

        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(performanceFeeRecipient);
        uint256 totalSupplyBefore = concreteStandardVault.totalSupply();

        concreteStandardVault.accrueYield();

        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(performanceFeeRecipient);
        uint256 totalSupplyAfter = concreteStandardVault.totalSupply();

        assertEq(recipientBalanceAfter, recipientBalanceBefore);
        assertEq(totalSupplyAfter, totalSupplyBefore);
        assertEq(recipientBalanceAfter, 0);
    }

    function testPerformanceFeeOnMultipleYieldAccruals() public {
        uint256 allocateAmount = 500e18;
        _allocateToStrategy(allocateAmount);

        _simulateYield(YIELD_AMOUNT);

        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(performanceFeeRecipient);
        uint256 totalSupplyBefore = concreteStandardVault.totalSupply();
        uint256 totalAssetsBefore = concreteStandardVault.cachedTotalAssets();

        uint256 netPositiveYield1 = _getActualYield();
        uint256 expectedFeeAmount1 = (netPositiveYield1 * PERFORMANCE_FEE_BPS) / 10_000;
        uint256 expectedFeeShares1 = InvariantUtils.convertToShares(
            expectedFeeAmount1,
            totalSupplyBefore,
            totalAssetsBefore + netPositiveYield1 - expectedFeeAmount1,
            Math.Rounding.Floor
        );

        concreteStandardVault.accrueYield();
        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(performanceFeeRecipient);

        uint256 firstYieldAccrualFeeShares = recipientBalanceAfter - recipientBalanceBefore;
        assertEq(firstYieldAccrualFeeShares, expectedFeeShares1);

        uint256 smallerYieldAmount = YIELD_AMOUNT / 2;
        _simulateYield(smallerYieldAmount);

        recipientBalanceBefore = concreteStandardVault.balanceOf(performanceFeeRecipient);
        totalSupplyBefore = concreteStandardVault.totalSupply();
        totalAssetsBefore = concreteStandardVault.cachedTotalAssets();

        uint256 netPositiveYield2 = _getActualYield();
        uint256 expectedFeeAmount2 = (netPositiveYield2 * PERFORMANCE_FEE_BPS) / 10_000;
        uint256 expectedFeeShares2 = InvariantUtils.convertToShares(
            expectedFeeAmount2,
            totalSupplyBefore,
            totalAssetsBefore + netPositiveYield2 - expectedFeeAmount2,
            Math.Rounding.Floor
        );

        concreteStandardVault.accrueYield();
        recipientBalanceAfter = concreteStandardVault.balanceOf(performanceFeeRecipient);

        uint256 secondYieldAccrualFeeShares = recipientBalanceAfter - recipientBalanceBefore;
        assertEq(secondYieldAccrualFeeShares, expectedFeeShares2);
        assertLt(secondYieldAccrualFeeShares, firstYieldAccrualFeeShares);
    }

    function testUserWithdrawalAfterPerformanceFee() public {
        uint256 allocateAmount = 500e18;
        _allocateToStrategy(allocateAmount);

        // Record user balance before yield simulation
        uint256 userSharesBefore = concreteStandardVault.balanceOf(user1);
        uint256 userAssetsBefore = concreteStandardVault.previewRedeem(userSharesBefore);

        _simulateYield(YIELD_AMOUNT);
        concreteStandardVault.accrueYield();

        uint256 userSharesAfter = concreteStandardVault.balanceOf(user1);
        assertEq(userSharesAfter, userSharesBefore);

        // Shares should now be worth more due to yield (net of fees)
        uint256 userAssetsAfter = concreteStandardVault.previewRedeem(userSharesAfter);
        assertGt(userAssetsAfter, userAssetsBefore);

        vm.startPrank(user1);
        uint256 withdrawnAssets = concreteStandardVault.redeem(userSharesAfter, user1, user1);
        vm.stopPrank();

        assertEq(withdrawnAssets, userAssetsAfter);
        assertEq(concreteStandardVault.balanceOf(user1), 0);
    }

    function testPerformanceFeeWithMultipleUsers() public {
        uint256 secondDeposit = 500e18;
        asset.mint(user2, secondDeposit);
        vm.startPrank(user2);
        asset.approve(address(concreteStandardVault), secondDeposit);
        concreteStandardVault.deposit(secondDeposit, user2);
        vm.stopPrank();

        uint256 totalAssets = INITIAL_DEPOSIT + secondDeposit;
        assertEq(concreteStandardVault.cachedTotalAssets(), totalAssets);

        _allocateToStrategy(totalAssets);
        _simulateYield(YIELD_AMOUNT);

        uint256 user1SharesBefore = concreteStandardVault.balanceOf(user1);
        uint256 user2SharesBefore = concreteStandardVault.balanceOf(user2);
        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(performanceFeeRecipient);

        concreteStandardVault.accrueYield();

        assertEq(concreteStandardVault.balanceOf(user1), user1SharesBefore);
        assertEq(concreteStandardVault.balanceOf(user2), user2SharesBefore);

        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(performanceFeeRecipient);
        assertGt(recipientBalanceAfter, recipientBalanceBefore);

        vm.startPrank(user1);
        uint256 user1Withdrawal = concreteStandardVault.redeem(user1SharesBefore, user1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 user2Withdrawal = concreteStandardVault.redeem(user2SharesBefore, user2, user2);
        vm.stopPrank();

        // Users should get their proportional share of yield (net of fees)
        assertGt(user1Withdrawal, INITIAL_DEPOSIT);
        assertGt(user2Withdrawal, secondDeposit);
    }

    function testPerformanceFeeWithZeroFeeRate() public {
        vm.prank(vaultManager);
        concreteStandardVault.updatePerformanceFee(0);

        uint256 allocateAmount = 500e18;
        _allocateToStrategy(allocateAmount);
        _simulateYield(YIELD_AMOUNT);

        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(performanceFeeRecipient);
        uint256 totalSupplyBefore = concreteStandardVault.totalSupply();

        concreteStandardVault.accrueYield();

        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(performanceFeeRecipient);
        uint256 totalSupplyAfter = concreteStandardVault.totalSupply();

        assertEq(recipientBalanceAfter, recipientBalanceBefore);
        assertEq(totalSupplyAfter, totalSupplyBefore);
        assertEq(recipientBalanceAfter, 0);
    }

    function testPerformanceFeeOnDepositTriggersYieldAccrual() public {
        uint256 allocateAmount = 500e18;
        _allocateToStrategy(allocateAmount);
        _simulateYield(YIELD_AMOUNT);

        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(performanceFeeRecipient);

        // Deposit should trigger yield accrual and performance fee accrual
        uint256 depositAmount = 200e18;
        asset.mint(user2, depositAmount);
        vm.startPrank(user2);
        asset.approve(address(concreteStandardVault), depositAmount);
        concreteStandardVault.deposit(depositAmount, user2);
        vm.stopPrank();

        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(performanceFeeRecipient);
        assertGt(recipientBalanceAfter, recipientBalanceBefore);
    }

    function testPerformanceFeeWithStrategyLoss() public {
        uint256 allocateAmount = 500e18;
        _allocateToStrategy(allocateAmount);

        uint256 lossAmount = 50e18;
        strategy.simulateLoss(lossAmount);

        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(performanceFeeRecipient);
        uint256 totalSupplyBefore = concreteStandardVault.totalSupply();

        concreteStandardVault.accrueYield();

        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(performanceFeeRecipient);
        uint256 totalSupplyAfter = concreteStandardVault.totalSupply();

        assertEq(recipientBalanceAfter, recipientBalanceBefore);
        assertEq(totalSupplyAfter, totalSupplyBefore);
        assertEq(recipientBalanceAfter, 0);
    }

    function testPerformanceFeeOnNetPositiveYieldAfterLoss() public {
        uint256 allocateAmount = 500e18;
        _allocateToStrategy(allocateAmount);

        _simulateYield(YIELD_AMOUNT);
        uint256 lossAmount = 30e18; // Loss less than yield
        strategy.simulateLoss(lossAmount);

        uint256 recipientBalanceBefore = concreteStandardVault.balanceOf(performanceFeeRecipient);

        uint256 netPositiveYield = _getActualYield();
        require(netPositiveYield > 0, "Expected net positive yield");

        concreteStandardVault.accrueYield();

        uint256 recipientBalanceAfter = concreteStandardVault.balanceOf(performanceFeeRecipient);
        assertGt(recipientBalanceAfter, recipientBalanceBefore);
    }

    function _allocateToStrategy(uint256 amount) internal {
        bytes memory extraData = abi.encode(amount);
        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] = IAllocateModule.AllocateParams({isDeposit: true, strategy: address(strategy), extraData: extraData});

        bytes memory data = abi.encode(params);
        vm.prank(allocator);
        concreteStandardVault.allocate(data);
    }

    function _simulateYield(uint256 yieldAmount) internal {
        asset.mint(address(this), yieldAmount);
        asset.approve(address(strategy), yieldAmount);
        strategy.simulateYield(yieldAmount);
    }

    // Returns actual yield that vault will see during yield accrual
    function _getActualYield() internal view returns (uint256) {
        uint256 currentValue = strategy.totalAllocatedValue();
        uint256 allocatedAmount = concreteStandardVault.getStrategyData(address(strategy)).allocated;
        return currentValue > allocatedAmount ? currentValue - allocatedAmount : 0;
    }
}
