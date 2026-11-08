// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "moc-main-latest/contracts/interfaces/IPriceProvider.sol";

/// @title Price Provider
/// @notice Returns a price and reports the current block as last publication.
contract WrapperPriceProvider is IPriceProvider {
    IPriceProvider public underlyingPriceProvider;

    constructor(IPriceProvider _priceProvider) {
        underlyingPriceProvider = _priceProvider;
    }

    /// @dev Returns same value as the underlying price provider.
    function peek() external view override returns (bytes32, bool) {
        return underlyingPriceProvider.peek();
    }

    /// @dev Reports the *current* block to look fresh to age checkers.
    function getLastPublicationBlock() external view override returns (uint256) {
        return block.number;
    }
}
