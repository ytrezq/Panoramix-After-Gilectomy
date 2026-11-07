//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./UniswapGammaStrategy.sol";

contract UniswapGammaStrategyMainnet_WMATIC_USDC is UniswapGammaStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xE583b04b9a8F576aa7F17ECc6eB662499B5A8793);
    address staking = address(0x144Dc3396976Aa0955Ca6Ee1aC4a2f9842198BA0);
    address wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address uniProxy = address(0x48975Ea6aA25914927241C3A9F493BfEEb8CA591);
    UniswapGammaStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      staking,
      wmatic,
      uniProxy
    );
    rewardTokens = [wmatic];
  }
}