// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Vm } from "../../modules/forge-std/src/Test.sol";

import { IMapleStrategy }      from "../../contracts/interfaces/IMapleStrategy.sol";
import { IMapleBasicStrategy } from "../../contracts/interfaces/basicStrategy/IMapleBasicStrategy.sol";

import { StrategyState } from "../../contracts/interfaces/basicStrategy/IMapleBasicStrategyStorage.sol";

import {
    IERC20Like,
    IERC4626Like,
    IGlobalsLike,
    IPoolManagerLike
} from "../../contracts/interfaces/Interfaces.sol";

import { BasicStrategyTestBase }     from "../utils/TestBase.sol";
import { MapleBasicStrategyHarness } from "../utils/Harnesses.sol";

contract MapleBasicStrategyViewFunctionTests is BasicStrategyTestBase {

    MapleBasicStrategyHarness basicStrategy;

    function setUp() public override {
        super.setUp();
        vm.etch(address(strategy), address(new MapleBasicStrategyHarness()).code);

        basicStrategy = MapleBasicStrategyHarness(address(strategy));

        vault.__setExchangeRate(1);
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

    function test_poolDelegate() external view {
        assertEq(strategy.poolDelegate(), address(poolDelegate));
    }

    function test_securityAdmin() external view {
        assertEq(strategy.securityAdmin(), address(securityAdmin));
    }

    function test_treasury() external view {
        assertEq(strategy.treasury(), treasury);
    }

    function test_locked() external view {
        assertEq(strategy.locked(), 1);
    }

    function test_pool() external view {
        assertEq(strategy.pool(), address(pool));
    }

    function test_poolManager() external view {
        assertEq(strategy.poolManager(), address(poolManager));
    }

    function test_strategyVault() external view {
        assertEq(strategy.strategyVault(), address(vault));
    }

    function test_strategyType() external view {
        assertEq(strategy.STRATEGY_TYPE(), "BASIC");
    }

    function test_assetsUnderManagement_strategyNotFunded() external view {
        assertEq(basicStrategy.assetsUnderManagement(), 0);
    }

    function test_assetsUnderManagement_strategyFundedAndZeroFee() external {
        assertEq(basicStrategy.lastRecordedTotalAssets(), 0);
        assertEq(basicStrategy.strategyFeeRate(),         0);

        vault.__setBalanceOf(address(basicStrategy), 1e6);
        vault.__setExchangeRate(1);

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (1e6))
        );

        assertEq(basicStrategy.assetsUnderManagement(), 1e6);
    }

    function test_assetsUnderManagement_strategyFundedWithFeeAndLoss() external {
        basicStrategy.__setLastRecordedTotalAssets(2e6);
        basicStrategy.__setStrategyFeeRate(1500);  // 15 basis points

        assertEq(basicStrategy.lastRecordedTotalAssets(), 2e6);
        assertEq(basicStrategy.strategyFeeRate(),         1500);

        vault.__setBalanceOf(address(basicStrategy), 1e6);
        vault.__setExchangeRate(1);

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (1e6))
        );

        assertEq(basicStrategy.assetsUnderManagement(), 1e6);
    }

    function test_assetsUnderManagement_strategyFundedWithFeeAndTotalAssetsIncreased() external {
        basicStrategy.__setLastRecordedTotalAssets(2e6);
        basicStrategy.__setStrategyFeeRate(1500);  // 15 basis points

        assertEq(basicStrategy.lastRecordedTotalAssets(), 2e6);
        assertEq(basicStrategy.strategyFeeRate(),         1500);

        vault.__setBalanceOf(address(basicStrategy), 5e6);
        vault.__setExchangeRate(1);

        uint256 strategyFee = ((5e6 - 2e6) * 1500) / 1e6;

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (5e6))
        );

        assertEq(basicStrategy.assetsUnderManagement(), 5e6 - strategyFee);
    }

    function testFuzz_assetsUnderManagement_strategyActive(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        vault.__setBalanceOf(address(strategy), currentTotalAssets);
        basicStrategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        basicStrategy.__setStrategyFeeRate(strategyFeeRate);
        basicStrategy.__setStrategyState(StrategyState.Active);

        uint256 yield = currentTotalAssets > lastRecordedTotalAssets ? currentTotalAssets - lastRecordedTotalAssets : 0;
        uint256 fee   = yield * strategyFeeRate / 1e6;

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (currentTotalAssets))
        );

        assertEq(basicStrategy.assetsUnderManagement(), currentTotalAssets - fee);
    }

    function testFuzz_assetsUnderManagement_strategyImpaired(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        vault.__setBalanceOf(address(strategy), currentTotalAssets);
        basicStrategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        basicStrategy.__setStrategyFeeRate(strategyFeeRate);
        basicStrategy.__setStrategyState(StrategyState.Impaired);

        uint256 yield = currentTotalAssets > lastRecordedTotalAssets ? currentTotalAssets - lastRecordedTotalAssets : 0;
        uint256 fee   = yield * strategyFeeRate / 1e6;

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (currentTotalAssets))
        );

        assertEq(basicStrategy.assetsUnderManagement(), currentTotalAssets - fee);
    }

    function testFuzz_assetsUnderManagement_strategyInactive(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        vault.__setBalanceOf(address(strategy), currentTotalAssets);
        basicStrategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        basicStrategy.__setStrategyFeeRate(strategyFeeRate);
        basicStrategy.__setStrategyState(StrategyState.Inactive);

        assertEq(basicStrategy.assetsUnderManagement(), 0);
    }

    function testFuzz_unrealizedLosses_strategyActive(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        vault.__setBalanceOf(address(strategy), currentTotalAssets);
        basicStrategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        basicStrategy.__setStrategyFeeRate(strategyFeeRate);
        basicStrategy.__setStrategyState(StrategyState.Active);

        assertEq(basicStrategy.unrealizedLosses(), 0);
    }

    function testFuzz_unrealizedLosses_strategyImpaired(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        vault.__setBalanceOf(address(strategy), currentTotalAssets);
        basicStrategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        basicStrategy.__setStrategyFeeRate(strategyFeeRate);
        basicStrategy.__setStrategyState(StrategyState.Impaired);

        uint256 yield = currentTotalAssets > lastRecordedTotalAssets ? currentTotalAssets - lastRecordedTotalAssets : 0;
        uint256 fee   = yield * strategyFeeRate / 1e6;

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (currentTotalAssets))
        );

        assertEq(basicStrategy.unrealizedLosses(), currentTotalAssets - fee);
    }

    function testFuzz_unrealizedLosses_strategyInactive(
        uint256 currentTotalAssets,
        uint256 lastRecordedTotalAssets,
        uint256 strategyFeeRate
    ) external {
        currentTotalAssets      = bound(currentTotalAssets,      0, 1e30);
        lastRecordedTotalAssets = bound(lastRecordedTotalAssets, 0, 1e30);
        strategyFeeRate         = bound(strategyFeeRate,         0, 1e6);

        vault.__setBalanceOf(address(strategy), currentTotalAssets);
        basicStrategy.__setLastRecordedTotalAssets(lastRecordedTotalAssets);
        basicStrategy.__setStrategyFeeRate(strategyFeeRate);
        basicStrategy.__setStrategyState(StrategyState.Inactive);

        assertEq(basicStrategy.unrealizedLosses(), 0);
    }

}

contract MapleBasicStrategyFundStrategyTests is BasicStrategyTestBase {

    MapleBasicStrategyHarness basicStrategy;

    function setUp() public override {
        super.setUp();

        vm.etch(address(strategy), address(new MapleBasicStrategyHarness()).code);

        basicStrategy = MapleBasicStrategyHarness(address(strategy));
    }

    function test_fund_failReentrancy() external {
        basicStrategy.__setLocked(2);

        vm.expectRevert("MS:LOCKED");
        strategy.fundStrategy(1e6, 0);
    }

    function test_fund_failWhenPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.fundStrategy(1e6, 0);
    }

    function test_fund_failIfNotStrategyManager() external {
        globals.__setIsInstanceOf(false);

        vm.expectRevert("MS:NOT_MANAGER");
        strategy.fundStrategy(1e6, 0);
    }

    function test_fund_failIfInactive() external {
        basicStrategy.__setStrategyState(StrategyState.Inactive);

        vm.expectRevert("MS:NOT_ACTIVE");
        strategy.fundStrategy(1e6, 0);
    }

    function test_fund_failIfImpaired() external {
        basicStrategy.__setStrategyState(StrategyState.Impaired);

        vm.expectRevert("MS:NOT_ACTIVE");
        strategy.fundStrategy(1e6, 0);
    }

    function test_fund_failInvalidStrategyVault() external {
        globals.__setIsInstanceOf(false);

        vm.expectRevert("MBS:FS:INVALID_VAULT");
        vm.prank(poolDelegate);
        strategy.fundStrategy(1e6, 0);
    }

    function test_fund_failMinimumSharesOut() external {
        vm.expectRevert("MBS:FS:MIN_SHARES");
        strategy.fundStrategy(1e6, 1e6 + 1);
    }

    function test_fund_successWithPoolDelegate() external {
        vault.__setBalanceOf(address(strategy), 1e6);
        vault.__setExchangeRate(1);

        vm.expectEmit();
        emit StrategyFunded(1e6, 1e6);

        vm.expectCall(
            address(poolManager),
            abi.encodeCall(IPoolManagerLike.requestFunds, (address(strategy), 1e6))
        );

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.deposit, (1e6, address(strategy)))
        );


        vm.prank(poolDelegate);
        strategy.fundStrategy(1e6, 0);

        assertEq(strategy.lastRecordedTotalAssets(), 1e6);
    }

    function test_fund_successWithStrategyManager() external {
        assertEq(globals.isInstanceOf("STRATEGY_MANAGER", strategyManager), true);

        vault.__setBalanceOf(address(strategy), 1e6);
        vault.__setExchangeRate(1);

        vm.expectEmit();
        emit StrategyFunded(1e6, 1e6);

        vm.expectCall(
            address(poolManager),
            abi.encodeCall(IPoolManagerLike.requestFunds, (address(strategy), 1e6))
        );

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.deposit, (1e6, address(strategy)))
        );

        vm.prank(strategyManager);
        strategy.fundStrategy(1e6, 0);

        assertEq(strategy.lastRecordedTotalAssets(), 1e6);
    }

}

contract MapleBasicStrategyWithdrawFromStrategyTests is BasicStrategyTestBase {

    uint256 assetsOut   = 1e6;
    uint256 totalAssets = 100e6;

    MapleBasicStrategyHarness basicStrategy;

    function setUp() public override {
        super.setUp();

        vm.etch(address(strategy), address(new MapleBasicStrategyHarness()).code);

        basicStrategy = MapleBasicStrategyHarness(address(strategy));

        basicStrategy.__setLastRecordedTotalAssets(totalAssets);
        vault.__setBalanceOf(address(strategy), totalAssets);
        vault.__setExchangeRate(1);
    }

    function test_withdrawFromStrategy_failReentrancy() external {
        vm.etch(address(strategy), address(new MapleBasicStrategyHarness()).code);

        MapleBasicStrategyHarness(address(strategy)).__setLocked(2);

        vm.expectRevert("MS:LOCKED");
        strategy.withdrawFromStrategy(assetsOut, type(uint256).max);
    }

    function test_withdrawFromStrategy_failWhenPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.withdrawFromStrategy(assetsOut, type(uint256).max);
    }

    function test_withdrawFromStrategy_failIfNotStrategyManager() external {
        globals.__setIsInstanceOf(false);

        vm.expectRevert("MS:NOT_MANAGER");
        strategy.withdrawFromStrategy(assetsOut, type(uint256).max);
    }

    function test_withdrawFromStrategy_failIfZeroAssets() external {
        vm.expectRevert("MBS:WFS:ZERO_ASSETS");
        strategy.withdrawFromStrategy(0, type(uint256).max);
    }

    function test_withdrawFromStrategy_failIfLowAssets() external {
        vault.__setBalanceOf(address(strategy), totalAssets);

        vm.prank(strategyManager);
        vm.expectRevert("MBS:WFS:LOW_ASSETS");
        strategy.withdrawFromStrategy(totalAssets + 1, type(uint256).max);
    }

    function test_withdrawFromStrategy_failIfSlippage() external {
        vault.__setBalanceOf(address(strategy), totalAssets);

        vm.prank(strategyManager);
        vm.expectRevert("MBS:WFS:SLIPPAGE");
        strategy.withdrawFromStrategy(totalAssets, 0);
    }

    function test_withdrawFromStrategy_successWithPoolDelegate() external {
        vm.expectEmit();
        emit StrategyWithdrawal(assetsOut, assetsOut);

        vm.expectCall(
            address(globals),
            abi.encodeCall(IGlobalsLike.isFunctionPaused, (IMapleBasicStrategy.withdrawFromStrategy.selector))
        );

        vm.expectCall(
            address(poolManager),
            abi.encodeCall(IPoolManagerLike.poolDelegate, ())
        );

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (totalAssets))
        );

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.withdraw, (assetsOut, address(pool), address(strategy)))
        );

        vm.prank(poolDelegate);
        strategy.withdrawFromStrategy(assetsOut, type(uint256).max);

        assertEq(strategy.lastRecordedTotalAssets(), basicStrategy.__currentTotalAssets());
    }

    function test_withdrawFromStrategy_successWithStrategyManager() external {
        vm.expectEmit();
        emit StrategyWithdrawal(assetsOut, assetsOut);

        vm.expectCall(
            address(globals),
            abi.encodeCall(IGlobalsLike.isFunctionPaused, (IMapleBasicStrategy.withdrawFromStrategy.selector))
        );

        vm.expectCall(
            address(globals),
            abi.encodeCall(IGlobalsLike.isInstanceOf, ("STRATEGY_MANAGER", strategyManager))
        );

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (totalAssets))
        );

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.withdraw, (assetsOut, address(pool), address(strategy)))
        );

        vm.prank(strategyManager);
        strategy.withdrawFromStrategy(assetsOut, type(uint256).max);

        assertEq(strategy.lastRecordedTotalAssets(), basicStrategy.__currentTotalAssets());
    }

    function test_withdrawFromStrategy_successWhenImpaired() external {
        basicStrategy.__setStrategyState(StrategyState.Impaired);

        vm.expectEmit();
        emit StrategyWithdrawal(assetsOut, assetsOut);

        vm.expectCall(
            address(globals),
            abi.encodeCall(IGlobalsLike.isFunctionPaused, (IMapleBasicStrategy.withdrawFromStrategy.selector))
        );

        vm.expectCall(
            address(globals),
            abi.encodeCall(IGlobalsLike.isInstanceOf, ("STRATEGY_MANAGER", strategyManager))
        );

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.withdraw, (assetsOut, address(pool), address(strategy)))
        );

        vm.prank(strategyManager);
        strategy.withdrawFromStrategy(assetsOut, type(uint256).max);

        assertEq(strategy.lastRecordedTotalAssets(), totalAssets);
    }

    function test_withdrawFromStrategy_successWhenInactive() external {
        basicStrategy.__setStrategyState(StrategyState.Inactive);

        vm.expectEmit();
        emit StrategyWithdrawal(assetsOut, assetsOut);

        vm.expectCall(
            address(globals),
            abi.encodeCall(IGlobalsLike.isFunctionPaused, (IMapleBasicStrategy.withdrawFromStrategy.selector))
        );

        vm.expectCall(
            address(globals),
            abi.encodeCall(IGlobalsLike.isInstanceOf, ("STRATEGY_MANAGER", strategyManager))
        );

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.withdraw, (assetsOut, address(pool), address(strategy)))
        );

        vm.prank(strategyManager);
        strategy.withdrawFromStrategy(assetsOut, type(uint256).max);

        assertEq(strategy.lastRecordedTotalAssets(), totalAssets);
    }

}

// TODO: Do these tests make sense post refactor as the accrueFees function doesn't change lastRecordedTotalAssets?
contract MapleBasicStrategyAccrueFeesTests is BasicStrategyTestBase {

    MapleBasicStrategyHarness basicStrategy;

    function setUp() public override {
        super.setUp();
        vm.etch(address(strategy), address(new MapleBasicStrategyHarness()).code);

        basicStrategy = MapleBasicStrategyHarness(address(strategy));

        basicStrategy.__setStrategyFeeRate(1500);  // 15 basis points
    }

    function test_accrueFees_zeroStrategyFeeRateAndNoChangeInTotalAssets() external {
        basicStrategy.__setStrategyFeeRate(0);

        assertEq(basicStrategy.strategyFeeRate(),         0);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 0);

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (0))
        );

        basicStrategy.__accrueFees(address(vault));

        assertEq(basicStrategy.strategyFeeRate(),         0);
    }

    function test_accrueFees_totalAssetsDecreased() external {
        basicStrategy.__setLastRecordedTotalAssets(1e6);

        assertEq(currentTotalAssets(),                    0);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 1e6);
        assertEq(basicStrategy.strategyFeeRate(),         1500);

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (0))
        );

        basicStrategy.__accrueFees(address(vault));

        assertEq(basicStrategy.strategyFeeRate(),         1500);
        assertEq(currentTotalAssets(),                    0);
    }

    function test_accrueFees_zeroStrategyFeeRate_totalAssetsUnchanged() external {
        basicStrategy.__setLastRecordedTotalAssets(1e6);
        basicStrategy.__setStrategyFeeRate(0);

        vault.__setBalanceOf(address(basicStrategy), 1e6);
        vault.__setExchangeRate(1);

        assertEq(currentTotalAssets(),                    1e6);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 1e6);
        assertEq(basicStrategy.strategyFeeRate(),         0);

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (1e6))
        );

        basicStrategy.__accrueFees(address(vault));

        assertEq(basicStrategy.strategyFeeRate(),         0);
        assertEq(currentTotalAssets(),                    1e6);
    }

    function test_accrueFees_zeroStrategyFeeRate_totalAssetsIncreased() external {
        basicStrategy.__setStrategyFeeRate(0);

        vault.__setBalanceOf(address(basicStrategy), 1e6);
        vault.__setExchangeRate(1);

        assertEq(currentTotalAssets(),                    1e6);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 0);
        assertEq(basicStrategy.strategyFeeRate(),         0);

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (1e6))
        );

        basicStrategy.__accrueFees(address(vault));

        assertEq(basicStrategy.strategyFeeRate(),         0);
        assertEq(currentTotalAssets(),                    1e6);
    }

    function test_accrueFees_strategyFeeRoundedDown() external {
        basicStrategy.__setLastRecordedTotalAssets(100);

        vault.__setBalanceOf(address(basicStrategy), 101);
        vault.__setExchangeRate(1);

        assertEq(basicStrategy.strategyFeeRate(),         1500);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 100);
        assertEq(currentTotalAssets(),                    101);

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (101))
        );

        basicStrategy.__accrueFees(address(vault));
    }

    function test_accrueFees_strategyFeeOneHundredPercent() external {
        basicStrategy.__setLastRecordedTotalAssets(100);
        basicStrategy.__setStrategyFeeRate(1e6);

        vault.__setBalanceOf(address(basicStrategy), 101);
        vault.__setExchangeRate(1);

        assertEq(basicStrategy.strategyFeeRate(),         1e6);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 100);
        assertEq(currentTotalAssets(),                    101);

        vm.expectEmit();
        emit StrategyFeesCollected(1);

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (101))
        );

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.withdraw, (1, treasury, address(basicStrategy)))
        );

        basicStrategy.__accrueFees(address(vault));
    }

    function test_accrueFees_totalAssetsIncreased() external {
        basicStrategy.__setLastRecordedTotalAssets(1e6);

        vault.__setBalanceOf(address(basicStrategy), 3e6);
        vault.__setExchangeRate(1);

        assertEq(currentTotalAssets(),                    3e6);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 1e6);
        assertEq(basicStrategy.strategyFeeRate(),         1500);

        uint256 strategyFee = ((3e6 - 1e6) * 1500) / 1e6;

        vm.expectEmit();
        emit StrategyFeesCollected(strategyFee);

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (3e6))
        );

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.withdraw, (strategyFee, treasury, address(basicStrategy)))
        );

        basicStrategy.__accrueFees(address(vault));

        assertEq(basicStrategy.strategyFeeRate(),         1500);
    }

}

contract MapleBasicStrategySetStrategyFeeRateTests is BasicStrategyTestBase {

    uint256 public constant HUNDRED_PERCENT = 1e6;  // 100.0000%

    MapleBasicStrategyHarness basicStrategy;

    function setUp() public override {
        super.setUp();
        vm.etch(address(strategy), address(new MapleBasicStrategyHarness()).code);

        basicStrategy = MapleBasicStrategyHarness(address(strategy));
    }

    function test_setStrategyFeeRate_failReentrancy() external {
        basicStrategy.__setLocked(2);

        vm.expectRevert("MS:LOCKED");
        strategy.setStrategyFeeRate(1500);
    }

    function test_setStrategyFeeRate_failWhenPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.setStrategyFeeRate(1500);
    }

    function test_setStrategyFeeRate_failIfNotProtocolAdmin() external {
        vm.expectRevert("MS:NOT_ADMIN");
        strategy.setStrategyFeeRate(1500);

        vm.prank(poolDelegate);
        strategy.setStrategyFeeRate(1500);

        vm.prank(governor);
        strategy.setStrategyFeeRate(1500);

        vm.prank(operationalAdmin);
        strategy.setStrategyFeeRate(1500);
    }

    function test_setStrategyFeeRate_failIfInactive() external {
        basicStrategy.__setStrategyState(StrategyState.Inactive);

        vm.prank(poolDelegate);
        vm.expectRevert("MS:NOT_ACTIVE");
        strategy.setStrategyFeeRate(1500);
    }

    function test_setStrategyFeeRate_failIfImpaired() external {
        basicStrategy.__setStrategyState(StrategyState.Impaired);

        vm.prank(poolDelegate);
        vm.expectRevert("MS:NOT_ACTIVE");
        strategy.setStrategyFeeRate(1500);
    }

    function test_setStrategyFeeRate_failInvalidStrategyFeeRate() external {
        vm.expectRevert("MBS:SSFR:INVALID_FEE_RATE");
        vm.prank(poolDelegate);
        strategy.setStrategyFeeRate(HUNDRED_PERCENT + 1);
    }

    function test_setStrategyFeeRate_zeroPriorFeeRateAndTotalAssets() external {
        assertEq(basicStrategy.strategyFeeRate(),         0);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 0);

        vm.expectEmit();
        emit StrategyFeeRateSet(1500);

        vm.prank(poolDelegate);
        basicStrategy.setStrategyFeeRate(1500);

        assertEq(basicStrategy.strategyFeeRate(),         1500);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 0);
    }

    function test_setStrategyFeeRate_zeroPriorFeeRate_totalAssetsIncreased() external {
        // Equivalent of a fundStrategy call prior to a fee being set.
        vault.__setBalanceOf(address(basicStrategy), 1e6);
        vault.__setExchangeRate(1);

        assertEq(basicStrategy.strategyFeeRate(),         0);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 0);
        assertEq(currentTotalAssets(),                    1e6);

        vm.expectEmit();
        emit StrategyFeeRateSet(1500);

        vm.prank(poolDelegate);
        basicStrategy.setStrategyFeeRate(1500);

        assertEq(basicStrategy.strategyFeeRate(),         1500);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 1e6);
    }

    function test_setStrategyFeeRate_nonZeroPriorFeeRate_totalAssetsIncreased() external {
        basicStrategy.__setStrategyFeeRate(1000);
        basicStrategy.__setLastRecordedTotalAssets(1e6);

        vault.__setBalanceOf(address(basicStrategy), 3e6);
        vault.__setExchangeRate(1);

        assertEq(basicStrategy.strategyFeeRate(),         1000);
        assertEq(basicStrategy.lastRecordedTotalAssets(), 1e6);
        assertEq(currentTotalAssets(),                    3e6);

        uint256 strategyFee = ((3e6 - 1e6) * 1000) / 1e6;

        vm.expectEmit();
        emit StrategyFeesCollected(strategyFee);

        vm.expectEmit();
        emit StrategyFeeRateSet(1500);

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.previewRedeem, (3e6))
        );

        vm.expectCall(
            address(vault),
            abi.encodeCall(IERC4626Like.withdraw, (strategyFee, treasury, address(basicStrategy)))
        );

        vm.prank(poolDelegate);
        basicStrategy.setStrategyFeeRate(1500);

        assertEq(basicStrategy.strategyFeeRate(), 1500);
    }

}

contract MapleBasicStrategyDeactivateStrategyTests is BasicStrategyTestBase {

    MapleBasicStrategyHarness basicStrategy;

    function setUp() public override {
        super.setUp();
        vm.etch(address(strategy), address(new MapleBasicStrategyHarness()).code);

        basicStrategy = MapleBasicStrategyHarness(address(strategy));
    }

    function test_deactivateStrategy_failReentrancy() external {
        basicStrategy.__setLocked(2);

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

        basicStrategy.__setStrategyState(StrategyState.Active);

        vm.prank(governor);
        strategy.deactivateStrategy();

        basicStrategy.__setStrategyState(StrategyState.Active);

        vm.prank(operationalAdmin);
        strategy.deactivateStrategy();
    }

    function test_deactivateStrategy_failIfAlreadyInactive() external {
        basicStrategy.__setStrategyState(StrategyState.Inactive);

        vm.prank(poolDelegate);
        vm.expectRevert("MBS:DS:ALREADY_INACTIVE");
        strategy.deactivateStrategy();
    }

    function test_deactivateStrategy_successWhenActive() external {
        basicStrategy.__setStrategyState(StrategyState.Active);

        vm.expectEmit();
        emit StrategyDeactivated();

        vm.prank(poolDelegate);
        strategy.deactivateStrategy();

        assertEq(uint256(strategy.strategyState()), uint256(StrategyState.Inactive));
    }

    function test_deactivateStrategy_successWhenImpaired() external {
        basicStrategy.__setStrategyState(StrategyState.Impaired);

        vm.expectEmit();
        emit StrategyDeactivated();

        vm.prank(poolDelegate);
        strategy.deactivateStrategy();

        assertEq(uint256(strategy.strategyState()), uint256(StrategyState.Inactive));
    }

}

contract MapleBasicStrategyImpairStrategyTests is BasicStrategyTestBase {

    MapleBasicStrategyHarness basicStrategy;

    function setUp() public override {
        super.setUp();
        vm.etch(address(strategy), address(new MapleBasicStrategyHarness()).code);

        basicStrategy = MapleBasicStrategyHarness(address(strategy));
    }

    function test_impairStrategy_failReentrancy() external {
        basicStrategy.__setLocked(2);

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

        basicStrategy.__setStrategyState(StrategyState.Active);

        vm.prank(governor);
        strategy.impairStrategy();

        basicStrategy.__setStrategyState(StrategyState.Active);

        vm.prank(operationalAdmin);
        strategy.impairStrategy();
    }

    function test_impairStrategy_failIfAlreadyImpaired() external {
        basicStrategy.__setStrategyState(StrategyState.Impaired);

        vm.prank(poolDelegate);
        vm.expectRevert("MBS:IS:ALREADY_IMPAIRED");
        strategy.impairStrategy();
    }

    function test_impairStrategy_successWhenActive() external {
        basicStrategy.__setStrategyState(StrategyState.Active);

        vm.expectEmit();
        emit StrategyImpaired();

        vm.prank(poolDelegate);
        strategy.impairStrategy();

        assertEq(uint256(strategy.strategyState()), uint256(StrategyState.Impaired));
    }

    function test_impairStrategy_successWhenInactive() external {
        basicStrategy.__setStrategyState(StrategyState.Inactive);

        vm.expectEmit();
        emit StrategyImpaired();

        vm.prank(poolDelegate);
        strategy.impairStrategy();

        assertEq(uint256(strategy.strategyState()), uint256(StrategyState.Impaired));
    }

}

contract MapleBasicStrategyReactivateStrategyTests is BasicStrategyTestBase {

    MapleBasicStrategyHarness basicStrategy;

    uint256 currentVaultBalance  = 1337e6;
    uint256 previousVaultBalance = 420e6;

    function setUp() public override {
        super.setUp();
        vm.etch(address(strategy), address(new MapleBasicStrategyHarness()).code);

        basicStrategy = MapleBasicStrategyHarness(address(strategy));

        basicStrategy.__setLastRecordedTotalAssets(previousVaultBalance);
        basicStrategy.__setStrategyState(StrategyState.Inactive);

        vault.__setBalanceOf(address(basicStrategy), currentVaultBalance);
        vault.__setExchangeRate(1);
    }

    function test_reactivateStrategy_failReentrancy() external {
        basicStrategy.__setLocked(2);

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

        basicStrategy.__setStrategyState(StrategyState.Inactive);

        vm.prank(governor);
        strategy.reactivateStrategy(false);

        basicStrategy.__setStrategyState(StrategyState.Inactive);

        vm.prank(operationalAdmin);
        strategy.reactivateStrategy(false);
    }

    function test_reactivateStrategy_failIfAlreadyActive() external {
        basicStrategy.__setStrategyState(StrategyState.Active);

        vm.prank(poolDelegate);
        vm.expectRevert("MBS:RS:ALREADY_ACTIVE");
        strategy.reactivateStrategy(false);
    }

    function test_reactivateStrategy_successWhenInactive_withoutAccountingUpdate() external {
        basicStrategy.__setStrategyState(StrategyState.Inactive);

        vm.expectEmit();
        emit StrategyReactivated(false);

        vm.prank(poolDelegate);
        strategy.reactivateStrategy(false);

        assertEq(strategy.lastRecordedTotalAssets(), previousVaultBalance);
        assertEq(uint256(strategy.strategyState()),  uint256(StrategyState.Active));
    }

    function test_reactivateStrategy_successWhenInactive_withAccountingUpdate() external {
        basicStrategy.__setStrategyState(StrategyState.Inactive);

        vm.expectEmit();
        emit StrategyReactivated(true);

        vm.prank(poolDelegate);
        strategy.reactivateStrategy(true);

        assertEq(strategy.lastRecordedTotalAssets(), currentVaultBalance);
        assertEq(uint256(strategy.strategyState()),  uint256(StrategyState.Active));
    }

    function test_reactivateStrategy_successWhenImpaired_withoutAccountingUpdate() external {
        basicStrategy.__setStrategyState(StrategyState.Impaired);

        vm.expectEmit();
        emit StrategyReactivated(false);

        vm.prank(poolDelegate);
        strategy.reactivateStrategy(false);

        assertEq(strategy.lastRecordedTotalAssets(), previousVaultBalance);
        assertEq(uint256(strategy.strategyState()),  uint256(StrategyState.Active));
    }

    function test_reactivateStrategy_successWhenImpaired_withAccountingUpdate() external {
        basicStrategy.__setStrategyState(StrategyState.Impaired);

        vm.expectEmit();
        emit StrategyReactivated(true);

        vm.prank(poolDelegate);
        strategy.reactivateStrategy(true);

        assertEq(strategy.lastRecordedTotalAssets(), currentVaultBalance);
        assertEq(uint256(strategy.strategyState()),  uint256(StrategyState.Active));
    }

}
