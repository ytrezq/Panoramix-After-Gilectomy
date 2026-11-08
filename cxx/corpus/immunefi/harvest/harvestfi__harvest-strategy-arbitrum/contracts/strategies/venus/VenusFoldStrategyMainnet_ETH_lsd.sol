//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./VenusFoldStrategy.sol";

contract VenusFoldStrategyMainnet_ETH_lsd is VenusFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address cToken = address(0x39D6d13Ea59548637104E40e729E4aABE27FE106);
    address comptroller = address(0x52bAB1aF7Ff770551BD05b9FC2329a0Bf5E23F16);
    address xvs = address(0xc1Eb7689147C81aC840d4FF0D298489fc7986d52);
    VenusFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      cToken,
      comptroller,
      xvs,
      0,
      1,
      1000,
      false
    );
    rewardTokens = [xvs];
  }
}
