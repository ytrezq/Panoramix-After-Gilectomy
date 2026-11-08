// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IPriceProvider.sol";
import "./interfaces/IMocState.sol";
import "./interfaces/ICoinPairPrice.sol";
import "./BproPriceLib.sol";

/// @title PriceProviderFlipPerBpro
/// @notice Exposes FLIP/BPRO price using two USD-denominated sources:
///         FLIP/BPRO = (FLIP/USD) / (BPRO/USD)
/// @dev
/// - FLIP/USD comes from an external IPriceProvider (assumed 18 decimals).
/// - BPRO/USD comes from MoCState (bproUsdPrice(), 18 decimals).
/// - As in CoinPairPriceBproUsdConversion, we gate output by checking that
///   MoC's BTC price provider (getBtcPriceProvider) reports a valid price.
/// - Result is 18-decimal fixed point.
/// - getLastPublicationBlock(): min(lastPub of FLIP/USD, lastPub of MoC's BTC provider).
contract PriceProviderFlipPerBpro is IPriceProvider {
  IPriceProvider public immutable flipUsd; // expects 18d
  IMocState public immutable mocState;
  /// @notice Cached at deploy time for gas savings. Redeploy if MocState changes its btcPriceProvider.
  ICoinPairPrice public immutable btcPriceProvider;

  constructor(IPriceProvider _flipUsd, IMocState _mocState) {
    require(address(_flipUsd) != address(0), "flipUsd is zero");
    require(address(_mocState) != address(0), "mocState is zero");
    flipUsd = _flipUsd;
    mocState = _mocState;
    btcPriceProvider = ICoinPairPrice(_mocState.getBtcPriceProvider());
  }

  /// @notice Returns FLIP/BPRO with 18 decimals, gated by MoC BTC provider validity.
  function peek() external view override returns (bytes32, bool) {
    // 1) Get the base pair rate validity from BTC price provider
    (bytes32 btcPrice, bool pairRateIsValid) = btcPriceProvider.peek();

    // 2) Get FLIP/USD from external provider (18 decimals)
    (bytes32 flipRateBytes, bool flipRateIsValid) = flipUsd.peek();
    uint256 flipRate = uint256(flipRateBytes);

    // 3) Get BPRO/USD from MoCState (18 decimals)
    uint256 bproUsdPrice = BproPriceLib.bproUsdPriceSafe(mocState, btcPrice);

    // 4) Compute FLIP/BPRO = (FLIP/USD) / (BPRO/USD) = (flipRate * 1e18) / bproUsdPrice
    uint256 flipPerBpro = 0;
    if (flipRate != 0 && bproUsdPrice != 0) {
      flipPerBpro = Math.mulDiv(flipRate, 1e18, bproUsdPrice);
    }

    // 5) Determine overall validity (all sources valid + non-zero result)
    bool overallValid = pairRateIsValid && flipRateIsValid && flipPerBpro != 0;

    // 6) Always return the calculated value, even if validity is false
    return (bytes32(flipPerBpro), overallValid);
  }

  /// @notice Freshness: min(lastPubBlock of FLIP/USD, lastPubBlock of MoC's BTC provider).
  function getLastPublicationBlock() external view override returns (uint256) {
    uint256 a = flipUsd.getLastPublicationBlock();
    uint256 b = btcPriceProvider.getLastPublicationBlock();
    return a < b ? a : b;
  }
}
