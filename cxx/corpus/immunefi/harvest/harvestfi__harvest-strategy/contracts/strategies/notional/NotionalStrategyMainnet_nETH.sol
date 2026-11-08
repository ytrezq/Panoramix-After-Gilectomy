//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./NotionalStrategy.sol";

contract NotionalStrategyMainnet_nETH is NotionalStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x3410463726a7A22ce0809367a4418FE82Fc31FD3);
    address nProxy = address(0x6e7058c91F85E0F6db4fc9da2CA41241f5e4263f);
    address note = address(0xCFEAead4947f0705A14ec42aC3D44129E1Ef3eD5);
    NotionalStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      nProxy,
      note
    );
    rewardTokens = [note];
  }
}
