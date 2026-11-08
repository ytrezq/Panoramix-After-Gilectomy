// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./CompoundStrategy.sol";

contract CompoundStrategyMainnet_USDC is CompoundStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address market = address(0xc3d688B66703497DAA19211EEdff47f25384cdc3);
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
