
//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./CamelotV3Strategy.sol";

contract CamelotV3StrategyMainnet_WBTC_ETH is CamelotV3Strategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x56c87c3892d3917895bAe1A4cAcf6ea23a4DB84d);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    CamelotV3Strategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      address(0xFA10759780304c2B8d34B051C039899dFBbcad7f),
      address(0),
      address(0x1F1Ca4e8236CD13032653391dB7e9544a6ad123E) //UniProxy
    );
    rewardTokens = [grail];
  }
}
