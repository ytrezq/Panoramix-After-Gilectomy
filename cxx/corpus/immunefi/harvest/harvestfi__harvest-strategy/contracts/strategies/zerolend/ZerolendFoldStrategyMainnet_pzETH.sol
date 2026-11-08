//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "../aave/AaveFoldStrategy.sol";

contract ZerolendFoldStrategyMainnet_pzETH is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8c9532a60E0E7C6BbD2B2c1303F63aCE1c3E9811);
    address aToken = address(0xd9855847FFD9Bc0c5f3efFbEf67B558dBf090a71);
    address debtToken = address(0x8e3e54599d6F40c8306B895214f54882d98CD2b5);
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
