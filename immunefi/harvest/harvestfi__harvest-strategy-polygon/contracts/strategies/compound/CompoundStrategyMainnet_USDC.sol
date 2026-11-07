//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CompoundStrategy.sol";

contract CompoundStrategyMainnet_USDC is CompoundStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    address market = address(0xF25212E676D1F7F89Cd72fFEe66158f541246445);
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
