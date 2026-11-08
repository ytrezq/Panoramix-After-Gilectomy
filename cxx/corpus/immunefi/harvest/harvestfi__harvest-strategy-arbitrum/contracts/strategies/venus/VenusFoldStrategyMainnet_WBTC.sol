//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./VenusFoldStrategy.sol";

contract VenusFoldStrategyMainnet_WBTC is VenusFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    address cToken = address(0xaDa57840B372D4c28623E87FC175dE8490792811);
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
      749,
      1000,
      false
    );
    rewardTokens = [xvs];
  }
}
