//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./VenusFoldStrategy.sol";

contract VenusFoldStrategyMainnet_ARB is VenusFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address cToken = address(0xAeB0FEd69354f34831fe1D16475D9A83ddaCaDA6);
    address comptroller = address(0x317c1A5739F39046E20b08ac9BeEa3f10fD43326);
    address xvs = address(0xc1Eb7689147C81aC840d4FF0D298489fc7986d52);
    VenusFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      cToken,
      comptroller,
      xvs,
      150,
      549,
      1000,
      true
    );
    rewardTokens = [xvs];
  }
}
