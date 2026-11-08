// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./IdleStrategy.sol";

contract IdleStrategyMainnet_DAI is IdleStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address idleToken = address(0x3fE7940616e5Bc47b0775a0dccf6237893353bB4);
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
