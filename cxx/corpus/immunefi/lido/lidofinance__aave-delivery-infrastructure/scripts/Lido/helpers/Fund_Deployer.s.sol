// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../BaseScript.sol';

abstract contract FundDeployer is BaseScript {
  function _execute(DeployerHelpers.Addresses memory addresses) internal override {
    uint256 value = 10 ether;

    // Deployer
    (bool success, ) = payable(msg.sender).call{value: value}(new bytes(0));

    // Voter
    (success, ) = payable(msg.sender).call{value: value}(new bytes(0));
  }
}

contract Ethereum is FundDeployer {
  function TRANSACTION_NETWORK() public pure virtual override returns (uint256) {
    return ChainIds.ETHEREUM;
  }
}

contract Ethereum_testnet is FundDeployer {
  function TRANSACTION_NETWORK() public pure virtual override returns (uint256) {
    return TestNetChainIds.ETHEREUM_SEPOLIA;
  }
}

contract Ethereum_local is Ethereum {
  function isLocalFork() public pure virtual override returns (bool) {
    return true;
  }
}

contract Binance is FundDeployer {
  function TRANSACTION_NETWORK() public pure virtual override returns (uint256) {
    return ChainIds.BNB;
  }
}

contract Binance_testnet is FundDeployer {
  function TRANSACTION_NETWORK() public pure virtual override returns (uint256) {
    return TestNetChainIds.BNB_TESTNET;
  }
}

contract Binance_local is Binance {
  function isLocalFork() public pure virtual override returns (bool) {
    return true;
  }
}

