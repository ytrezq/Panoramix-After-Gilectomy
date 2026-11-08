//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "../aave/AaveFoldStrategy.sol";

contract ZerolendFoldStrategyMainnet_eBTC is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x657e8C867D8B37dCC18fA4Caead9C45EB088C642);
    address aToken = address(0x52bB650211e8a6986287306A4c09B73A9Affd5e9);
    address debtToken = address(0x57C0FbFEfA18c6b438A4eb3c01354640017BF154);
    address zero = address(0x2Da17fAf782ae884faf7dB2208BBC66b6E085C22);
    AaveFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      debtToken,
      zero,
      0,
      899,
      1000,
      false
    );
    rewardTokens = [zero];
  }
}
