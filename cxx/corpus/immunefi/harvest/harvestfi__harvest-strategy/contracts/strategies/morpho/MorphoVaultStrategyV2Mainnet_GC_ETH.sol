//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoVaultStrategyV2.sol";

contract MorphoVaultStrategyV2Mainnet_GC_ETH is MorphoVaultStrategyV2 {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address morphoVault = address(0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658);
    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address morpho = address(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);
    address ynETHx = address(0x657d9ABA1DBb59e53f9F3eCAA878447dCfC96dCb);
    MorphoVaultStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault,
      usdc,
      address(0x15568A3361a2501181daC9309772cae14156CF9E)
    );
    rewardTokens = [morpho, ynETHx];
  }

  function finalizeUpgrade() external override onlyGovernance {
    address morpho = address(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);
    rewardTokens = [morpho];
    distributionTime[morpho] = 43200;
    _finalizeUpgrade();
  }
}
