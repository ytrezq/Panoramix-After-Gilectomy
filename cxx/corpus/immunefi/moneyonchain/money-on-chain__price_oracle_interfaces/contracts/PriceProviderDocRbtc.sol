// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./interfaces/IPriceProvider.sol";
import "./interfaces/IMocState.sol";
import "./interfaces/ICoinPairPrice.sol";
import "./DocPriceLib.sol";

/// @title PriceProviderDocRbtc
/// @notice Exposes MoC's DOC/RBTC price through IPriceProvider with 18 decimals.
/// @dev DOC/RBTC is capped at USD/BTC (inverse of BTC/USD) to preserve the 1 USD DOC peg upper bound.
contract PriceProviderDocRbtc is IPriceProvider {
  IMocState public immutable mocState;
  ICoinPairPrice public immutable btcPriceProvider;

  constructor(IMocState _mocState) {
    require(address(_mocState) != address(0), "mocState address is zero");
    mocState = _mocState;
    btcPriceProvider = ICoinPairPrice(_mocState.getBtcPriceProvider());
  }

  function peek() external view override returns (bytes32, bool) {
    (bytes32 btcPriceInUsdBytes, bool btcPriceIsValid) = btcPriceProvider.peek();
    uint256 btcPriceInUsd = uint256(btcPriceInUsdBytes);
    uint256 docPriceInRbtc = DocPriceLib.docRbtcPriceSafe(mocState, btcPriceInUsd);

    bool overallValid = btcPriceIsValid && btcPriceInUsd != 0 && docPriceInRbtc != 0;
    return (bytes32(docPriceInRbtc), overallValid);
  }

  function getLastPublicationBlock() external view override returns (uint256) {
    return btcPriceProvider.getLastPublicationBlock();
  }
}
