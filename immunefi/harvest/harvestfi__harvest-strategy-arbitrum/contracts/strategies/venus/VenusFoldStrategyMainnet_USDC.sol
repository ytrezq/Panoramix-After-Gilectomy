//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./VenusFoldStrategy.sol";

contract VenusFoldStrategyMainnet_USDC is VenusFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address cToken = address(0x7D8609f8da70fF9027E9bc5229Af4F6727662707);
    address comptroller = address(0x317c1A5739F39046E20b08ac9BeEa3f10fD43326);
    address xvs = address(0xc1Eb7689147C81aC840d4FF0D298489fc7986d52);
    VenusFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      cToken,
      comptroller,
      xvs,
      0,
      779,
      1000,
      false
    );
    rewardTokens = [xvs];
  }
}
