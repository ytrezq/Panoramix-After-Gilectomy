// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Vm } from "../../modules/forge-std/src/Test.sol";

import { IMapleStrategy }     from "../../contracts/interfaces/IMapleStrategy.sol";
import { IMapleAaveStrategy } from "../../contracts/interfaces/aaveStrategy/IMapleAaveStrategy.sol";

import { StrategyState } from "../../contracts/interfaces/aaveStrategy/IMapleAaveStrategyStorage.sol";

import {
    IAavePoolLike,
    IAaveRewardsControllerLike,
    IAaveTokenLike,
    IERC20Like,
    IGlobalsLike,
    IPoolManagerLike
} from "../../contracts/interfaces/Interfaces.sol";

import { AaveStrategyTestBase } from "../utils/TestBase.sol";

contract MapleAaveStrategyViewFunctionTests is AaveStrategyTestBase {

    function test_aavePool() external view {
        assertEq(strategy.aavePool(), address(aavePool));
    }

    function test_aaveToken() external view {
        assertEq(strategy.aaveToken(), address(aaveToken));
    }

    function test_factory() external view {
        assertEq(strategy.factory(), address(factory));
    }

    function test_fundsAsset() external view {
        assertEq(strategy.fundsAsset(), address(asset));
    }

    function test_globals() external view {
        assertEq(strategy.globals(), address(globals));
    }

    function test_governor() external view {
        assertEq(strategy.governor(), address(governor));
    }

    function test_implementation() external view {
        assertEq(strategy.implementation(), address(implementation));
    }

    function test_locked() external view {
        assertEq(strategy.locked(), 1);
    }

    function test_poolDelegate() external view {
        assertEq(strategy.poolDelegate(), address(poolDelegate));
    }

    function test_pool() external view {
        assertEq(strategy.pool(), address(pool));
    }

    function test_poolManager() external view {
        assertEq(strategy.poolManager(), address(poolManager));
    }

    function test_securityAdmin() external view {
        assertEq(strategy.securityAdmin(), address(securityAdmin));
    }

    function test_strategyState() external view {
        assertEq(uint256(strategy.strategyState()), uint256(StrategyState.Active));
    }

    function test_treasury() external view {
        assertEq(strategy.treasury(), address(treasury));
    }

    function test_strategyType() external view {
        assertEq(strategy.STRATEGY_TYPE(), "AAVE");
    }

}

contract MapleAaveStrategyAssetsUnderManagementTests is AaveStrategyTestBase {

    function testFuzz_assetsUnderManagement_strategyActive(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        aaveToken.__setCurrentTotalAssets(currentTotalAssets);
        strategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        strategy.__setStrategyFeeRate(strategyFeeRate);
        strategy.__setStrategyState(StrategyState.Active);

        uint256 AUM = currentTotalAssets;

        if (currentTotalAssets > lastRecordedTotalAssets) {
            AUM -= (currentTotalAssets - lastRecordedTotalAssets) * strategyFeeRate / 1e6;
        }

        vm.expectCall(
            address(aaveToken),
            abi.encodeCall(IERC20Like.balanceOf, (address(strategy)))
        );

        assertEq(strategy.assetsUnderManagement(), AUM);
    }

    function testFuzz_assetsUnderManagement_strategyImpaired(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        aaveToken.__setCurrentTotalAssets(currentTotalAssets);
        strategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        strategy.__setStrategyFeeRate(strategyFeeRate);
        strategy.__setStrategyState(StrategyState.Impaired);

        uint256 AUM = currentTotalAssets;

        if (currentTotalAssets > lastRecordedTotalAssets) {
            AUM -= (currentTotalAssets - lastRecordedTotalAssets) * strategyFeeRate / 1e6;
        }

        vm.expectCall(
            address(aaveToken),
            abi.encodeCall(IERC20Like.balanceOf, (address(strategy)))
        );

        assertEq(strategy.assetsUnderManagement(), AUM);
    }

    function testFuzz_assetsUnderManagement_strategyInactive(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        aaveToken.__setCurrentTotalAssets(currentTotalAssets);
        strategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        strategy.__setStrategyFeeRate(strategyFeeRate);
        strategy.__setStrategyState(StrategyState.Inactive);

        assertEq(strategy.assetsUnderManagement(), 0);
    }

}

contract MapleAaveStrategyUnrealizedLossesTests is AaveStrategyTestBase {

    function testFuzz_unrealizedLosses_strategyActive(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        aaveToken.__setCurrentTotalAssets(currentTotalAssets);
        strategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        strategy.__setStrategyFeeRate(strategyFeeRate);
        strategy.__setStrategyState(StrategyState.Active);

        assertEq(strategy.unrealizedLosses(), 0);
    }

    function testFuzz_unrealizedLosses_strategyImpaired(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        aaveToken.__setCurrentTotalAssets(currentTotalAssets);
        strategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        strategy.__setStrategyFeeRate(strategyFeeRate);
        strategy.__setStrategyState(StrategyState.Impaired);

        assertEq(strategy.unrealizedLosses(), strategy.assetsUnderManagement());
    }

    function testFuzz_unrealizedLosses_strategyInactive(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        aaveToken.__setCurrentTotalAssets(currentTotalAssets);
        strategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        strategy.__setStrategyFeeRate(strategyFeeRate);
        strategy.__setStrategyState(StrategyState.Inactive);

        assertEq(strategy.unrealizedLosses(), 0);
    }

}

contract MapleAaveStrategyFundStrategyTests is AaveStrategyTestBase {

    uint256 assets = 1e18;

    function setUp() public override {
        super.setUp();
    }

    function test_fund_failReentrancy() external {
        strategy.__setLocked(2);

        vm.expectRevert("MS:LOCKED");
        strategy.fundStrategy(assets);
    }

    function test_fund_failWhenPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.fundStrategy(assets);
    }

    function test_fund_failIfNonManager() external {
        globals.__setIsInstanceOf(false);

        vm.expectRevert("MS:NOT_MANAGER");
        strategy.fundStrategy(assets);
    }

    function test_fund_failIfImpaired() external {
        strategy.__setStrategyState(StrategyState.Impaired);

        vm.expectRevert("MS:NOT_ACTIVE");
        strategy.fundStrategy(assets);
    }

    function test_fund_failIfInactive() external {
        strategy.__setStrategyState(StrategyState.Inactive);

        vm.expectRevert("MS:NOT_ACTIVE");
        strategy.fundStrategy(assets);
    }

    function test_fund_failIfInvalidAavePool() external {
        globals.__setIsInstanceOf(false);

        vm.prank(poolDelegate);
        vm.expectRevert("MAS:FS:INVALID_AAVE_TOKEN");
        strategy.fundStrategy(assets);
    }

    function test_fundStrategy_successWithPoolDelegate() external {
        aaveToken.__setCurrentTotalAssets(assets);

        vm.expectEmit();
        emit StrategyFunded(assets);

        vm.expectCall(
            address(poolManager),
            abi.encodeCall(IPoolManagerLike.requestFunds, (address(strategy), assets))
        );

        vm.expectCall(
            address(aavePool),
            abi.encodeCall(IAavePoolLike.supply, (address(asset), assets, address(strategy), 0))
        );

        vm.prank(poolDelegate);
        strategy.fundStrategy(assets);

        assertEq(strategy.lastRecordedTotalAssets(), assets);
    }

    function test_fundStrategy_successWithStrategyManager() external {
        aaveToken.__setCurrentTotalAssets(assets);

        vm.expectEmit();
        emit StrategyFunded(assets);

        vm.expectCall(
            address(poolManager),
            abi.encodeCall(IPoolManagerLike.requestFunds, (address(strategy), assets))
        );

        vm.expectCall(
            address(aavePool),
            abi.encodeCall(IAavePoolLike.supply, (address(asset), assets, address(strategy), 0))
        );

        vm.prank(strategyManager);
        strategy.fundStrategy(assets);

        assertEq(strategy.lastRecordedTotalAssets(), assets);
    }

}

contract MapleAaveStrategyWithdrawFromStrategyTests is AaveStrategyTestBase {

    uint256 assetsOut   = 1e18;
    uint256 totalAssets = 150e18;

    function setUp() public override {
        super.setUp();

        aaveToken.__setCurrentTotalAssets(totalAssets);
        strategy.__setLastRecordedTotalAssets(totalAssets);
    }

    function test_withdrawFromStrategy_failReentrancy() external {
        strategy.__setLocked(2);

        vm.expectRevert("MS:LOCKED");
        strategy.withdrawFromStrategy(assetsOut);
    }

    function test_withdrawFromStrategy_failWhenPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.withdrawFromStrategy(assetsOut);
    }

    function test_withdrawFromStrategy_failIfNonManager() external {
        globals.__setIsInstanceOf(false);

        vm.expectRevert("MS:NOT_MANAGER");
        strategy.withdrawFromStrategy(assetsOut);
    }

    function test_withdrawFromStrategy_failIfZeroAssets() external {
        vm.expectRevert("MAS:WFS:ZERO_ASSETS");
        strategy.withdrawFromStrategy(0);
    }

    function test_withdrawFromStrategy_failIfLowAssets() external {
        vm.prank(poolDelegate);
        vm.expectRevert("MAS:WFS:LOW_ASSETS");
        strategy.withdrawFromStrategy(totalAssets + 1);
    }

    function test_withdrawFromStrategy_successWithPoolDelegate() external {
        vm.expectEmit();
        emit StrategyWithdrawal(assetsOut);

            vm.expectCall(
            address(globals),
            abi.encodeCall(IGlobalsLike.isFunctionPaused, (IMapleAaveStrategy.withdrawFromStrategy.selector))
        );

        vm.expectCall(
            address(aaveToken),
            abi.encodeCall(IAaveTokenLike.balanceOf, (address(strategy)))
        );

        vm.expectCall(
            address(aavePool),
            abi.encodeCall(IAavePoolLike.withdraw, (address(asset), assetsOut, address(pool)))
        );

        vm.prank(poolDelegate);
        strategy.withdrawFromStrategy(assetsOut);

        assertEq(strategy.lastRecordedTotalAssets(), strategy.__currentTotalAssets());
    }

    function test_withdrawFromStrategy_successWithStrategyManager() external {
        vm.expectEmit();
        emit StrategyWithdrawal(assetsOut);

            vm.expectCall(
            address(globals),
            abi.encodeCall(IGlobalsLike.isFunctionPaused, (IMapleAaveStrategy.withdrawFromStrategy.selector))
        );

        vm.expectCall(
            address(aaveToken),
            abi.encodeCall(IAaveTokenLike.balanceOf, (address(strategy)))
        );

        vm.expectCall(
            address(aavePool),
            abi.encodeCall(IAavePoolLike.withdraw, (address(asset), assetsOut, address(pool)))
        );

        vm.prank(strategyManager);
        strategy.withdrawFromStrategy(assetsOut);

        assertEq(strategy.lastRecordedTotalAssets(), strategy.__currentTotalAssets());
    }

    function test_withdrawFromStrategy_successWhenImpaired() external {
        strategy.__setStrategyState(StrategyState.Impaired);

        vm.expectEmit();
        emit StrategyWithdrawal(assetsOut);

        vm.expectCall(
            address(globals),
            abi.encodeCall(IGlobalsLike.isFunctionPaused, (IMapleAaveStrategy.withdrawFromStrategy.selector))
        );

        vm.expectCall(
            address(aavePool),
            abi.encodeCall(IAavePoolLike.withdraw, (address(asset), assetsOut, address(pool)))
        );

        vm.prank(strategyManager);
        strategy.withdrawFromStrategy(assetsOut);

        assertEq(strategy.lastRecordedTotalAssets(), totalAssets);
    }

    function test_withdrawFromStrategy_successWhenInactive() external {
        strategy.__setStrategyState(StrategyState.Inactive);

        vm.expectEmit();
        emit StrategyWithdrawal(assetsOut);

        vm.expectCall(
            address(globals),
            abi.encodeCall(IGlobalsLike.isFunctionPaused, (IMapleAaveStrategy.withdrawFromStrategy.selector))
        );

        vm.expectCall(
            address(aavePool),
            abi.encodeCall(IAavePoolLike.withdraw, (address(asset), assetsOut, address(pool)))
        );

        vm.prank(strategyManager);
        strategy.withdrawFromStrategy(assetsOut);

        assertEq(strategy.lastRecordedTotalAssets(), totalAssets);
    }

}

contract MapleAaveStrategySetStrategyFeeRateTests is AaveStrategyTestBase {

    uint256 balance    = 8_500_000e6;
    uint256 gain       = 16_301e6;
    uint256 loss       = 14_125e6;
    uint256 newFeeRate = 420;
    uint256 oldFeeRate = 1337;

    function test_setStrategyFeeRate_failReentrancy() external {
        strategy.__setLocked(2);

        vm.expectRevert("MS:LOCKED");
        strategy.setStrategyFeeRate(newFeeRate);
    }

    function test_setStrategyFeeRate_failWhenPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.setStrategyFeeRate(newFeeRate);
    }

    function test_setStrategyFeeRate_failWhenNotAdmin() external {
        vm.expectRevert("MS:NOT_ADMIN");
        strategy.setStrategyFeeRate(newFeeRate);
    }

    function test_setStrategyFeeRate_failIfImpaired() external {
        strategy.__setStrategyState(StrategyState.Impaired);

        vm.prank(poolDelegate);
        vm.expectRevert("MS:NOT_ACTIVE");
        strategy.setStrategyFeeRate(newFeeRate);
    }

    function test_setStrategyFeeRate_failIfInactive() external {
        strategy.__setStrategyState(StrategyState.Inactive);

        vm.prank(poolDelegate);
        vm.expectRevert("MS:NOT_ACTIVE");
        strategy.setStrategyFeeRate(newFeeRate);
    }

    function test_setStrategyFeeRate_failWhenInvalidStrategyFeeRate() external {
        vm.expectRevert("MAS:SSFR:INVALID_FEE_RATE");
        vm.prank(poolDelegate);
        strategy.setStrategyFeeRate(1e6 + 1);
    }

    function test_setStrategyFeeRate_successWithPoolDelegate() external {
        vm.prank(poolDelegate);
        strategy.setStrategyFeeRate(newFeeRate);
    }

    function test_setStrategyFeeRate_successWithGovernor() external {
        vm.prank(governor);
        strategy.setStrategyFeeRate(newFeeRate);
    }

    function test_setStrategyFeeRate_successWithOperationalAdmin() external {
        vm.prank(operationalAdmin);
        strategy.setStrategyFeeRate(newFeeRate);
    }

    function test_setStrategyFeeRate_unfundedStrategy_zeroFeeRate() external {
        aaveToken.__setCurrentTotalAssets(0);
        strategy.__setLastRecordedTotalAssets(0);
        strategy.__setStrategyFeeRate(0);

        vm.expectEmit();
        emit StrategyFeeRateSet(newFeeRate);

        vm.prank(governor);
        strategy.setStrategyFeeRate(newFeeRate);

        assertEq(strategy.lastRecordedTotalAssets(), 0);
        assertEq(strategy.strategyFeeRate(),         newFeeRate);
    }

    function test_setStrategyFeeRate_unfundedStrategy_realisticFeeRate() external {
        aaveToken.__setCurrentTotalAssets(0);
        strategy.__setLastRecordedTotalAssets(0);
        strategy.__setStrategyFeeRate(oldFeeRate);

        vm.expectEmit();
        emit StrategyFeeRateSet(newFeeRate);

        vm.prank(governor);
        strategy.setStrategyFeeRate(newFeeRate);

        assertEq(strategy.lastRecordedTotalAssets(), 0);
        assertEq(strategy.strategyFeeRate(),         newFeeRate);
    }

    function test_setStrategyFeeRate_normalGain_zeroFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance + gain);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(0);

        vm.expectEmit();
        emit StrategyFeeRateSet(newFeeRate);

        vm.prank(governor);
        strategy.setStrategyFeeRate(newFeeRate);

        assertEq(strategy.lastRecordedTotalAssets(), balance + gain);
        assertEq(strategy.strategyFeeRate(),         newFeeRate);
    }

    function test_setStrategyFeeRate_normalGain_realisticFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance + gain);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(oldFeeRate);

        vm.expectEmit();
        emit StrategyFeesCollected(gain * oldFeeRate / 1e6);

        vm.expectEmit();
        emit StrategyFeeRateSet(newFeeRate);

        vm.prank(governor);
        strategy.setStrategyFeeRate(newFeeRate);

        assertEq(strategy.strategyFeeRate(),         newFeeRate);
    }

    function test_setStrategyFeeRate_normalGain_1e6() external {
        aaveToken.__setCurrentTotalAssets(balance + gain);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(1e6);

        vm.expectEmit();
        emit StrategyFeesCollected(gain);

        vm.expectEmit();
        emit StrategyFeeRateSet(newFeeRate);

        vm.prank(governor);
        strategy.setStrategyFeeRate(newFeeRate);

        assertEq(strategy.strategyFeeRate(),         newFeeRate);
    }

    function test_setStrategyFeeRate_normalLoss_zeroFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance - loss);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(0);

        vm.expectEmit();
        emit StrategyFeeRateSet(newFeeRate);

        vm.prank(governor);
        strategy.setStrategyFeeRate(newFeeRate);

        assertEq(strategy.lastRecordedTotalAssets(), balance - loss);
        assertEq(strategy.strategyFeeRate(),         newFeeRate);
    }

    function test_setStrategyFeeRate_normalLoss_realisticFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance - loss);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(oldFeeRate);

        vm.expectEmit();
        emit StrategyFeeRateSet(newFeeRate);

        vm.prank(governor);
        strategy.setStrategyFeeRate(newFeeRate);

        assertEq(strategy.lastRecordedTotalAssets(), balance - loss);
        assertEq(strategy.strategyFeeRate(),         newFeeRate);
    }

    function test_setStrategyFeeRate_totalLoss_zeroFeeRate() external {
        aaveToken.__setCurrentTotalAssets(0);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(0);

        vm.expectEmit();
        emit StrategyFeeRateSet(newFeeRate);

        vm.prank(governor);
        strategy.setStrategyFeeRate(newFeeRate);

        assertEq(strategy.lastRecordedTotalAssets(), 0);
        assertEq(strategy.strategyFeeRate(),         newFeeRate);
    }

    function test_setStrategyFeeRate_totalLoss_realisticFeeRate() external {
        aaveToken.__setCurrentTotalAssets(0);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(0);

        vm.expectEmit();
        emit StrategyFeeRateSet(newFeeRate);

        vm.prank(governor);
        strategy.setStrategyFeeRate(newFeeRate);

        assertEq(strategy.lastRecordedTotalAssets(), 0);
        assertEq(strategy.strategyFeeRate(),         newFeeRate);
    }

}


// TODO: Do these tests make sense post refactor as the accrueFees function doesn't change lastRecordedTotalAssets?
contract MapleAaveStrategyAccrueFeesTests is AaveStrategyTestBase {

    uint256 balance = 8_500_000e6;
    uint256 feeRate = 1337;
    uint256 gain    = 16_301e6;
    uint256 loss    = 14_125e6;

    function test_accrueFees_unfundedStrategy_zeroFeeRate() external {
        aaveToken.__setCurrentTotalAssets(0);
        strategy.__setLastRecordedTotalAssets(0);
        strategy.__setStrategyFeeRate(0);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_unfundedStrategy_realisticFeeRate() external {
        aaveToken.__setCurrentTotalAssets(0);
        strategy.__setLastRecordedTotalAssets(0);
        strategy.__setStrategyFeeRate(feeRate);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_minimumGain_zeroFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance + 1);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(0);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_minimumGain_realisticFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance + 1);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(feeRate);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_normalGain_zeroFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance + gain);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(0);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_normalGain_realisticFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance + gain);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(feeRate);

        vm.expectEmit();
        emit StrategyFeesCollected(gain * feeRate / 1e6);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_normalGain_minimumFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance + gain);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(1);

        vm.expectEmit();
        emit StrategyFeesCollected(gain / 1e6);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_normalGain_maximumFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance + gain);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(1e6);

        vm.expectEmit();
        emit StrategyFeesCollected(gain);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_minimumLoss_zeroFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance - 1);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(0);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_minimumLoss_realisticFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance - 1);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(feeRate);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_normalLoss_zeroFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance - loss);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(0);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_normalLoss_realisticFeeRate() external {
        aaveToken.__setCurrentTotalAssets(balance - loss);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(feeRate);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_totalLoss_zeroFeeRate() external {
        aaveToken.__setCurrentTotalAssets(0);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(0);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

    function test_accrueFees_totalLoss_realisticFeeRate() external {
        aaveToken.__setCurrentTotalAssets(0);
        strategy.__setLastRecordedTotalAssets(balance);
        strategy.__setStrategyFeeRate(feeRate);

        vm.prank(governor);
        strategy.__accrueFees(address(aavePool), address(aaveToken), address(asset));
    }

}

contract MapleAaveStrategyDeactivateStrategyTests is AaveStrategyTestBase {

    function test_deactivateStrategy_failReentrancy() external {
        strategy.__setLocked(2);

        vm.expectRevert("MS:LOCKED");
        strategy.deactivateStrategy();
    }

    function test_deactivateStrategy_failWhenPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.deactivateStrategy();
    }

    function test_deactivateStrategy_failIfNotProtocolAdmin() external {
        vm.expectRevert("MS:NOT_ADMIN");
        strategy.deactivateStrategy();

        vm.prank(poolDelegate);
        strategy.deactivateStrategy();

        strategy.__setStrategyState(StrategyState.Active);

        vm.prank(governor);
        strategy.deactivateStrategy();

        strategy.__setStrategyState(StrategyState.Active);

        vm.prank(operationalAdmin);
        strategy.deactivateStrategy();
    }

    function test_deactivateStrategy_failIfAlreadyInactive() external {
        strategy.__setStrategyState(StrategyState.Inactive);

        vm.prank(poolDelegate);
        vm.expectRevert("MAS:DS:ALREADY_INACTIVE");
        strategy.deactivateStrategy();
    }

    function test_deactivateStrategy_successWhenActive() external {
        strategy.__setStrategyState(StrategyState.Active);

        vm.expectEmit();
        emit StrategyDeactivated();

        vm.prank(poolDelegate);
        strategy.deactivateStrategy();

        assertEq(uint256(strategy.strategyState()), uint256(StrategyState.Inactive));
    }

    function test_deactivateStrategy_successWhenImpaired() external {
        strategy.__setStrategyState(StrategyState.Impaired);

        vm.expectEmit();
        emit StrategyDeactivated();

        vm.prank(poolDelegate);
        strategy.deactivateStrategy();

        assertEq(uint256(strategy.strategyState()), uint256(StrategyState.Inactive));
    }

}

contract MapleAaveStrategyImpairStrategyTests is AaveStrategyTestBase {

    function test_impairStrategy_failReentrancy() external {
        strategy.__setLocked(2);

        vm.expectRevert("MS:LOCKED");
        strategy.impairStrategy();
    }

    function test_impairStrategy_failWhenPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.impairStrategy();
    }

    function test_impairStrategy_failIfNotProtocolAdmin() external {
        vm.expectRevert("MS:NOT_ADMIN");
        strategy.impairStrategy();

        vm.prank(poolDelegate);
        strategy.impairStrategy();

        strategy.__setStrategyState(StrategyState.Active);

        vm.prank(governor);
        strategy.impairStrategy();

        strategy.__setStrategyState(StrategyState.Active);

        vm.prank(operationalAdmin);
        strategy.impairStrategy();
    }

    function test_impairStrategy_failIfAlreadyImpaired() external {
        strategy.__setStrategyState(StrategyState.Impaired);

        vm.prank(poolDelegate);
        vm.expectRevert("MAS:IS:ALREADY_IMPAIRED");
        strategy.impairStrategy();
    }

    function test_impairStrategy_successWhenActive() external {
        strategy.__setStrategyState(StrategyState.Active);

        vm.expectEmit();
        emit StrategyImpaired();

        vm.prank(poolDelegate);
        strategy.impairStrategy();

        assertEq(uint256(strategy.strategyState()), uint256(StrategyState.Impaired));
    }

    function test_impairStrategy_successWhenInactive() external {
        strategy.__setStrategyState(StrategyState.Inactive);

        vm.expectEmit();
        emit StrategyImpaired();

        vm.prank(poolDelegate);
        strategy.impairStrategy();

        assertEq(uint256(strategy.strategyState()), uint256(StrategyState.Impaired));
    }

}

contract MapleAaveStrategyReactivateStrategyTests is AaveStrategyTestBase {

    uint256 currentVaultBalance  = 1337e18;
    uint256 previousVaultBalance = 420e18;

    function setUp() public override {
        super.setUp();

        aaveToken.__setCurrentTotalAssets(currentVaultBalance);
        strategy.__setLastRecordedTotalAssets(previousVaultBalance);
        strategy.__setStrategyState(StrategyState.Inactive);
    }

    function test_reactivateStrategy_failReentrancy() external {
        strategy.__setLocked(2);

        vm.expectRevert("MS:LOCKED");
        strategy.reactivateStrategy(false);
    }

    function test_reactivateStrategy_failWhenPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.reactivateStrategy(false);
    }

    function test_reactivateStrategy_failIfNotProtocolAdmin() external {
        vm.expectRevert("MS:NOT_ADMIN");
        strategy.reactivateStrategy(false);

        vm.prank(poolDelegate);
        strategy.reactivateStrategy(false);

        strategy.__setStrategyState(StrategyState.Inactive);

        vm.prank(governor);
        strategy.reactivateStrategy(false);

        strategy.__setStrategyState(StrategyState.Inactive);

        vm.prank(operationalAdmin);
        strategy.reactivateStrategy(false);
    }

    function test_reactivateStrategy_failIfAlreadyActive() external {
        strategy.__setStrategyState(StrategyState.Active);

        vm.prank(poolDelegate);
        vm.expectRevert("MAS:RS:ALREADY_ACTIVE");
        strategy.reactivateStrategy(false);
    }

    function test_reactivateStrategy_successWhenInactive_withoutAccountingUpdate() external {
        strategy.__setStrategyState(StrategyState.Inactive);

        vm.expectEmit();
        emit StrategyReactivated(false);

        vm.prank(poolDelegate);
        strategy.reactivateStrategy(false);

        assertEq(strategy.lastRecordedTotalAssets(), previousVaultBalance);
        assertEq(uint256(strategy.strategyState()),  uint256(StrategyState.Active));
    }

    function test_reactivateStrategy_successWhenInactive_withAccountingUpdate() external {
        strategy.__setStrategyState(StrategyState.Inactive);

        vm.expectEmit();
        emit StrategyReactivated(true);

        vm.prank(poolDelegate);
        strategy.reactivateStrategy(true);

        assertEq(strategy.lastRecordedTotalAssets(), currentVaultBalance);
        assertEq(uint256(strategy.strategyState()),  uint256(StrategyState.Active));
    }

    function test_reactivateStrategy_successWhenImpaired_withoutAccountingUpdate() external {
        strategy.__setStrategyState(StrategyState.Impaired);

        vm.expectEmit();
        emit StrategyReactivated(false);

        vm.prank(poolDelegate);
        strategy.reactivateStrategy(false);

        assertEq(strategy.lastRecordedTotalAssets(), previousVaultBalance);
        assertEq(uint256(strategy.strategyState()),  uint256(StrategyState.Active));
    }

    function test_reactivateStrategy_successWhenImpaired_withAccountingUpdate() external {
        strategy.__setStrategyState(StrategyState.Impaired);

        vm.expectEmit();
        emit StrategyReactivated(true);

        vm.prank(poolDelegate);
        strategy.reactivateStrategy(true);

        assertEq(strategy.lastRecordedTotalAssets(), currentVaultBalance);
        assertEq(uint256(strategy.strategyState()),  uint256(StrategyState.Active));
    }

}

contract ClaimRewardsTests is AaveStrategyTestBase {

    address rewardToken = makeAddr("rewardToken");

    uint256 rewardAmount = 1e18;

    address[] assets;

    function setUp() public override {
        super.setUp();

        assets.push(address(aaveToken));

        aaveRewardsController.__setRewardAmount(rewardAmount);
    }

    function test_claimRewards_failReentrancy() external {
        strategy.__setLocked(2);

        vm.expectRevert("MS:LOCKED");
        strategy.claimRewards(assets, rewardAmount, rewardToken);
    }

    function test_claimRewards_failWhenPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.claimRewards(assets, rewardAmount, rewardToken);
    }

    function test_claimRewards_failIfNotProtocolAdmin() external {
        vm.expectRevert("MS:NOT_ADMIN");
        strategy.claimRewards(assets, rewardAmount, rewardToken);

        vm.prank(poolDelegate);
        strategy.claimRewards(assets, rewardAmount, rewardToken);

        vm.prank(governor);
        strategy.claimRewards(assets, rewardAmount, rewardToken);

        vm.prank(operationalAdmin);
        strategy.claimRewards(assets, rewardAmount, rewardToken);
    }

    function test_claimRewards_success() external {
        vm.expectEmit();
        emit RewardsClaimed(rewardToken, rewardAmount);

        vm.expectCall(
            address(aaveRewardsController),
            abi.encodeCall(IAaveRewardsControllerLike.claimRewards, (assets, rewardAmount, treasury, rewardToken))
        );

        vm.prank(governor);
        strategy.claimRewards(assets, rewardAmount, rewardToken);
    }

}
