//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./PearlHodlStrategy.sol";

contract PearlHodlStrategyMainnet_ETH_USDR is PearlHodlStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x74c64d1976157E7Aaeeed46EF04705F4424b27eC);
    address gauge = address(0x7D02A8b758791A03319102f81bF61E220F73e43D);
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
