//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./AaveSupplyStrategy.sol";

contract AaveSupplyStrategyMainnet_EURS is AaveSupplyStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xE111178A87A3BFf0c8d18DECBa5798827539Ae99);
    address aToken = address(0x38d693cE1dF5AaDF7bC62595A37D667aD57922e5);
    AaveSupplyStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken
    );
  }
}
