//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoVaultStrategyV2.sol";

contract MorphoVaultStrategyV2Mainnet_SP_USDC is MorphoVaultStrategyV2 {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address morphoVault = address(0x40DD8f13395a1dD5C8aB5B6a7ecDb4F782838E45);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address morpho = address(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);
    MorphoVaultStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault,
      weth,
      address(0)
    );
    rewardTokens = [morpho];
    distributionTime[morpho] = 86400;
  }
}
