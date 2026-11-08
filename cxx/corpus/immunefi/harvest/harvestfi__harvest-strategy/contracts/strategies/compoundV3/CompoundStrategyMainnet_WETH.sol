// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./CompoundStrategy.sol";

contract CompoundStrategyMainnet_WETH is CompoundStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address market = address(0xA17581A9E3356d9A858b789D68B4d866e593aE94);
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
