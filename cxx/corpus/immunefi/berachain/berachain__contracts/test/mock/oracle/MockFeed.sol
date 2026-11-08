// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IPriceOracle } from "../../../src/extras/IPriceOracle.sol";

// TODO: improve API
contract MockFeed {
    IPriceOracle.Data public data;

    function setPrice(uint256 price) external {
        data.price = price;
        data.publishTime = block.timestamp;
    }

    function setStaleSeconds(uint256 s) external {
        data.publishTime = block.timestamp - s;
    }

    ///////////////////////////////////////////////////////////////////////////

    function getPrice() external view returns (IPriceOracle.Data memory) {
        return data;
    }
}
