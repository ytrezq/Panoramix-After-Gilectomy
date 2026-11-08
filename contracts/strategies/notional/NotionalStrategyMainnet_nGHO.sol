//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./NotionalStrategy.sol";

contract NotionalStrategyMainnet_nGHO is NotionalStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x2F7350Cb5e434C2d177922110c7e314953B84Afc);
    address nProxy = address(0x6e7058c91F85E0F6db4fc9da2CA41241f5e4263f);
    address note = address(0xCFEAead4947f0705A14ec42aC3D44129E1Ef3eD5);
    address gho = address(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    NotionalStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      nProxy,
      weth
    );
    rewardTokens = [note, gho];
  }
}
