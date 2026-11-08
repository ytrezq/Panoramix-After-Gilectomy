// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IPriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";
import {AP_ZERO_PRICE_FEED} from "../libraries/ContractLiterals.sol";

/// @title Zero price feed
/// @notice Always returns zero price as answer
contract ZeroPriceFeed is IPriceFeed {
    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = AP_ZERO_PRICE_FEED;

    uint8 public constant override decimals = 8;
    string public constant override description = "Zero price feed";
    bool public constant override skipPriceCheck = true;

    /// @notice Empty state serialization
    function serialize() external pure override returns (bytes memory) {}

    /// @notice Returns zero price
    function latestRoundData() external pure override returns (uint80, int256, uint256, uint256, uint80) {
        return (0, 0, 0, 0, 0);
    }
}
