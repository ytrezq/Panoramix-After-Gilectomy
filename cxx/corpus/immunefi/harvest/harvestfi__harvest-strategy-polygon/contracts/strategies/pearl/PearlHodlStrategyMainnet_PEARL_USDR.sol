//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./PearlHodlStrategy.sol";

contract PearlHodlStrategyMainnet_PEARL_USDR is PearlHodlStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xf68c20d6C50706f6C6bd8eE184382518C93B368c);
    address gauge = address(0x79d5Ae0DF5C3A31941c3Afe0021F25e2929E205d);
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
