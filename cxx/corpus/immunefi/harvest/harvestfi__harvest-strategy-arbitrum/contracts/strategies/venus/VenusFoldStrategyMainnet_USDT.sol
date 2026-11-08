//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./VenusFoldStrategy.sol";

contract VenusFoldStrategyMainnet_USDT is VenusFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address cToken = address(0xB9F9117d4200dC296F9AcD1e8bE1937df834a2fD);
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
