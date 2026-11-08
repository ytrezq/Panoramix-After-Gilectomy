//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./VenusFoldStrategy.sol";

contract VenusFoldStrategyMainnet_ETH_core is VenusFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address cToken = address(0x68a34332983f4Bf866768DD6D6E638b02eF5e1f0);
    address comptroller = address(0x317c1A5739F39046E20b08ac9BeEa3f10fD43326);
    address xvs = address(0xc1Eb7689147C81aC840d4FF0D298489fc7986d52);
    VenusFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      cToken,
      comptroller,
      xvs,
      730,
      749,
      1000,
      true
    );
    rewardTokens = [xvs];
  }
}
