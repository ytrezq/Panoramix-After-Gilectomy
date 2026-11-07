// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./interfaces/IPriceProvider.sol";

/// @title Dummy Price Provider (always fresh)
/// @notice Returns a fixed price and reports the current block as last publication.
contract PriceProviderDummy is IPriceProvider {
  uint256 public price;

  constructor(uint256 _price) {
    price = _price;
  }

  /// @dev Always returns the same price and `true`.
  function peek() external view override returns (bytes32, bool) {
    return (bytes32(price), true);
  }

  /// @dev Reports the *current* block to look fresh to age checkers.
  function getLastPublicationBlock() external view override returns (uint256) {
    return block.number;
  }
}
