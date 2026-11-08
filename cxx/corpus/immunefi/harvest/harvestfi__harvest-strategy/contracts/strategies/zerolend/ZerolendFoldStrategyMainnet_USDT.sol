//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "../aave/AaveFoldStrategy.sol";

contract ZerolendFoldStrategyMainnet_USDT is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address aToken = address(0x4aEaFA9F24096bFe4b7354c16B2D34e2a7B92B78);
    address debtToken = address(0xE7a632694Dc4ac65583248aaf92FB5bECB54011e);
    address zero = address(0x2Da17fAf782ae884faf7dB2208BBC66b6E085C22);
    AaveFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      debtToken,
      zero,
      870,
      899,
      1000,
      true
    );
    rewardTokens = [zero];
  }
}
