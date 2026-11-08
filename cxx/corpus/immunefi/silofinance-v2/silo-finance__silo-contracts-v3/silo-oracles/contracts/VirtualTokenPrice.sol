// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable1and2Steps} from "common/access/Ownable1and2Steps.sol";
import {Aggregator} from "silo-oracles/contracts/_common/Aggregator.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

contract VirtualTokenPrice is Ownable1and2Steps {
    mapping(address token => Aggregator oracle) public oracles;

    error InvalidToken();
    error InvalidAggregator();
    error InvalidAggregatorPrice();
    error PriceAlreadySet();

    constructor() Ownable1and2Steps(msg.sender) {}

    function removePrice(address _token) external onlyOwner {
        delete oracles[_token];
    }

    function setPrice(address _token, Aggregator _aggregator) external onlyOwner {
        require(_token != address(0), InvalidToken());
        require(address(_aggregator) != address(0), InvalidAggregator());

        (, int256 price, ,,) = _aggregator.latestRoundData();
        require(price != 0, InvalidAggregatorPrice());
        
        oracles[_token] = _aggregator;
    }

    function getPrice(address _token) external view returns (uint256 price) {
        (, int256 answer, ,,) = oracles[_token].latestRoundData();
        price = SafeCast.toUint256(answer);
    }
}
