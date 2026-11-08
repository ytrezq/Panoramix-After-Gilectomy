// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IStrcPriceOracle {
    /// @notice Returns the current STRC price and its decimal precision
    /// @return price The current price of STRC in USD terms
    /// @return decimals The number of decimals for the price value
    function getPrice() external view returns (uint256 price, uint8 decimals);
}
