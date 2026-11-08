//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./AaveSupplyStrategy.sol";

contract AaveSupplyStrategyMainnet_USDC is AaveSupplyStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
    address aToken = address(0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD);
    AaveSupplyStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken
    );
  }
}
