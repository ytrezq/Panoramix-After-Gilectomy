// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./IdleStrategy.sol";

contract IdleStrategyMainnet_USDT is IdleStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address idleToken = address(0xF34842d05A1c888Ca02769A633DF37177415C2f8);
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
