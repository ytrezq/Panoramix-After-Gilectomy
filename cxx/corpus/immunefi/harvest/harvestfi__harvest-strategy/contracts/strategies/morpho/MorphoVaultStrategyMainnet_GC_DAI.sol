//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoVaultStrategy.sol";

contract MorphoVaultStrategyMainnet_GC_DAI is MorphoVaultStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address morphoVault = address(0x500331c9fF24D9d11aee6B07734Aa72343EA74a5);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address morpho = address(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);
    MorphoVaultStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault,
      weth
    );
    rewardTokens = [morpho];
  }
}
