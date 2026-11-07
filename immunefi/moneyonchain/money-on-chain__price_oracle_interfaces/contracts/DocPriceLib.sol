// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./interfaces/IMocState.sol";

/// @title DocPriceLib
/// @notice Helper functions to derive DOC/USD and DOC/RBTC from MoC bucket balances and BTC/USD.
library DocPriceLib {
  uint256 internal constant MOC_PRECISION = 1e18;
  uint256 internal constant MOC_PRECISION_SQUARED = 1e36;
  bytes32 internal constant BUCKET_C0 = "C0";

  /// @notice DOC/USD with 18 decimals. Capped at 1.0 for senior-claim behavior.
  /// @dev Formula: min(1, (nBTC * BTC/USD) / nDOC)
  function docUsdPriceSafe(IMocState mocState, uint256 btcPriceInUsd) internal view returns (uint256) {
    if (btcPriceInUsd == 0) {
      return 0;
    }

    uint256 nDoc = mocState.getBucketNDoc(BUCKET_C0);
    if (nDoc == 0) {
      return MOC_PRECISION;
    }

    uint256 nRbtc = mocState.getBucketNBTC(BUCKET_C0);
    uint256 uncappedDocPriceInUsd = (nRbtc * btcPriceInUsd) / nDoc;
    return uncappedDocPriceInUsd > MOC_PRECISION ? MOC_PRECISION : uncappedDocPriceInUsd;
  }

  /// @notice DOC/RBTC with 18 decimals.
  /// @dev Formula: min(nBTC/nDOC, USD/BTC) where USD/BTC = 1/(BTC/USD).
  function docRbtcPriceSafe(IMocState mocState, uint256 btcPriceInUsd) internal view returns (uint256) {
    if (btcPriceInUsd == 0) {
      return 0;
    }

    uint256 nDoc = mocState.getBucketNDoc(BUCKET_C0);
    uint256 usdPerBtc = MOC_PRECISION_SQUARED / btcPriceInUsd;
    if (nDoc == 0) {
      return usdPerBtc;
    }

    uint256 nRbtc = mocState.getBucketNBTC(BUCKET_C0);
    uint256 bucketDocRbtc = (nRbtc * MOC_PRECISION) / nDoc;
    return bucketDocRbtc > usdPerBtc ? usdPerBtc : bucketDocRbtc;
  }
}
