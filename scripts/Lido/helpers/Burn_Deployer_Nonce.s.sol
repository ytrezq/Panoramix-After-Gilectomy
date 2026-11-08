// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../BaseScript.sol';

abstract contract BurnDeployerNonce is BaseScript {
  function _execute(DeployerHelpers.Addresses memory addresses) internal override {
    uint8 txAmount = 20;
    for (uint256 i = 0; i < txAmount; i++) {
      (bool success, ) = msg.sender.call{value: 0}(new bytes(0));
    }
  }
}

contract Binance is BurnDeployerNonce {
  function TRANSACTION_NETWORK() public pure virtual override returns (uint256) {
    return ChainIds.BNB;
  }
}

contract Binance_testnet is BurnDeployerNonce {
  function TRANSACTION_NETWORK() public pure virtual override returns (uint256) {
    return TestNetChainIds.BNB_TESTNET;
  }
}

contract Binance_local is Binance {
  function isLocalFork() public pure virtual override returns (bool) {
    return true;
  }
}
