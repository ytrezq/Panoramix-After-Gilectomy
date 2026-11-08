//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./SavingsDaiStrategy.sol";

contract SavingsDaiStrategyMainnet_DAI is SavingsDaiStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address savingsDai = address(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    SavingsDaiStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      savingsDai,
      weth
    );
  }
}