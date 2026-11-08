// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { ChainlinkCorrelatedAssetsPriceOracle } from "../ChainlinkCorrelatedAssetsPriceOracle.sol";
import { PriceCapAdapterBase } from "../utils/PriceCapAdapterBase.sol";

import { SimplePriceFeed } from "./SimplePriceFeed.sol";

contract ChainliChainlinkCorrelatedAssetsPriceOracleTest is Test {
    address manager;

    SimplePriceFeed clFeed;
    SimplePriceFeed ratioFeed;
    ChainlinkCorrelatedAssetsPriceOracle capo;

    function setUp() public {
        manager = makeAddr("manager");
        vm.warp(1 hours + 1);
    }

    function _deploy(uint8 feedDec, uint8 outDec, int256 priceA) internal {
        clFeed = new SimplePriceFeed(priceA, feedDec);
        ratioFeed = new SimplePriceFeed(1e18, 18);
        PriceCapAdapterBase.PriceCapSnapshot memory snap = PriceCapAdapterBase.PriceCapSnapshot({
            snapshotRatio: 1e18,
            snapshotTimestamp: uint48(block.timestamp - 1 hours),
            maxYearlyRatioGrowthPercent: 100
        });

        capo = new ChainlinkCorrelatedAssetsPriceOracle(
            manager,
            AggregatorV3Interface(address(clFeed)),
            address(ratioFeed),
            "Chainlink CAPO",
            outDec,
            3600,
            snap
        );
    }

    // -----------------------------------------------------------------------------
    // utilities
    // -----------------------------------------------------------------------------
    function _boundInputs(uint8 feedDec, uint8 outDec, int256 priceA) internal pure returns (uint8, uint8, int256) {
        vm.assume(priceA != type(int256).min);
        feedDec = uint8(bound(feedDec, 6, 18));
        outDec = uint8(bound(outDec, 6, 18));

        // keep the value strictly positive and within a sane range
        uint256 mag = uint256(priceA >= 0 ? priceA : -priceA);
        mag = bound(mag, 10 ** (feedDec - 2), 100_000 * 10 ** feedDec);

        return (feedDec, outDec, int256(mag));
    }

    // -----------------------------------------------------------------------------
    // fuzz – mirrors the Chainlink feed after CAPO scaling
    // -----------------------------------------------------------------------------
    function testFuzz_mirrorsChainlink(uint8 feedDec, uint8 outDec, int256 priceA) public {
        (uint8 fd, uint8 od, int256 pA) = _boundInputs(feedDec, outDec, priceA);
        _deploy(fd, od, pA);

        // low-level call so a revert just drops the seed
        (bool ok, bytes memory ret) = address(capo).call(abi.encodeWithSignature("latestRoundData()"));
        vm.assume(ok);

        (, int256 answer, , , ) = abi.decode(ret, (uint80, int256, uint256, uint256, uint80));

        // Oracle must not emit negative answers
        vm.assume(answer >= 0);

        uint256 expected = uint256(pA);
        if (od > fd) expected *= 10 ** (od - fd);
        else if (od < fd) expected /= 10 ** (fd - od);

        // fit-check so the cast below can’t overflow
        vm.assume(expected <= uint256(type(int256).max));

        assertEq(answer, int256(expected), "scaled price mismatch");
        assertTrue(!capo.isCapped());
        assertEq(capo.getRatio(), 1e18);
    }

    // -----------------------------------------------------------------------------
    // round-meta passthrough smoke-test
    // -----------------------------------------------------------------------------
    function test_roundMetaPassThrough() public {
        _deploy(8, 8, 1e8);
        clFeed.setRoundData(42, 2e8, 777, 888, 42);

        (bool ok, bytes memory ret) = address(capo).call(abi.encodeWithSignature("latestRoundData()"));
        require(ok, "oracle reverted");

        (uint80 id, int256 price, uint256 started, uint256 updated, uint80 ansInRound) = abi.decode(ret, (uint80, int256, uint256, uint256, uint80));

        assertEq(id, 42);
        assertEq(price, 2e8);
        assertEq(started, 777);
        assertEq(updated, 888);
        assertEq(ansInRound, 42);
    }
}
