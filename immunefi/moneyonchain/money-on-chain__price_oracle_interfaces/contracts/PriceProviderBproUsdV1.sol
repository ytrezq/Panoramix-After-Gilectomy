// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./interfaces/IPriceProvider.sol";
import "./interfaces/IMocState.sol";
import "./interfaces/ICoinPairPrice.sol";
import "./BproPriceLib.sol";

/// @title PriceProviderBproUsdV1
/// @notice Exposes MoC's BPRO/USD price through the IPriceProvider interface.
/// @dev
/// - Uses MoCState as source of truth.
/// - Requires the BTC price provider inside MoCState to be valid (gate for freshness).
/// - Returns 18-decimal fixed-point value encoded in bytes32.
contract PriceProviderBproUsdV1 is IPriceProvider {
  IMocState public immutable mocState;
  /// @notice Cached at deploy time for gas savings. Redeploy if MocState changes its btcPriceProvider.
  ICoinPairPrice public immutable btcPriceProvider;

  constructor(IMocState _mocState) {
    require(address(_mocState) != address(0), "mocState address is zero");
    mocState = _mocState;
    btcPriceProvider = ICoinPairPrice(_mocState.getBtcPriceProvider());
  }

  /// @notice Returns (price, valid) where price is BPRO/USD in 18 decimals.
  function peek() external view returns (bytes32, bool) {
    // 1) Query the pair rate from the BTC price provider
    (bytes32 pairRateBytes, bool pairRateIsValid) = btcPriceProvider.peek();

    // 2) Convert and retrieve the BPRO/USD price from MoCState
    uint256 pairRate = uint256(pairRateBytes);
    uint256 bproUsdPrice = BproPriceLib.bproUsdPriceSafe(mocState, pairRateBytes); // always 18 decimals

    // 3) Always attempt to return the result even if validity is false
    //    Only return zero if there is no data available
    if (bproUsdPrice == 0) {
      return (bytes32(0), false);
    }

    // 4) Determine overall validity based on provider trust and non-zero data
    bool overallValid = pairRateIsValid && pairRate != 0 && bproUsdPrice != 0;

    // 5) Return the calculated price (as bytes32) and overall validity flag
    return (bytes32(bproUsdPrice), overallValid);
  }

  /// @notice Forwards the last publication block from MoC's BTC provider (used by age checks).
  function getLastPublicationBlock() external view returns (uint256) {
    return btcPriceProvider.getLastPublicationBlock();
  }
}
