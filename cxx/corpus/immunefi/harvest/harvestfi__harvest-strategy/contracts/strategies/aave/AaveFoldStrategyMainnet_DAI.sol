//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AaveFoldStrategy.sol";

contract AaveFoldStrategyMainnet_DAI is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address aToken = address(0x018008bfb33d285247A21d44E50697654f754e63);
    address debtToken = address(0xcF8d0c70c850859266f5C338b38F9D663181C314);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    AaveFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      debtToken,
      weth,
      0,
      749,
      1000,
      false
    );
    rewardTokens = [weth];
  }
}
