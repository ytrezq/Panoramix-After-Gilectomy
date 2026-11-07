// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IPriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";
import {NestedPriceFeeds} from "../../libraries/NestedPriceFeeds.sol";
import {
    MockPriceFeed,
    MockSingleUnderlyingPriceFeed,
    MockMultipleUnderlyingPriceFeed,
    MockFallbackPriceFeed
} from "../mocks/MockPriceFeed.sol";

contract NestedPriceFeedsUnitTest is Test {
    function test_U_NPF_01_getNestingType_works_as_expected() public {
        // Test simple feed with no nesting
        MockPriceFeed simpleFeed = new MockPriceFeed();
        assertEq(
            uint256(NestedPriceFeeds.getNestingType(simpleFeed)),
            uint256(NestedPriceFeeds.NestingType.NO_NESTING),
            "Wrong nesting type for simple feed"
        );

        // Test single underlying
        MockSingleUnderlyingPriceFeed singleFeed = new MockSingleUnderlyingPriceFeed(address(1));
        assertEq(
            uint256(NestedPriceFeeds.getNestingType(singleFeed)),
            uint256(NestedPriceFeeds.NestingType.SINGLE_UNDERLYING),
            "Wrong nesting type for single underlying"
        );

        // Test multiple underlying
        address[] memory underlyings = new address[](3);
        underlyings[0] = makeAddr("feed0");
        underlyings[1] = makeAddr("feed1");
        underlyings[2] = makeAddr("feed2");
        MockMultipleUnderlyingPriceFeed multiFeed = new MockMultipleUnderlyingPriceFeed(underlyings);
        assertEq(
            uint256(NestedPriceFeeds.getNestingType(multiFeed)),
            uint256(NestedPriceFeeds.NestingType.MULTIPLE_UNDERLYING),
            "Wrong nesting type for multiple underlying"
        );

        // Test feed with fallback but no actual implementation
        MockFallbackPriceFeed fallbackFeed = new MockFallbackPriceFeed();
        assertEq(
            uint256(NestedPriceFeeds.getNestingType(fallbackFeed)),
            uint256(NestedPriceFeeds.NestingType.NO_NESTING),
            "Wrong nesting type for fallback feed"
        );
    }

    function test_U_NPF_02_getUnderlyingFeeds_works_as_expected_with_no_nesting() public {
        MockPriceFeed feed = new MockPriceFeed();
        address[] memory feeds = NestedPriceFeeds.getUnderlyingFeeds(feed);
        assertEq(feeds.length, 0, "Should return empty array for non-nested feed");
    }

    function test_U_NPF_03_getUnderlyingFeeds_works_as_expected_with_single_underlying() public {
        address underlying = makeAddr("underlying");
        MockSingleUnderlyingPriceFeed feed = new MockSingleUnderlyingPriceFeed(underlying);

        address[] memory feeds = NestedPriceFeeds.getUnderlyingFeeds(feed);
        assertEq(feeds.length, 1, "Wrong number of feeds");
        assertEq(feeds[0], underlying, "Wrong underlying feed");
    }

    function test_U_NPF_04_getUnderlyingFeeds_works_as_expected_with_multiple_underlyings() public {
        // Test regular case with 3 feeds
        address[] memory underlyings = new address[](3);
        for (uint256 i = 0; i < 3; ++i) {
            underlyings[i] = makeAddr(string.concat("feed", vm.toString(i)));
        }

        MockMultipleUnderlyingPriceFeed feed = new MockMultipleUnderlyingPriceFeed(underlyings);
        address[] memory feeds = NestedPriceFeeds.getUnderlyingFeeds(feed);
        assertEq(feeds.length, 3, "Wrong number of feeds");
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(feeds[i], underlyings[i], "Wrong underlying feed");
        }

        // Test max length case
        underlyings = new address[](NestedPriceFeeds.MAX_UNDERLYING_PRICE_FEEDS);
        for (uint256 i = 0; i < NestedPriceFeeds.MAX_UNDERLYING_PRICE_FEEDS; ++i) {
            underlyings[i] = makeAddr(string.concat("feed", vm.toString(i)));
        }

        feed = new MockMultipleUnderlyingPriceFeed(underlyings);
        feeds = NestedPriceFeeds.getUnderlyingFeeds(feed);
        assertEq(feeds.length, NestedPriceFeeds.MAX_UNDERLYING_PRICE_FEEDS, "Wrong number of feeds for max length");
        for (uint256 i = 0; i < NestedPriceFeeds.MAX_UNDERLYING_PRICE_FEEDS; ++i) {
            assertEq(feeds[i], underlyings[i], "Wrong underlying feed for max length");
        }

        // Test array with zeros at the end
        underlyings = new address[](NestedPriceFeeds.MAX_UNDERLYING_PRICE_FEEDS);
        for (uint256 i = 0; i < 3; ++i) {
            underlyings[i] = makeAddr(string.concat("feed", vm.toString(i)));
        }
        // rest are address(0)

        feed = new MockMultipleUnderlyingPriceFeed(underlyings);
        feeds = NestedPriceFeeds.getUnderlyingFeeds(feed);
        assertEq(feeds.length, 3, "Wrong number of feeds for partial array");
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(feeds[i], underlyings[i], "Wrong underlying feed for partial array");
        }

        // Test smaller array with zeros at the end
        underlyings = new address[](5);
        for (uint256 i = 0; i < 2; ++i) {
            underlyings[i] = makeAddr(string.concat("feed", vm.toString(i)));
        }
        // rest are address(0)

        feed = new MockMultipleUnderlyingPriceFeed(underlyings);
        feeds = NestedPriceFeeds.getUnderlyingFeeds(feed);
        assertEq(feeds.length, 2, "Wrong number of feeds for smaller array");
        for (uint256 i = 0; i < 2; ++i) {
            assertEq(feeds[i], underlyings[i], "Wrong underlying feed for smaller array");
        }
    }
}
