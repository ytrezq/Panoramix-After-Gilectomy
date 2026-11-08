//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "../aave/AaveFoldStrategy.sol";

contract ZerolendFoldStrategyMainnet_SolvBTCBNN is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xd9D920AA40f578ab794426F5C90F6C731D159DEf);
    address aToken = address(0x5d9155032e3Cd6bb2C6b6A448b79Bacb0fF01Be9);
    address debtToken = address(0x250d1435b02ddce933f73317feeBA58F78861108);
    address zero = address(0x2Da17fAf782ae884faf7dB2208BBC66b6E085C22);
    AaveFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      debtToken,
      zero,
      0,
      1,
      1000,
      false
    );
    rewardTokens = [zero];
  }
}
