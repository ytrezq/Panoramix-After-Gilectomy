// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IPriceProvider.sol";
import "./interfaces/IMocState.sol";
import "./interfaces/ICoinPairPrice.sol";

/// @title PriceProviderUsdPerBtc
/// @notice Provides USD/BTC as the inverse of BTC/USD from MoC's BTC price provider.
/// @dev
/// - BTC/USD comes from mocState.getBtcPriceProvider() (ICoinPairPrice).
/// - Both input and output use 18-decimal fixed point.
/// - If the BTC provider reports invalid or zero, returns (0,false).
contract PriceProviderUsdPerBtc is IPriceProvider {
  IMocState public immutable mocState;
  /// @notice Cached at deploy time for gas savings. Redeploy if MocState changes its btcPriceProvider.
  ICoinPairPrice public immutable btcPriceProvider;

  constructor(IMocState _mocState) {
    require(address(_mocState) != address(0), "mocState is zero");
    mocState = _mocState;
    btcPriceProvider = ICoinPairPrice(_mocState.getBtcPriceProvider());
  }

  /// @notice Returns USD/BTC with 18 decimals.
  function peek() external view override returns (bytes32, bool) {
    // 1) Read the pair rate from the BTC price provider: BTC/USD (18 decimals)
    (bytes32 pairRateBytes, bool pairRateIsValid) = btcPriceProvider.peek();
    uint256 pairRate = uint256(pairRateBytes); // BTC/USD

    // 2) Compute USD/BTC = 1e18 / (BTC/USD) = (1e18 * 1e18) / pairRate
    uint256 usdPerBtc = 0;
    if (pairRate != 0) {
      usdPerBtc = Math.mulDiv(1e18, 1e18, pairRate);
    }

    // 3) Validity reflects data trustworthiness (provider validity + non-zero result)
    bool overallValid = pairRateIsValid && pairRate != 0 && usdPerBtc != 0;

    // 4) Always return the computed value (if computable), even if validity is false
    return (bytes32(usdPerBtc), overallValid);
  }

  /// @notice Forwards last publication block from MoC's BTC provider.
  function getLastPublicationBlock() external view override returns (uint256) {
    return btcPriceProvider.getLastPublicationBlock();
  }
}
