// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./interfaces/IMocState.sol";

/**
 * @title BproPriceLib
 * @notice Helper functions to calculate BPRO/USD prices with a maybe outdated BTC/USD price
 *
 * @dev
 * This library implement the mocState bproUsdPrice and bproTecPrice methods.
 * We can't use those directly because they rely on getBitcoinPrice internally.
 * getBitcoinPrice reverts when the price is invalid.
 * This peek method should not revert, and instead use the old price but mark it as invalid.
 * Invalid prices are still useful for ballpark suggestions such as initializing the EMA on a deployment.
 */

library BproPriceLib {
  uint256 internal constant MOC_PRECISION = 1e18;
  uint256 internal constant RESERVE_PRECISION = 1e18;
  bytes32 internal constant BUCKET_C0 = "C0";

  function bproUsdPriceSafe(IMocState mocState, bytes32 btcPrice) internal view returns (uint256) {
    return (uint256(btcPrice) * bproTecPriceHelper(mocState, btcPrice)) / MOC_PRECISION; // 18 decimals
  }

  function bproTecPriceHelper(
    IMocState mocState,
    bytes32 btcPrice
  ) internal view returns (uint256) {
    if (mocState.state() == IMocState.States.Liquidated) {
      return 0;
    }

    uint256 nBpro = mocState.getBucketNBPro(BUCKET_C0);
    if (nBpro == 0) {
      return MOC_PRECISION;
    }

    uint256 nRbtc = mocState.getBucketNBTC(BUCKET_C0);
    uint256 lockedRbtc = lockedBitcoin(btcPrice, mocState.getBucketNDoc(BUCKET_C0));
    if (nRbtc <= lockedRbtc) {
      return 0;
    }

    // ([RES] - [RES]) * [MOC] / [MOC]
    return ((nRbtc - lockedRbtc) * MOC_PRECISION) / nBpro;
  }

  function lockedBitcoin(bytes32 btcPrice, uint256 nDoc) internal pure returns (uint256) {
    return (nDoc * RESERVE_PRECISION) / uint256(btcPrice);
  }
}
