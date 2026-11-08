// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IPriceOracle } from "../../../src/extras/IPriceOracle.sol";
import { MockFeed } from "./MockFeed.sol";

contract MockOracle is IPriceOracle {
    mapping(address asset => MockFeed feed) public feeds;

    function setPriceFeed(address asset, MockFeed feed) external {
        feeds[asset] = feed;
    }

    ///////////////////////////////////////////////////////////////////////////

    function getPrice(address asset) external view returns (IPriceOracle.Data memory price) {
        return feeds[asset].getPrice();
    }

    function getPriceUnsafe(address asset) external view returns (IPriceOracle.Data memory price) {
        return feeds[asset].getPrice();
    }

    function getPriceNoOlderThan(address asset, uint256 age) external view returns (IPriceOracle.Data memory price) {
        age;
        return feeds[asset].getPrice();
    }

    function priceAvailable(address asset) external view returns (bool) {
        IPriceOracle.Data memory price = feeds[asset].getPrice();
        return price.publishTime > 0;
    }
}
