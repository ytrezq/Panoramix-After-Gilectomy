// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { RateBasedCorrelatedAssetsPriceOracle } from "../RateBasedCorrelatedAssetsPriceOracle.sol";

import { SimplePriceFeed } from "./SimplePriceFeed.sol";
import { MockRateProvider } from "./MockRateProvider.sol";
import { PriceCapAdapterBase } from "../utils/PriceCapAdapterBase.sol";

contract RateBasedCorrelatedAssetsPriceOracleTest is Test {
    address manager;

    SimplePriceFeed baseFeed;
    MockRateProvider rateProv;
    RateBasedCorrelatedAssetsPriceOracle capo;

    function setUp() public {
        manager = makeAddr("manager");
    }

    function _deployFeeds(uint8 baseDecimals, uint8 outDecimals, int256 priceA, int256 rate, uint48 minDelay, uint32 maxGrowth) internal {
        baseFeed = new SimplePriceFeed(priceA, baseDecimals);
        rateProv = new MockRateProvider(uint256(rate));

        vm.warp(block.timestamp + (minDelay * 2));
        vm.roll(block.number + 1);

        PriceCapAdapterBase.PriceCapSnapshot memory snap = PriceCapAdapterBase.PriceCapSnapshot({
            snapshotRatio: uint256(rate),
            snapshotTimestamp: uint48(block.timestamp - minDelay),
            maxYearlyRatioGrowthPercent: maxGrowth
        });

        capo = new RateBasedCorrelatedAssetsPriceOracle(
            manager,
            AggregatorV3Interface(address(baseFeed)),
            address(rateProv),
            AggregatorV3Interface(address(0)),
            "Rate-Based CAPO",
            outDecimals,
            minDelay,
            18,
            snap
        );
    }

    function _boundInputs(
        uint8 baseDecimals,
        uint8 outDecimals,
        int256 priceA,
        int256 rate,
        uint48 minDelay,
        uint32 maxGrowth,
        uint256 dt
    ) internal pure returns (uint8, uint8, int256, int256, uint48, uint32, uint256) {
        baseDecimals = uint8(bound(baseDecimals, 6, 18));
        outDecimals = uint8(bound(outDecimals, 6, 18));

        priceA = int256(bound(uint256(priceA), 10 ** (baseDecimals - 2), 100_000 * 10 ** baseDecimals));
        rate = int256(bound(uint256(rate), 10 ** 16, 100_000 * 1e18));

        minDelay = uint48(bound(minDelay, 1 hours, 10 days));
        maxGrowth = uint32(bound(maxGrowth, 100, 2_000_00));
        dt = bound(dt, 60 days, 365 days * 3);

        return (baseDecimals, outDecimals, priceA, rate, minDelay, maxGrowth, dt);
    }

    function testFuzz_latestRoundData_exactGrowth(
        uint8 baseDec,
        uint8 outDec,
        int256 priceA,
        int256 rate,
        uint48 minDelay,
        uint32 maxGrowth,
        uint256 dt
    ) public {
        (baseDec, outDec, priceA, rate, minDelay, maxGrowth, dt) = _boundInputs(baseDec, outDec, priceA, rate, minDelay, maxGrowth, dt);

        _deployFeeds(baseDec, outDec, priceA, rate, minDelay, maxGrowth);

        vm.warp(block.timestamp + dt);
        vm.roll(block.number + 1);

        int256 expectedRate = rate + (rate * int32(maxGrowth) * int256(dt)) / 365 days / 1e4;

        rateProv.setRate(uint256(expectedRate));

        int256 onChainRate = capo.getRatio();
        assertEq(onChainRate, expectedRate, "ratio exact growth");

        (, int256 answer, , , ) = capo.latestRoundData();

        uint256 expectedPrice = (uint256(expectedRate) * uint256(priceA)) / 1e18;

        if (outDec > baseDec) expectedPrice *= 10 ** (outDec - baseDec);
        else expectedPrice /= 10 ** (baseDec - outDec);

        assertEq(uint256(answer), expectedPrice, "price exact growth");
        assertTrue(!capo.isCapped(), "should NOT be capped");
    }

    function testFuzz_latestRoundData_growthExceeds(
        uint8 baseDec,
        uint8 outDec,
        int256 priceA,
        int256 rate,
        uint48 minDelay,
        uint32 maxGrowth,
        uint256 dt
    ) public {
        (baseDec, outDec, priceA, rate, minDelay, maxGrowth, dt) = _boundInputs(baseDec, outDec, priceA, rate, minDelay, maxGrowth, dt);

        _deployFeeds(baseDec, outDec, priceA, rate, minDelay, maxGrowth);

        vm.warp(block.timestamp + dt);
        vm.roll(block.number + 1);

        int256 tooHigh = rate + (rate * int32(maxGrowth * 2) * int256(dt)) / 365 days / 1e4;

        rateProv.setRate(uint256(tooHigh));

        assertTrue(capo.isCapped(), "should be capped");

        (, int256 cappedPrice, , , ) = capo.latestRoundData();

        uint256 raw = (uint256(tooHigh) * uint256(priceA)) / 1e18;

        if (outDec > baseDec) raw *= 10 ** (outDec - baseDec);
        else raw /= 10 ** (baseDec - outDec);
        vm.assume(raw > uint256(cappedPrice));
        assertGt(raw, uint256(cappedPrice), "capped price must be lower");
    }

    function testFuzz_latestRoundData_growthNotExceeds(
        uint8 baseDec,
        uint8 outDec,
        int256 priceA,
        int256 rate,
        uint48 minDelay,
        uint32 maxGrowth,
        uint256 dt
    ) public {
        (baseDec, outDec, priceA, rate, minDelay, maxGrowth, dt) = _boundInputs(baseDec, outDec, priceA, rate, minDelay, maxGrowth, dt);

        _deployFeeds(baseDec, outDec, priceA, rate, minDelay, maxGrowth);

        vm.warp(block.timestamp + dt);
        vm.roll(block.number + 1);

        int256 within = rate + (rate * int32(maxGrowth / 2) * int256(dt)) / 365 days / 1e4;

        rateProv.setRate(uint256(within));

        assertTrue(!capo.isCapped(), "should NOT be capped");

        int256 onChainRate = capo.getRatio();
        assertEq(onChainRate, within, "ratio not-capped match");
    }
}
