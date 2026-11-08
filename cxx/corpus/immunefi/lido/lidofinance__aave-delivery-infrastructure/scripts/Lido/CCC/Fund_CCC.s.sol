// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../BaseScript.sol';

abstract contract BaseFundCrossChainController is BaseScript {
  function getAmountToFund() public view virtual returns (uint256) {
    return 500000000000000000;
  }

  function _execute(DeployerHelpers.Addresses memory addresses) internal override {
    (bool success, ) = addresses.crossChainController.call{value: getAmountToFund()}(new bytes(0));
    require(success, 'ETH_TRANSFER_FAILED');
  }
}

contract Ethereum is BaseFundCrossChainController {
  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return ChainIds.ETHEREUM;
  }
}

contract Ethereum_testnet is BaseFundCrossChainController {
  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return TestNetChainIds.ETHEREUM_SEPOLIA;
  }
}

contract Ethereum_local is Ethereum {
  function isLocalFork() public pure override returns (bool) {
    return true;
  }
}

contract Binance is BaseFundCrossChainController {
  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return ChainIds.BNB;
  }
}

contract Binance_testnet is BaseFundCrossChainController {
  function getAmountToFund() public view override returns (uint256) {
    return 100000000000000000;
  }

  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return TestNetChainIds.BNB_TESTNET;
  }
}

contract Binance_local is Binance {
  function isLocalFork() public pure override returns (bool) {
    return true;
  }
}
