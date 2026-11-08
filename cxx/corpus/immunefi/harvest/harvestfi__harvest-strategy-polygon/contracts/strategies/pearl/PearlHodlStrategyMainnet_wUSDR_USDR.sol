//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./PearlHodlStrategy.sol";

contract PearlHodlStrategyMainnet_wUSDR_USDR is PearlHodlStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8711a1a52c34EDe8E61eF40496ab2618a8F6EA4B);
    address gauge = address(0x03Fa7A2628D63985bDFe07B95d4026663ED96065);
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
