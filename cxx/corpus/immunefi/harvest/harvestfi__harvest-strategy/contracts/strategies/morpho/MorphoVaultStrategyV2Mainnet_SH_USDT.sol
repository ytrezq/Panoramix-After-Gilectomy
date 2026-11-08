//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoVaultStrategyV2.sol";

contract MorphoVaultStrategyV2Mainnet_SH_USDT is MorphoVaultStrategyV2 {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address morphoVault = address(0xA0804346780b4c2e3bE118ac957D1DB82F9d7484);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address morpho = address(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);
    MorphoVaultStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault,
      weth,
      address(0x15568A3361a2501181daC9309772cae14156CF9E)
    );
    rewardTokens = [morpho];
  }

  function finalizeUpgrade() external override onlyGovernance {
    address morpho = address(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);
    rewardTokens = [morpho];
    distributionTime[morpho] = 43200;
    _finalizeUpgrade();
  }
}
