// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Test, Vm } from "../../modules/forge-std/src/Test.sol";

import { IERC20Like, IPoolLike } from "../../contracts/interfaces/Interfaces.sol";

import { SyrupUserActions } from "../../contracts/SyrupUserActions.sol";

import {
    IBalancerVaultLike,
    IPotLike,
    IPSMLike,
    ISDaiLike
} from "../utils/Interfaces.sol";

contract ScenarioTestBase is Test {

    address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant CSP            = 0x48a5bFB5bd44345Db0B31FA4b5a204890695C9B4;
    address constant DAI            = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant GEM_JOIN       = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
    address constant PSM            = 0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A;
    address constant SDAI           = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address constant SYRUP_USDC     = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;
    address constant USDC           = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WARD           = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

    address constant CSP_SOURCE        = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant DAI_SOURCE        = 0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf;
    address constant SDAI_SOURCE       = 0x4C612E3B15b96Ff9A6faED838F8d07d479a8dD4c;
    address constant SYRUP_USDC_SOURCE = 0xAdA1fc89b42F15A1Ce5395456CF4E0A90A9e8EfE;
    address constant USDC_SOURCE       = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;

    bytes32 constant POOL_ID = 0x48a5bfb5bd44345db0b31fa4b5a204890695c9b4000000000000000000000697;

    uint256 expectedUsdcOut;
    uint256 syrupUsdcIn;

    Vm.Wallet account = vm.createWallet("account");

    IERC20Like dai       = IERC20Like(DAI);
    IERC20Like sdai      = IERC20Like(SDAI);
    IERC20Like syrupUsdc = IPoolLike(SYRUP_USDC);
    IERC20Like usdc      = IERC20Like(USDC);

    IBalancerVaultLike vault = IBalancerVaultLike(BALANCER_VAULT);

    SyrupUserActions actions;

    function setUp() external {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 20184000);

        syrupUsdcIn     = 1_000e6;
        expectedUsdcOut = IPoolLike(SYRUP_USDC).convertToExitAssets(syrupUsdcIn);

        actions = new SyrupUserActions(DAI, PSM, SDAI, SYRUP_USDC, POOL_ID);
    }

    function burnPsmLiquidity() internal {
        uint256 liquidity = IERC20Like(USDC).balanceOf(GEM_JOIN);

        // Burn all of the USDC in the `gemJoin` contract.
        vm.prank(GEM_JOIN);
        IERC20Like(USDC).transfer(address(1), liquidity);
    }

    function burnSyrupLiquidity(uint256 amountToBurn) internal {
        uint256 liquidity = IERC20Like(USDC).balanceOf(SYRUP_USDC);

        require(amountToBurn <= liquidity, "TEST:INSUFFICIENT_LIQUIDITY");

        vm.prank(SYRUP_USDC);
        IERC20Like(USDC).transfer(address(1), amountToBurn);
    }

    function increaseDaiExchangeRate(uint256 timespan) internal {
        vm.warp(block.timestamp + timespan);
    }

    function mintSyrupUsdc(address target, uint256 amount) internal {
        vm.prank(SYRUP_USDC_SOURCE);
        IERC20Like(SYRUP_USDC).transfer(target, amount);
    }

    function mintUsdc(address target, uint256 amount) internal {
        vm.prank(USDC_SOURCE);
        IERC20Like(USDC).transfer(target, amount);
    }

    // Value of 1e18 is equivalent to a 100% fee.
    function setTout(uint256 amount) internal {
        vm.prank(WARD);
        IPSMLike(PSM).file("tout", amount);
    }

    function swapToUsdc(address actor, uint256 syrupIn, uint256 minUsdcOut) internal returns (uint256 usdcOut) {
        mintSyrupUsdc(actor, syrupIn);

        vm.prank(actor);
        syrupUsdc.approve(address(actions), syrupIn);

        vm.prank(actor);
        usdcOut = actions.swapToUsdc(syrupIn, minUsdcOut, block.timestamp, actor);
    }

    function updateBalancerLiquidity(address asset, int256 amount) internal {
        require(asset == SYRUP_USDC || asset == SDAI, "TEST:UBL:INVALID_ASSET");

        if (amount == 0) return;

        address source = CSP_SOURCE;

        if (amount > 0) {
            source = asset == SYRUP_USDC ? SYRUP_USDC_SOURCE : SDAI_SOURCE;
        }

        // TODO: Add require to prevent unsafe casts.
        uint256 absAmount = uint256(amount > 0 ? amount : amount * -1);

        if (amount < 0 && asset == SYRUP_USDC) {
            absAmount *= 1e12;
        }

        IBalancerVaultLike.FundManagement memory funds = IBalancerVaultLike.FundManagement({
            sender:              address(source),
            fromInternalBalance: false,
            recipient:           address(source),
            toInternalBalance:   false
        });

        IBalancerVaultLike.SingleSwap memory swap = IBalancerVaultLike.SingleSwap({
            poolId:   POOL_ID,
            kind:     IBalancerVaultLike.SwapKind.GIVEN_IN,
            assetIn:  amount > 0 ? asset : CSP,
            assetOut: amount > 0 ? CSP   : asset,
            amount:   absAmount,
            userData: new bytes(0)
        });

        vm.prank(source);
        IERC20Like(source == CSP_SOURCE ? CSP : asset).approve(BALANCER_VAULT, absAmount);

        vm.prank(source);
        IBalancerVaultLike(BALANCER_VAULT).swap({
            singleSwap: swap,
            funds:      funds,
            limit:      0,
            deadline:   block.timestamp
        });
    }

}

contract SyrupUserActionsScenarioTests is ScenarioTestBase {

    function testScenario_swapDeadlineHasPassed() external {
        mintSyrupUsdc(address(account.addr), syrupUsdcIn);

        vm.prank(account.addr);
        syrupUsdc.approve(address(actions), syrupUsdcIn);

        uint256 priorTimestamp = block.timestamp;

        vm.warp(priorTimestamp + 1 days);

        vm.expectRevert("BAL#508");  // Error code for swap deadline https://docs.balancer.fi/reference/contracts/error-codes.html#vault
        vm.prank(account.addr);
        actions.swapToUsdc(syrupUsdcIn, 100e6, priorTimestamp, account.addr);
    }

    function test_scenario_insufficientSlippage() external {
        // Update Balancer Liquidity
        updateBalancerLiquidity(SYRUP_USDC, 100_000e6);
        updateBalancerLiquidity(SDAI,       100_000e18);

        mintSyrupUsdc(account.addr, syrupUsdcIn);

        vm.prank(account.addr);
        syrupUsdc.approve(address(actions), syrupUsdcIn);

        // Revert expected due to balancer fees
        vm.prank(account.addr);
        vm.expectRevert("SUA:S:INSUFFICIENT_AMOUNT_OUT");
        uint256 usdcOut = actions.swapToUsdc(syrupUsdcIn, expectedUsdcOut, block.timestamp, account.addr);

        // Allow for 1% slippage.
        uint256 adjustedUsdcOut = expectedUsdcOut * 0.99e18 / 1e18;

        vm.prank(account.addr);
        usdcOut = actions.swapToUsdc(syrupUsdcIn, adjustedUsdcOut, block.timestamp, account.addr);

        assertGt(usdcOut, adjustedUsdcOut);
    }

    function test_scenario_syrupUsdcExchangeRateReduced() external {
        // Update Balancer Liquidity
        updateBalancerLiquidity(SYRUP_USDC, 1_000_000e6);
        updateBalancerLiquidity(SDAI,       1_000_000e18);

        uint256 usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 0.1% less than expected.
        assertEq(usdcOut, 1001_998441);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.001e18);

        burnSyrupLiquidity(500_000e6);

        uint256 newExpectedUsdcOut = IPoolLike(SYRUP_USDC).convertToExitAssets(syrupUsdcIn);

        // SyrupUSDC is worth ~13% less than before.
        assertEq(newExpectedUsdcOut, 893_555624);
        assertApproxEqRel(newExpectedUsdcOut, expectedUsdcOut, 0.13e18);

        usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is the same as before.
        assertEq(usdcOut, 1001_994575);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.001e18);

        // TODO: Have test with forcing a cache update.
        // NOTE: Either the pool needs to be manually pinged to update the rate or we wait for the cache duration (4 hours).
        vm.warp(block.timestamp + 4 hours);

        usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 13% less than expected.
        assertEq(usdcOut, 893_060038);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.13e18);
    }

    function test_scenario_mixedBalancerPoolCompositions() external {
        // Update Balancer Liquidity
        updateBalancerLiquidity(SYRUP_USDC, 100_000e6);
        updateBalancerLiquidity(SDAI,       100_000e18);

        uint256 usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 0.1% less than expected.
        assertEq(usdcOut, 1001_981162);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.001e18);

        // Update Balancer Liquidity to add more SyrupUSDC.
        updateBalancerLiquidity(SYRUP_USDC, 900_000e6);

        usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 2.7% less than expected.
        assertEq(usdcOut, 976_548722);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.027e18);

        // Update Balancer Liquidity to remove sDAI
        updateBalancerLiquidity(SDAI, -115_000e18);

        usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 66% less than expected.
        assertEq(usdcOut, 346_277850);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.66e18);

        // Update Balancer Liquidity to have ~ 100x more sDAI
        updateBalancerLiquidity(SYRUP_USDC, -880_000e6);
        updateBalancerLiquidity(SDAI,        10_000_000e18);

        usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 255% higher than expected.
        assertEq(usdcOut, 3551_828902);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 2.55e18);
    }

    function test_scenario_increaseSDaiExchangeRate() external {
        // Update Balancer Liquidity
        updateBalancerLiquidity(SYRUP_USDC, 1_000_000e6);
        updateBalancerLiquidity(SDAI,       1_000_000e18);

        uint256 usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 0.1% less than expected.
        assertEq(usdcOut, 1001_998441);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.001e18);

        // Increase SDAI Exchange Rate.
        increaseDaiExchangeRate(30 days);

        usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 0.69% higher than expected.
        assertEq(usdcOut, 1009_724776);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.0069e18);

        // Increase SDAI Exchange Rate more.
        increaseDaiExchangeRate(180 days);

        usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 5.32% higher than expected.
        assertEq(usdcOut, 1056_103588);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.0532e18);
    }

    function test_scenario_changePSMFee() external {
        // Update Balancer Liquidity
        updateBalancerLiquidity(SYRUP_USDC, 1_000_000e6);
        updateBalancerLiquidity(SDAI,       1_000_000e18);

        uint256 usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 0.1% less than expected.
        assertEq(usdcOut, 1001_998441);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.001e18);

        // Set fee to 50%.
        setTout(0.5e18);

        usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 34% less than expected.
        assertEq(usdcOut, 667_996383);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.34e18);

        // Set fee to 100%.
        setTout(1e18);

        usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 50% less than expected.
        assertEq(usdcOut, 500_995355);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.509e18);

        // Set fee to 200%.
        setTout(2e18);

        usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 67% less than expected.
        assertEq(usdcOut, 333_995616);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.67e18);

        // Set fee to 400%.
        setTout(4e18);

        usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 80% less than expected.
        assertEq(usdcOut, 200_396597);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.801e18);
    }

    function test_scenario_psmIsEmpty() external {
        // Update Balancer Liquidity
        updateBalancerLiquidity(SYRUP_USDC, 100_000e6);
        updateBalancerLiquidity(SDAI,       100_000e18);

        uint256 usdcOut = swapToUsdc(account.addr, syrupUsdcIn, 0);

        // USDC amount is 0.1% less than expected.
        assertEq(usdcOut, 1001_981162);
        assertApproxEqRel(usdcOut, expectedUsdcOut, 0.001e18);

        // Prevent DAI from being swapped for USDC.
        burnPsmLiquidity();

        mintSyrupUsdc(account.addr, syrupUsdcIn);

        vm.prank(account.addr);
        syrupUsdc.approve(address(actions), syrupUsdcIn);

        vm.prank(account.addr);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        usdcOut = actions.swapToUsdc(syrupUsdcIn, 0, block.timestamp, account.addr);
    }

    // NOTE: Purpose of the test is to find edge cases where the contract may revert.
    function test_scenario_fuzzing(
        uint256 syrupUsdcBalanceAdjustment,
        uint256 sdaiBalanceAdjustment,
        uint256 syrupUsdcImpairment,
        uint256 sdaiAccumulationTime,
        uint256 toutValue,
        uint256 syrupUsdcInFuzzed
    )
        external
    {
        // Set Balancer Vault liquidity values.
        syrupUsdcBalanceAdjustment = bound(syrupUsdcBalanceAdjustment, 1e6,  950_000e6);
        sdaiBalanceAdjustment      = bound(sdaiBalanceAdjustment,      1e18, 950_000e18);

        // NOTE: Maximum ratio is roughly 1000:1
        updateBalancerLiquidity(SYRUP_USDC, int256(syrupUsdcBalanceAdjustment));
        updateBalancerLiquidity(SDAI,       int256(sdaiBalanceAdjustment));

        // Set Syrup USDC impairment (by burning cash).
        syrupUsdcImpairment = bound(syrupUsdcImpairment, 0, 500_000e6);

        burnSyrupLiquidity(syrupUsdcImpairment);

        // Accrue value to SDAI.
        sdaiAccumulationTime = bound(sdaiAccumulationTime, 0, 365 days);

        increaseDaiExchangeRate(sdaiAccumulationTime);

        // Set tout fee.
        toutValue = bound(toutValue, 0, 1e18);

        setTout(toutValue);

        // Perform swap.
        syrupUsdcIn = bound(syrupUsdcInFuzzed, 1e6, 50_000e6);

        // NOTE: Slippage can be extremely high.
        swapToUsdc(account.addr, syrupUsdcIn, 0.001e6);
    }

}
