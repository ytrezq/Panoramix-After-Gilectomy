// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IPyth, PythStructs } from "@pythnetwork/IPyth.sol";

/**
 * @author Berachain Team
 */
contract MockPyth is IPyth {
    mapping(bytes32 id => PythStructs.Price data) public feeds;

    function setData(bytes32 id, int64 price, uint64 conf, int32 expo, uint256 publishTime) external {
        feeds[id].price = price;
        feeds[id].conf = conf;
        feeds[id].expo = expo;
        feeds[id].publishTime = publishTime;
    }

    function setReturn(bytes32 id, PythStructs.Price memory price) public {
        feeds[id] = price;
    }

    // Mocked functions
    function getPrice(bytes32 id) external view returns (PythStructs.Price memory) {
        return feeds[id];
    }

    function getPriceUnsafe(bytes32 id) external view returns (PythStructs.Price memory) {
        return feeds[id];
    }

    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (PythStructs.Price memory) {
        age;
        return feeds[id];
    }

    function getValidTimePeriod() external view override returns (uint256 validTimePeriod) { }

    function getEmaPrice(bytes32 id) external view override returns (PythStructs.Price memory price) { }

    function getEmaPriceUnsafe(bytes32 id) external view override returns (PythStructs.Price memory price) { }

    function getEmaPriceNoOlderThan(
        bytes32 id,
        uint256 age
    )
        external
        view
        override
        returns (PythStructs.Price memory price)
    { }

    function updatePriceFeeds(bytes[] calldata updateData) external payable override { }

    function updatePriceFeedsIfNecessary(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64[] calldata publishTimes
    )
        external
        payable
        override
    { }

    function getUpdateFee(bytes[] calldata updateData) external view override returns (uint256 feeAmount) { }

    function parsePriceFeedUpdates(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64 minPublishTime,
        uint64 maxPublishTime
    )
        external
        payable
        override
        returns (PythStructs.PriceFeed[] memory priceFeeds)
    { }

    function parsePriceFeedUpdatesUnique(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64 minPublishTime,
        uint64 maxPublishTime
    )
        external
        payable
        override
        returns (PythStructs.PriceFeed[] memory priceFeeds)
    { }
}
