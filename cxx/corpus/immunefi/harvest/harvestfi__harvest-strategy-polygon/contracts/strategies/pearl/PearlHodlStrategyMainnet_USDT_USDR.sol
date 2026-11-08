//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./PearlHodlStrategy.sol";

contract PearlHodlStrategyMainnet_USDT_USDR is PearlHodlStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x3f69055F203861abFd5D986dC81a2eFa7c915b0c);
    address gauge = address(0x89EF6e539F2Ac4eE817202f445aA69A3769A727C);
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
