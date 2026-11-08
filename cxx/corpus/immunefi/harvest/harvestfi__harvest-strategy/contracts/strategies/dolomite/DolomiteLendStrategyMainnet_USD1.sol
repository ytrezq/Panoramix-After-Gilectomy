//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./DolomiteLendStrategy.sol";

contract DolomiteLendStrategyMainnet_USD1 is DolomiteLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d);
    address wlfi = address(0xdA5e1988097297dCdc1f90D4dFE7909e847CBeF6);
    DolomiteLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      address(0x003Ca23Fd5F0ca87D01F6eC6CD14A8AE60c2b97D),
      address(0xf8b2c637A68cF6A17b1DF9F8992EeBeFf63d2dFf),
      1,
      wlfi
    );
    rewardTokens = [wlfi];
  }
}