// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IPriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";

contract MockPriceFeed is IPriceFeed {
    uint256 private _lastUpdateTime;
    int256 private _price;
    bytes32 private constant _CONTRACT_TYPE = "PRICE_FEED::MOCK";
    uint256 private constant _VERSION = 1;

    constructor() {
        _lastUpdateTime = block.timestamp;
        _price = 1e18; // Default price of 1
    }

    function serialize() external pure override returns (bytes memory) {}

    function lastUpdateTime() external view returns (uint256) {
        return _lastUpdateTime;
    }

    function version() external pure returns (uint256) {
        return _VERSION;
    }

    function contractType() external pure returns (bytes32) {
        return _CONTRACT_TYPE;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _price, _lastUpdateTime, _lastUpdateTime, 0);
    }

    // Test helper functions
    function setLastUpdateTime(uint256 timestamp) external {
        _lastUpdateTime = timestamp;
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }

    function decimals() external pure returns (uint8) {
        return 8; // Standard 8 decimals for USD oracles
    }

    function description() external pure returns (string memory) {
        return "Mock Price Feed";
    }

    function skipPriceCheck() external pure returns (bool) {
        return false;
    }
}

contract MockFallbackPriceFeed is MockPriceFeed {
    fallback() external {}
}

contract MockUpdatablePriceFeed is MockPriceFeed {
    bytes public lastUpdateData;
    bool public constant updatable = true;

    function updatePrice(bytes calldata data) external {
        lastUpdateData = data;
    }
}

contract MockSingleUnderlyingPriceFeed is MockPriceFeed {
    address public immutable priceFeed;

    constructor(address _priceFeed) {
        priceFeed = _priceFeed;
    }
}

contract MockMultipleUnderlyingPriceFeed is MockPriceFeed {
    address[] public priceFeeds;

    constructor(address[] memory priceFeeds_) {
        require(priceFeeds_.length <= 8, "Too many feeds");

        bool seenZero;
        for (uint256 i = 0; i < priceFeeds_.length; ++i) {
            if (priceFeeds_[i] == address(0)) seenZero = true;
            else require(!seenZero, "Non-zero feed after zero");
        }

        priceFeeds = priceFeeds_;
    }

    function _getPriceFeed(uint256 index) internal view returns (address) {
        if (index >= priceFeeds.length) revert("Not implemented");
        return priceFeeds[index];
    }

    function priceFeed0() external view returns (address) {
        return _getPriceFeed(0);
    }

    function priceFeed1() external view returns (address) {
        return _getPriceFeed(1);
    }

    function priceFeed2() external view returns (address) {
        return _getPriceFeed(2);
    }

    function priceFeed3() external view returns (address) {
        return _getPriceFeed(3);
    }

    function priceFeed4() external view returns (address) {
        return _getPriceFeed(4);
    }

    function priceFeed5() external view returns (address) {
        return _getPriceFeed(5);
    }

    function priceFeed6() external view returns (address) {
        return _getPriceFeed(6);
    }

    function priceFeed7() external view returns (address) {
        return _getPriceFeed(7);
    }
}
