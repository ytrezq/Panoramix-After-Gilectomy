//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "../aave/AaveFoldStrategy.sol";

contract ZerolendFoldStrategyMainnet_weETH is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
    address aToken = address(0x84E55c6Bc5B7e9505d87b3Df6Ceff7753e15A0c5);
    address debtToken = address(0x53C94fd63Ef4001d45744c311d6BBe2171D4a11e);
    address zero = address(0x2Da17fAf782ae884faf7dB2208BBC66b6E085C22);
    AaveFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      debtToken,
      zero,
      670,
      699,
      1000,
      true
    );
    rewardTokens = [zero];
  }
}
