//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "../aave/AaveFoldStrategy.sol";

contract ZerolendFoldStrategyMainnet_WBTC is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address aToken = address(0x1d5f4e8c842a5655f9B722cAC40C6722794b75f5);
    address debtToken = address(0xa2962376f68eDb09b08F9B433F4ecae8D3217Eec);
    address zero = address(0x2Da17fAf782ae884faf7dB2208BBC66b6E085C22);
    AaveFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      debtToken,
      zero,
      0,
      799,
      1000,
      false
    );
    rewardTokens = [zero];
  }
}
