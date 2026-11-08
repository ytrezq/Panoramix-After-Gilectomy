//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "../aave/AaveFoldStrategy.sol";

contract ZerolendFoldStrategyMainnet_LBTC is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8236a87084f8B84306f72007F36F2618A5634494);
    address aToken = address(0xcABB8fa209CcdF98a7A0DC30b1979fC855Cb3Eb3);
    address debtToken = address(0x028cf048867D37566b60Cee7822C857441DaC9E7);
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
