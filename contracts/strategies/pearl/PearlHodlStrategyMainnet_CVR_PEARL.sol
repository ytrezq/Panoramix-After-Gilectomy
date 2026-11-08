//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./PearlHodlStrategy.sol";

contract PearlHodlStrategyMainnet_CVR_PEARL is PearlHodlStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x700D6E1167472bDc312D9cBBdc7c58C7f4F45120);
    address gauge = address(0xe4A9ABD56c4c42807e70909Df5853347d20274cE);
    address pearl = address(0x7238390d5f6F64e67c3211C343A410E2A3DEc142);
    PearlHodlStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      pearl,
      address(0xCB2f2895208c36F38c9B13aB0C9e49Ad69B14e9d), //hodlVault
      address(0)  //potPool
    );
  }
}
