//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CompoundStrategy.sol";

contract CompoundStrategyMainnet_USDT is CompoundStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);
    address market = address(0xaeB318360f27748Acb200CE616E389A6C9409a07);
    address rewards = address(0x45939657d1CA34A8FA39A924B71D28Fe8431e581);
    address comp = address(0x8505b9d2254A7Ae468c0E9dd10Ccea3A837aef5c);
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
