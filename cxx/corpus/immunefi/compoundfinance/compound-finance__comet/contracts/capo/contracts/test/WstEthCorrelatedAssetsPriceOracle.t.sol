// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { WstETHCorrelatedAssetsPriceOracle } from "../WstETHCorrelatedAssetsPriceOracle.sol";
import { PriceCapAdapterBase } from "../utils/PriceCapAdapterBase.sol";

import { SimplePriceFeed } from "./SimplePriceFeed.sol";
import { MockWstETH } from "./MockWstEth.sol";

contract WstEthCorrelatedAssetsPeoceOracleTest is Test {
    address manager;

    SimplePriceFeed baseFeed;
    MockWstETH wsteth;
    WstETHCorrelatedAssetsPriceOracle capo;

    function setUp() public {
        manager = makeAddr("manager");
    }

    function _deploy(uint8 baseDec, uint8 outDec, int256 priceA, int256 ratio, uint48 minDelay, uint32 maxGrowth) internal {
        baseFeed = new SimplePriceFeed(priceA, baseDec);
        wsteth = new MockWstETH(uint256(ratio));

        vm.warp(block.timestamp + minDelay * 2);
        vm.roll(block.number + 1);

        PriceCapAdapterBase.PriceCapSnapshot memory snap = PriceCapAdapterBase.PriceCapSnapshot({
            snapshotRatio: uint256(ratio),
            snapshotTimestamp: uint48(block.timestamp - minDelay),
            maxYearlyRatioGrowthPercent: maxGrowth
        });

        capo = new WstETHCorrelatedAssetsPriceOracle(
            manager,
            AggregatorV3Interface(address(baseFeed)),
            address(wsteth),
            AggregatorV3Interface(address(0)),
            "wstETH CAPO",
            outDec,
            minDelay,
            snap
        );
    }

    function _boundInputs(
        uint8 baseDec,
        uint8 outDec,
        int256 priceA,
        int256 ratio,
        uint48 minDelay,
        uint32 maxGrowth,
        uint256 dt
    ) internal pure returns (uint8, uint8, int256, int256, uint48, uint32, uint256) {
        baseDec = uint8(bound(baseDec, 6, 18));
        outDec = uint8(bound(outDec, 6, 18));

        priceA = int256(bound(uint256(priceA), 10 ** (baseDec - 2), 100_000 * 10 ** baseDec));
        ratio = int256(bound(uint256(ratio), 10 ** (18 - 2), 100_000 * 10 ** 18));

        minDelay = uint48(bound(minDelay, 1 hours, 10 days));
        maxGrowth = uint32(bound(maxGrowth, 100, 2_000_00)); // 1-2000 %
        dt = bound(dt, 60 days, 365 days * 3);

        return (baseDec, outDec, priceA, ratio, minDelay, maxGrowth, dt);
    }

    function testFuzz_exactGrowth(uint8 baseDec, uint8 outDec, int256 priceA, int256 ratio, uint48 minDelay, uint32 maxGrowth, uint256 dt) public {
        (baseDec, outDec, priceA, ratio, minDelay, maxGrowth, dt) = _boundInputs(baseDec, outDec, priceA, ratio, minDelay, maxGrowth, dt);

        _deploy(baseDec, outDec, priceA, ratio, minDelay, maxGrowth);

        vm.warp(block.timestamp + dt);
        vm.roll(block.number + 1);

        int256 expected = ratio + (ratio * int32(maxGrowth) * int256(dt)) / 365 days / 1e4;
        wsteth.setRate(uint256(expected));

        assertEq(capo.getRatio(), expected);

        (, int256 price, , , ) = capo.latestRoundData();
        uint256 expPrice = (uint256(expected) * uint256(priceA)) / 1e18;
        expPrice = outDec > baseDec ? expPrice * 10 ** (outDec - baseDec) : expPrice / 10 ** (baseDec - outDec);

        assertEq(uint256(price), expPrice);
        assertTrue(!capo.isCapped());
    }

    function testFuzz_growthExceeds(uint8 baseDec, uint8 outDec, int256 priceA, int256 ratio, uint48 minDelay, uint32 maxGrowth, uint256 dt) public {
        (baseDec, outDec, priceA, ratio, minDelay, maxGrowth, dt) = _boundInputs(baseDec, outDec, priceA, ratio, minDelay, maxGrowth, dt);

        _deploy(baseDec, outDec, priceA, ratio, minDelay, maxGrowth);

        vm.warp(block.timestamp + dt);
        vm.roll(block.number + 1);

        int256 tooHigh = ratio + (ratio * int32(maxGrowth * 2) * int256(dt)) / 365 days / 1e4;
        wsteth.setRate(uint256(tooHigh));

        assertTrue(capo.isCapped());

        (, int256 capped, , , ) = capo.latestRoundData();
        uint256 raw = (uint256(tooHigh) * uint256(priceA)) / 1e18;
        raw = outDec > baseDec ? raw * 10 ** (outDec - baseDec) : raw / 10 ** (baseDec - outDec);

        vm.assume(raw != uint256(capped));
        assertGt(raw, uint256(capped));
    }

    function testFuzz_growthNotExceeds(
        uint8 baseDec,
        uint8 outDec,
        int256 priceA,
        int256 ratio,
        uint48 minDelay,
        uint32 maxGrowth,
        uint256 dt
    ) public {
        (baseDec, outDec, priceA, ratio, minDelay, maxGrowth, dt) = _boundInputs(baseDec, outDec, priceA, ratio, minDelay, maxGrowth, dt);

        _deploy(baseDec, outDec, priceA, ratio, minDelay, maxGrowth);

        vm.warp(block.timestamp + dt);
        vm.roll(block.number + 1);

        int256 within = ratio + (ratio * int32(maxGrowth / 2) * int256(dt)) / 365 days / 1e4;
        wsteth.setRate(uint256(within));

        assertTrue(!capo.isCapped());
        assertEq(capo.getRatio(), within);
    }
}
