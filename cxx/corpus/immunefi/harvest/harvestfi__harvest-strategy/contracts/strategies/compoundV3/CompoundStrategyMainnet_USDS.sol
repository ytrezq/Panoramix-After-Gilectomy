// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./CompoundStrategy.sol";

contract CompoundStrategyMainnet_USDS is CompoundStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xdC035D45d973E3EC169d2276DDab16f1e407384F);
    address market = address(0x5D409e56D886231aDAf00c8775665AD0f9897b56);
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
