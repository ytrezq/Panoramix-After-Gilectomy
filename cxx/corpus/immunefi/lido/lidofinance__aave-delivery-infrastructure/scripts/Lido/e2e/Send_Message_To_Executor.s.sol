// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ICrossChainForwarder} from '../../../src/contracts/interfaces/ICrossChainForwarder.sol';

import '../BaseScript.sol';

abstract contract BaseSendMessageToExecutor is BaseScript {
  function DESTINATION_NETWORK() public view virtual returns (uint256);

  function getDestinationAddress() public view virtual returns (address) {
    return _getAddresses(DESTINATION_NETWORK()).executorMock;
  }

  function getGasLimit() public view virtual returns (uint256) {
    return 300_000;
  }

  function getMessage() public view virtual returns (bytes memory) {
    return abi.encode('This is a test message...');
  }

  function _execute(DeployerHelpers.Addresses memory addresses) internal override {
    uint256 destinationChainId = _getAddresses(DESTINATION_NETWORK()).chainId;

    ICrossChainForwarder(addresses.crossChainController).forwardMessage(
      destinationChainId,
      getDestinationAddress(),
      getGasLimit(),
      getMessage()
    );
  }
}

contract Ethereum is BaseSendMessageToExecutor {
  function getMessage() public view virtual override returns (bytes memory) {
    return abi.encode('This is a test message from the Ethereum mainnet to the Polygon mainnet...');
  }

  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return ChainIds.ETHEREUM;
  }

  function DESTINATION_NETWORK() public pure override returns (uint256) {
    return ChainIds.POLYGON;
  }
}

contract Ethereum_testnet is BaseSendMessageToExecutor {
  function getMessage() public view virtual override returns (bytes memory) {
    address[] memory addresses = new address[](1);
    addresses[0] = _getAddresses(DESTINATION_NETWORK()).mockDestination;

    uint256[] memory values = new uint256[](1);
    values[0] = uint256(0);

    string[] memory signatures = new string[](1);
    signatures[0] = 'test(string)';

    bytes[] memory calldatas = new bytes[](1);
    string memory message = string.concat(
      'This is an encoded message from ',
      Strings.toString(TRANSACTION_NETWORK()),
      ' to ',
      Strings.toString(DESTINATION_NETWORK()),
      '...'
    );

    calldatas[0] = abi.encode(message);

    bool[] memory withDelegatecalls = new bool[](1);
    withDelegatecalls[0] = false;

    return abi.encode(addresses, values, signatures, calldatas, withDelegatecalls);
  }

  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return TestNetChainIds.ETHEREUM_SEPOLIA;
  }

  function DESTINATION_NETWORK() public pure override returns (uint256) {
    return TestNetChainIds.BNB_TESTNET;
  }
}
