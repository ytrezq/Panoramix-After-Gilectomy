// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./CompoundStrategy.sol";

contract CompoundStrategyMainnet_wstETH is CompoundStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address market = address(0x3D0bb1ccaB520A66e607822fC55BC921738fAFE3);
    address rewards = address(0x1B0e765F6224C21223AeA2af16c1C46E38885a40);
    address comp = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    CompoundStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      market,
      rewards,
      comp
    );
    rewardTokens = [comp];
  }
}
