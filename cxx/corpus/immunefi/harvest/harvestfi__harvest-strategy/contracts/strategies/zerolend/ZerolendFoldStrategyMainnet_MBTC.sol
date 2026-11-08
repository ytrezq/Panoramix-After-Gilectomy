//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "../aave/AaveFoldStrategy.sol";

contract ZerolendFoldStrategyMainnet_MBTC is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x2F913C820ed3bEb3a67391a6eFF64E70c4B20b19);
    address aToken = address(0xffB7Fea7567E5a84656E4fcb66a743A8C62EEF36);
    address debtToken = address(0x7f9CF95f4B8cbDC754A797da420eaEd2C6cD586A);
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
