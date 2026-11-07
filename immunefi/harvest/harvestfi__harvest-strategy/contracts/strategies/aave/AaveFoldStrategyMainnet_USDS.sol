//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AaveFoldStrategy.sol";

contract AaveFoldStrategyMainnet_USDS is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xdC035D45d973E3EC169d2276DDab16f1e407384F);
    address aToken = address(0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259);
    address debtToken = address(0x490E0E6255bF65b43E2e02F7acB783c5e04572Ff);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    AaveFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      debtToken,
      weth,
      740,
      749,
      1000,
      true
    );
    rewardTokens = [aToken];
  }
}
