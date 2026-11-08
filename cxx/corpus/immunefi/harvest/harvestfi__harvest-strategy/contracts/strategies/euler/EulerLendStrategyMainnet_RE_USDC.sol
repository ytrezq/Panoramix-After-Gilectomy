//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./EulerLendStrategy.sol";

contract EulerLendStrategyMainnet_RE_USDC is EulerLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address eulerVault = address(0xcBC9B61177444A793B85442D3a953B90f6170b7D);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    EulerLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      eulerVault,
      weth
    );
  }
}