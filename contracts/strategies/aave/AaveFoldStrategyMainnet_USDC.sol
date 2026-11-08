//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AaveFoldStrategy.sol";

contract AaveFoldStrategyMainnet_USDC is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address aToken = address(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
    address debtToken = address(0x72E95b8931767C79bA4EeE721354d6E99a61D004);
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
