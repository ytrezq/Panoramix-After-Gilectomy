// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./CompoundStrategy.sol";

contract CompoundStrategyMainnet_USDT is CompoundStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address market = address(0x3Afdc9BCA9213A35503b077a6072F3D0d5AB0840);
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
