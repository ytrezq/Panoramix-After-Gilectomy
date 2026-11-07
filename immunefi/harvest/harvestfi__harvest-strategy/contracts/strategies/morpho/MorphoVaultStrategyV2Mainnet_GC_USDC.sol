//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoVaultStrategyV2.sol";

contract MorphoVaultStrategyV2Mainnet_GC_USDC is MorphoVaultStrategyV2 {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address morphoVault = address(0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address morpho = address(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);
    address syrup = address(0x643C4E15d7d62Ad0aBeC4a9BD4b001aA3Ef52d66);
    MorphoVaultStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault,
      weth,
      address(0x15568A3361a2501181daC9309772cae14156CF9E)
    );
    rewardTokens = [morpho, syrup];
  }

  function finalizeUpgrade() external override onlyGovernance {
    address morpho = address(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);
    rewardTokens = [morpho];
    distributionTime[morpho] = 43200;
    _finalizeUpgrade();
  }
}
