//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./SiloVaultStrategy.sol";

contract SiloVaultStrategyMainnet_OP_USDC is SiloVaultStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address fToken = address(0x2514A2Ce842705EAD703d02fABFd8250BfCfb8bd);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    SiloVaultStrategy.initializeBaseStrategy(
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