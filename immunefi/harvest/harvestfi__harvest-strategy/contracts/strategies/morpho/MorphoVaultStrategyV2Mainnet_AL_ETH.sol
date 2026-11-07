//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoVaultStrategyV2.sol";

contract MorphoVaultStrategyV2Mainnet_AL_ETH is MorphoVaultStrategyV2 {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address morphoVault = address(0x47fe8Ab9eE47DD65c24df52324181790b9F47EfC);
    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address morpho = address(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);
    MorphoVaultStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault,
      usdc,
      address(0x15568A3361a2501181daC9309772cae14156CF9E)
    );
    rewardTokens = [morpho];
  }
}
