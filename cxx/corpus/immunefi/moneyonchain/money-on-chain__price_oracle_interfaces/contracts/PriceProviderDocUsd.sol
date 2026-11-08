// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./interfaces/IPriceProvider.sol";
import "./interfaces/IMocState.sol";
import "./interfaces/ICoinPairPrice.sol";
import "./DocPriceLib.sol";

/// @title PriceProviderDocUsd
/// @notice Exposes MoC's DOC/USD price through IPriceProvider with 18 decimals.
/// @dev DOC/USD is capped at 1e18 (senior claim).
contract PriceProviderDocUsd is IPriceProvider {
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
    uint256 docPriceInUsd = DocPriceLib.docUsdPriceSafe(mocState, btcPriceInUsd);

    bool overallValid = btcPriceIsValid && btcPriceInUsd != 0 && docPriceInUsd != 0;
    return (bytes32(docPriceInUsd), overallValid);
  }

  function getLastPublicationBlock() external view override returns (uint256) {
    return btcPriceProvider.getLastPublicationBlock();
  }
}
