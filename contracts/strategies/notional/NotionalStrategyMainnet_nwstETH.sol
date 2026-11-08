//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./NotionalStrategy.sol";

contract NotionalStrategyMainnet_nwstETH is NotionalStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x06D45ef1f8b3C37b0de66f156B11F10b4837619A);
    address nProxy = address(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address note = address(0x019bE259BC299F3F653688c7655C87F998Bc7bC1);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    NotionalStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      nProxy,
      note
    );
    rewardTokens = [note,arb];
  }
}
