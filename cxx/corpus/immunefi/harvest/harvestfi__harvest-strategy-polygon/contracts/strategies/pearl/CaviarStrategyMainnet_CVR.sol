//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CaviarStrategy.sol";

contract CaviarStrategyMainnet_CVR is CaviarStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6AE96Cc93331c19148541D4D2f31363684917092);
    address rewards = address(0x83C5022745B2511Bd199687a42D27BEFd025A9A9);
    address usdr = address(0x40379a439D4F6795B6fc9aa5687dB461677A2dBa);
    CaviarStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewards,
      usdr
    );
    rewardTokens = [underlying, usdr];
  }
}
