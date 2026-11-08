// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "../interfaces/AggregatorV3Interface.sol";

contract SimpleERC4626RatePriceFeed {
    string public constant description = "Mock Chainlink price aggregator";

    uint public constant version = 1;

    uint8 public immutable decimals;

    address public immutable asset;

    int256 internal answer;

    constructor(int answer_, uint8 decimals_, address _asset) {
        answer = answer_;
        decimals = decimals_;
        asset = _asset;
    }

    function setRoundData(int256 answer_) public {
        answer = answer_;
    }

    function convertToAssets(uint256) external view returns (uint256) {
        return uint256(answer);
    }
}
