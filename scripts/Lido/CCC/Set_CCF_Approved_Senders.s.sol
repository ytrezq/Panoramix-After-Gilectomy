// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ICrossChainForwarder} from '../../../src/contracts/interfaces/ICrossChainForwarder.sol';

import '../BaseScript.sol';

/**
 * @notice This script needs to be implemented from where the senders are known
 */
abstract contract BaseSetCCFApprovedSenders is BaseScript {
  function getSendersToApprove(DeployerHelpers.Addresses memory addresses) public view virtual returns (address[] memory);

  function _execute(DeployerHelpers.Addresses memory addresses) internal override {
    ICrossChainForwarder(addresses.crossChainController).approveSenders(getSendersToApprove(addresses));
  }
}

contract Ethereum is BaseSetCCFApprovedSenders {
  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return ChainIds.ETHEREUM;
  }

  function getSendersToApprove(DeployerHelpers.Addresses memory addresses) public view override returns (address[] memory) {
    address[] memory senders = new address[](1);

    // https://docs.lido.fi/deployed-contracts/#dao-contracts - Aragon Agent
    senders[0] = isRealDaoDeployed() ? Constants.LIDO_DAO_AGENT : Constants.LIDO_DAO_AGENT_FAKE;

    return senders;
  }
}

contract Ethereum_testnet is BaseSetCCFApprovedSenders {
  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return TestNetChainIds.ETHEREUM_SEPOLIA;
  }

  function getSendersToApprove(DeployerHelpers.Addresses memory addresses) public view override returns (address[] memory) {
    address[] memory senders = new address[](1);

    // https://docs.lido.fi/deployed-contracts/sepolia#dao-contracts - Aragon Agent
    senders[0] = 0x32A0E5828B62AAb932362a4816ae03b860b65e83;

    return senders;
  }
}

contract Ethereum_local is Ethereum {
  function isLocalFork() public view override returns (bool) {
    return true;
  }
}
