// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./YelStrategy.sol";

contract YelStrategyMainnet_YEL_WETH is YelStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xc83cE8612164eF7A13d17DDea4271DD8e8EEbE5d);
    address yel = address(0x7815bDa662050D84718B988735218CFfd32f75ea);
    YelStrategy.initializeStrategy(
      _storage,
      underlying,
      _vault,
      address(0xe7c8477C0c7AAaD6106EBDbbED3a5a2665b273b9), // master chef contract
      yel,
      1  // Pool id
    );
  }
}
