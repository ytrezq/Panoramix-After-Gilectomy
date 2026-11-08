//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AaveFoldStrategy.sol";

contract AaveFoldStrategyMainnet_USDC_prime is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address aToken = address(0x2A1FBcb52Ed4d9b23daD17E1E8Aed4BB0E6079b8);
    address debtToken = address(0xeD90dE2D824Ee766c6Fd22E90b12e598f681dc9F);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address awstETH = address(0xC035a7cf15375cE2706766804551791aD035E0C2);
    AaveFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      debtToken,
      weth,
      0,
      1,
      1000,
      false
    );
    rewardTokens = [awstETH];
    isAToken[awstETH] = true;
  }
}
