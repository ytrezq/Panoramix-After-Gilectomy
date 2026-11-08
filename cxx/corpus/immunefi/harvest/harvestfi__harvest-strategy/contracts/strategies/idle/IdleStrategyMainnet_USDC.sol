// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./IdleStrategy.sol";

contract IdleStrategyMainnet_USDC is IdleStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address idleToken = address(0x5274891bEC421B39D23760c04A6755eCB444797C);
    address idle = address(0x875773784Af8135eA0ef43b5a374AaD105c5D39e);
    IdleStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      idleToken,
      idle,
      address(0xF066789028fE31D4f53B69B81b328B8218Cc0641),
      true
    );
  }
}
