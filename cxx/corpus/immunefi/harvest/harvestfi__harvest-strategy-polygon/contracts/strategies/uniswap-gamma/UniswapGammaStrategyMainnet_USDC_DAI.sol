//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./UniswapGammaStrategy.sol";

contract UniswapGammaStrategyMainnet_USDC_DAI is UniswapGammaStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x831231E16D95Eb3D54Bf2C80968F35A5F4483447);
    address staking = address(0xf45c2Cb5E8145E820365618188E54F869A92B7Cb);
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