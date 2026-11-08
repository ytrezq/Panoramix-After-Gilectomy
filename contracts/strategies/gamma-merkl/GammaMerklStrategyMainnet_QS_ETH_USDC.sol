//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./GammaMerklStrategy.sol";

contract GammaMerklStrategyMainnet_QS_ETH_USDC is GammaMerklStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x3974FbDC22741A1632E024192111107b202F214f);
    address quick = address(0xB5C064F955D8e7F38fE0460C556a72987494eE17);
    GammaMerklStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      quick,
      address(0xA42d55074869491D60Ac05490376B74cF19B00e6) //UniProxy
    );
    rewardTokens = [quick];
  }
}
