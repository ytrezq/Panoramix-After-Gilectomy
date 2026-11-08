//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./UniswapGammaStrategy.sol";

contract UniswapGammaStrategyMainnet_USDC_WETH is UniswapGammaStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x1Fd452156b12FB5D74680C5Ff166303E6dd12A78);
    address staking = address(0x4215bc71b52ef6D0D31046d66eE0eD9A84744Eb6);
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