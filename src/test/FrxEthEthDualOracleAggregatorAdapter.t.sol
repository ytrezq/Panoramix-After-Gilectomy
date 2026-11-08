// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {FrxEthEthDualOracleAggregatorAdapter} from "../FrxEthEthDualOracleAggregatorAdapter.sol";

contract MockFrxEthEthDualOracle {
    bool internal _isBadData;
    uint256 internal _priceLow;
    uint256 internal _priceHigh;

    function setPrices(bool isBadData_, uint256 priceLow_, uint256 priceHigh_) external {
        _isBadData = isBadData_;
        _priceLow = priceLow_;
        _priceHigh = priceHigh_;
    }

    function getPrices() external view returns (bool isBadData, uint256 priceLow, uint256 priceHigh) {
        return (_isBadData, _priceLow, _priceHigh);
    }
}

contract FrxEthEthDualOracleAggregatorAdapterTest is Test {
    MockFrxEthEthDualOracle internal dualOracle;
    FrxEthEthDualOracleAggregatorAdapter internal adapter;

    function setUp() public {
        dualOracle = new MockFrxEthEthDualOracle();
        adapter = new FrxEthEthDualOracleAggregatorAdapter(address(dualOracle));
    }

    function test_constructor_setsDualOracleAddress() public view {
        assertEq(address(adapter.dualOracle()), address(dualOracle), "unexpected dual oracle address");
    }

    function test_decimals_returns18() public view {
        assertEq(adapter.decimals(), 18, "unexpected decimals");
    }

    function test_latestRoundData_returnsAveragePrice() public {
        dualOracle.setPrices(false, 0.999e18, 1.001e18);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();

        assertEq(roundId, uint80(block.number), "unexpected roundId");
        assertEq(answer, int256(1e18), "unexpected average price");
        assertEq(startedAt, block.timestamp, "unexpected startedAt");
        assertEq(updatedAt, block.timestamp, "unexpected updatedAt");
        assertEq(answeredInRound, uint80(block.number), "unexpected answeredInRound");
    }

    function test_latestRoundData_revertsOnBadData() public {
        dualOracle.setPrices(true, 1e18, 1e18);

        vm.expectRevert(bytes("Bad dual oracle data"));
        adapter.latestRoundData();
    }

    function test_latestRoundData_revertsOnZeroAveragePrice() public {
        dualOracle.setPrices(false, 0, 0);

        vm.expectRevert(bytes("Invalid dual oracle price"));
        adapter.latestRoundData();
    }
}
