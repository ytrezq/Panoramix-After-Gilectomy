//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./EulerLendStrategy.sol";

contract EulerLendStrategyMainnet_TF_USDC is EulerLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address fToken = address(0x44C10DA836d2aBe881b77bbB0b3DCE5f85C0C1Cc);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    EulerLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      fToken,
      arb
    );
    rewardTokens = [arb];
    distributionTime[arb] = 86400;
  }
}