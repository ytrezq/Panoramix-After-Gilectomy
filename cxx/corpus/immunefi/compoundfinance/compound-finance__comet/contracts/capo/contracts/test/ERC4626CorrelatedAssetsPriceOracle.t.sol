// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { ERC4626CorrelatedAssetsPriceOracle } from "../ERC4626CorrelatedAssetsPriceOracle.sol";
import { SimplePriceFeed } from "./SimplePriceFeed.sol";
import { SimpleERC4626RatePriceFeed } from "./SimpleERC4626RatePriceFeed.sol";
import { ERC4626CorrelatedAssetsPriceOracle } from "../ERC4626CorrelatedAssetsPriceOracle.sol";
import { PriceCapAdapterBase } from "../utils/PriceCapAdapterBase.sol";
import { MockERC20 } from "./MockERC20.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";

import { console } from "forge-std/console.sol";

contract ERC4626CorrelatedAssetsPriceOracleTest is Test {
    using SignedMath for int256;

    MockERC20 public assetA;
    SimplePriceFeed public priceFeedA;
    SimpleERC4626RatePriceFeed public priceFeedB;
    address manager;

    ERC4626CorrelatedAssetsPriceOracle public capo;

    function setUp() public {
        manager = makeAddr("manager");
    }

    function _deployFeeds(
        uint8 assetADecimals,
        uint8 priceFeedADecimals,
        uint8 priceFeedBDecimals,
        int256 priceA,
        int256 priceB,
        uint8 capoDecimals,
        uint48 minDelay,
        uint32 maxGrowthPercent
    ) internal {
        assetA = new MockERC20("Asset A", "ASSET_A", assetADecimals);
        priceFeedA = new SimplePriceFeed(priceA, priceFeedADecimals);
        priceFeedB = new SimpleERC4626RatePriceFeed(priceB, priceFeedBDecimals, address(assetA));
        vm.warp(block.timestamp + (minDelay * 2));
        vm.roll(block.number + 1);

        PriceCapAdapterBase.PriceCapSnapshot memory priceCapSnapshot = PriceCapAdapterBase.PriceCapSnapshot({
            snapshotRatio: uint256(priceB),
            snapshotTimestamp: uint48(block.timestamp - minDelay),
            maxYearlyRatioGrowthPercent: maxGrowthPercent
        });
        capo = new ERC4626CorrelatedAssetsPriceOracle(
            manager,
            AggregatorV3Interface(address(priceFeedA)),
            address(priceFeedB),
            "CAPO Price Feed",
            capoDecimals,
            minDelay,
            priceCapSnapshot
        );
    }

    function _testFuzz_getRatio_exactGrowth(
        uint8 assetADecimals,
        uint8 priceFeedADecimals,
        uint8 priceFeedBDecimals,
        uint8 capoDecimals,
        int256 priceA,
        int256 priceB,
        uint48 minDelay,
        uint32 maxGrowthPercent,
        uint256 timeToAdvance
    ) internal pure returns (uint8, uint8, uint8, uint8, int256, int256, uint48, uint32, uint256) {
        assetADecimals = uint8(bound(assetADecimals, 6, 18));
        priceFeedADecimals = uint8(bound(priceFeedADecimals, 6, 18));
        priceFeedBDecimals = uint8(bound(priceFeedBDecimals, 6, 18));
        capoDecimals = uint8(bound(capoDecimals, 6, 18));
        minDelay = uint48(bound(minDelay, 1, 10 days));
        maxGrowthPercent = uint32(bound(maxGrowthPercent, 1_00, 1000_00)); // 1_000% growth
        timeToAdvance = bound(timeToAdvance, 60 days, 365 days * 3);

        priceA = int256(bound(uint256(priceA), 10 ** (priceFeedADecimals - 2), 100_000 * 10 ** priceFeedADecimals));
        priceB = int256(bound(uint256(priceB), 10 ** (assetADecimals - 2), 100_000 * 10 ** assetADecimals));

        return (assetADecimals, priceFeedADecimals, priceFeedBDecimals, capoDecimals, priceA, priceB, minDelay, maxGrowthPercent, timeToAdvance);
    }

    function testFuzz_latestRoundData_exactGrowth(
        uint8 assetADecimals,
        uint8 priceFeedADecimals,
        uint8 priceFeedBDecimals,
        uint8 capoDecimals,
        int256 priceA,
        int256 priceB,
        uint48 minDelay,
        uint32 maxGrowthPercent,
        uint256 timeToAdvance
    ) public {
        (
            assetADecimals,
            priceFeedADecimals,
            priceFeedBDecimals,
            capoDecimals,
            priceA,
            priceB,
            minDelay,
            maxGrowthPercent,
            timeToAdvance
        ) = _testFuzz_getRatio_exactGrowth(
            assetADecimals,
            priceFeedADecimals,
            priceFeedBDecimals,
            capoDecimals,
            priceA,
            priceB,
            minDelay,
            maxGrowthPercent,
            timeToAdvance
        );

        _deployFeeds(assetADecimals, priceFeedADecimals, priceFeedBDecimals, priceA, priceB, capoDecimals, minDelay, maxGrowthPercent);
        vm.warp(block.timestamp + timeToAdvance);
        vm.roll(block.number + 1);
        // Advance time to ensure the price feed is updated
        int256 expectedRate = priceB + (priceB * int32(maxGrowthPercent) * int256(timeToAdvance)) / int256(365 days) / 100_00;

        priceFeedB.setRoundData(expectedRate);

        int256 rate = capo.getRatio();

        assertEq(rate, expectedRate, "Rate should match the expected rate");

        // Check the latest round data
        (, int256 price, , , ) = capo.latestRoundData();
        uint256 expectedPrice = (uint256(expectedRate) * uint256(priceA)) / (10 ** assetADecimals);
        expectedPrice = capoDecimals > priceFeedADecimals
            ? expectedPrice * (10 ** (capoDecimals - priceFeedADecimals))
            : expectedPrice / (10 ** (priceFeedADecimals - capoDecimals));
        require(!capo.isCapped(), "Capped price oracle should not be capped");
        assertEq(uint256(price), expectedPrice, "Latest round data price should match the expected price");
    }

    function testFuzz_latestRoundData_growthExceeds(
        uint8 assetADecimals,
        uint8 priceFeedADecimals,
        uint8 priceFeedBDecimals,
        uint8 capoDecimals,
        int256 priceA,
        int256 priceB,
        uint48 minDelay,
        uint32 maxGrowthPercent,
        uint256 timeToAdvance
    ) public {
        (
            assetADecimals,
            priceFeedADecimals,
            priceFeedBDecimals,
            capoDecimals,
            priceA,
            priceB,
            minDelay,
            maxGrowthPercent,
            timeToAdvance
        ) = _testFuzz_getRatio_exactGrowth(
            assetADecimals,
            priceFeedADecimals,
            priceFeedBDecimals,
            capoDecimals,
            priceA,
            priceB,
            minDelay,
            maxGrowthPercent,
            timeToAdvance
        );

        _deployFeeds(assetADecimals, priceFeedADecimals, priceFeedBDecimals, priceA, priceB, capoDecimals, minDelay, maxGrowthPercent);
        vm.warp(block.timestamp + timeToAdvance);
        vm.roll(block.number + 1);

        // Set a rate that exceeds the expected growth
        int256 actualRate = priceB + (priceB * int32(maxGrowthPercent * 2) * int256(timeToAdvance)) / int256(365 days) / 100_00;

        priceFeedB.setRoundData(actualRate);

        uint256 uncappedPrice = (uint256(actualRate) * uint256(priceA)) / (10 ** assetADecimals);
        uncappedPrice = capoDecimals > priceFeedADecimals
            ? uncappedPrice * (10 ** (capoDecimals - priceFeedADecimals))
            : uncappedPrice / (10 ** (priceFeedADecimals - capoDecimals));

        // The rate should be capped to the maximum growth allowed
        require(capo.isCapped(), "Capped price oracle should be capped");

        (, int256 cappedPrice, , , ) = capo.latestRoundData();
        vm.assume(uncappedPrice > uint256(cappedPrice));
        assertGt(uncappedPrice, uint256(cappedPrice), "Uncapped price should be greater than the expected capped price");
    }

    function testFuzz_latestRoundData_growthNotExceeds(
        uint8 assetADecimals,
        uint8 priceFeedADecimals,
        uint8 priceFeedBDecimals,
        uint8 capoDecimals,
        int256 priceA,
        int256 priceB,
        uint48 minDelay,
        uint32 maxGrowthPercent,
        uint256 timeToAdvance
    ) public {
        (
            assetADecimals,
            priceFeedADecimals,
            priceFeedBDecimals,
            capoDecimals,
            priceA,
            priceB,
            minDelay,
            maxGrowthPercent,
            timeToAdvance
        ) = _testFuzz_getRatio_exactGrowth(
            assetADecimals,
            priceFeedADecimals,
            priceFeedBDecimals,
            capoDecimals,
            priceA,
            priceB,
            minDelay,
            maxGrowthPercent,
            timeToAdvance
        );

        _deployFeeds(assetADecimals, priceFeedADecimals, priceFeedBDecimals, priceA, priceB, capoDecimals, minDelay, maxGrowthPercent);
        vm.warp(block.timestamp + timeToAdvance);
        vm.roll(block.number + 1);

        // Set a rate that exceeds the expected growth
        int256 actualRate = priceB + (priceB * int32(maxGrowthPercent / 2) * int256(timeToAdvance)) / int256(365 days) / 100_00;

        priceFeedB.setRoundData(actualRate);

        int256 rate = capo.getRatio();

        assertEq(rate, actualRate, "Rate should match the expected rate");

        // Check the latest round data
        (, int256 price, , , ) = capo.latestRoundData();
        uint256 expectedPrice = (uint256(actualRate) * uint256(priceA)) / (10 ** assetADecimals);
        expectedPrice = capoDecimals > priceFeedADecimals
            ? expectedPrice * (10 ** (capoDecimals - priceFeedADecimals))
            : expectedPrice / (10 ** (priceFeedADecimals - capoDecimals));
        vm.assume(!capo.isCapped());
        assertEq(uint256(price), expectedPrice, "Latest round data price should match the expected price");
    }
}
