// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

import "../BaseScript.sol";

abstract contract FinalizeScript is BaseScript {

  function DAO_AGENT() public view virtual returns (address) {
    return address(0);
  }

  function _execute(DeployerHelpers.Addresses memory addresses) internal override {
    address executor = isRealDaoDeployed() ? addresses.executorProd : addresses.executorMock;

    // If no DAO_AGENT is set, use the executor as the DAO_AGENT for the network
    address daoAgentAddress = DAO_AGENT() == address(0)
      ? executor
      : DAO_AGENT();

    // Transfer CrossChainController ownership to the DAO
    Ownable(addresses.crossChainController).transferOwnership(daoAgentAddress);

    // Transfer proxy admin ownership to the DAO
    Ownable(addresses.proxyAdmin).transferOwnership(daoAgentAddress);
  }
}

contract Ethereum is FinalizeScript {
  // https://docs.lido.fi/deployed-contracts/#dao-contracts Aragon Agent
  function DAO_AGENT() public view virtual override returns (address) {
    return isRealDaoDeployed() ? Constants.LIDO_DAO_AGENT : Constants.LIDO_DAO_AGENT_FAKE;
  }

  function TRANSACTION_NETWORK() public pure virtual override returns (uint256) {
    return ChainIds.ETHEREUM;
  }
}

contract Ethereum_testnet is FinalizeScript {
  // https://docs.lido.fi/deployed-contracts/sepolia#dao-contracts Aragon Agent
  function DAO_AGENT() public view virtual override returns (address) {
    return 0x32A0E5828B62AAb932362a4816ae03b860b65e83;
  }

  function TRANSACTION_NETWORK() public pure virtual override returns (uint256) {
    return TestNetChainIds.ETHEREUM_SEPOLIA;
  }
}

contract Ethereum_local is Ethereum {
  function isLocalFork() public pure virtual override returns (bool) {
    return true;
  }
}

contract Binance is FinalizeScript {
  function TRANSACTION_NETWORK() public pure virtual override returns (uint256) {
    return ChainIds.BNB;
  }
}

contract Binance_testnet is FinalizeScript {
  function TRANSACTION_NETWORK() public pure virtual override returns (uint256) {
    return TestNetChainIds.BNB_TESTNET;
  }
}

contract Binance_local is Binance {
  function isLocalFork() public pure virtual override returns (bool) {
    return true;
  }
}
