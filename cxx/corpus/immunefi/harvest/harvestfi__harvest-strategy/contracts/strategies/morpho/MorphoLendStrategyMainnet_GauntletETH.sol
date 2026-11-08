//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoLendStrategy.sol";

contract MorphoLendStrategyMainnet_GauntletETH is MorphoLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address morphoVault = address(0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658);
    MorphoLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault
    );
  }
}