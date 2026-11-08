//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./UniswapGammaStrategy.sol";

contract UniswapGammaStrategyMainnet_USDC_USDT is UniswapGammaStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8c6FE430cf06e56BE7c092AD3A249BF0BcB388B9);
    address staking = address(0xABc34b7cBE6e850694A1D8cE7C5FE88e2f1E7097);
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