// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IProposalGenericExecutor} from '../../src/interfaces/IProposalGenericExecutor.sol';

/**
 * @dev Mock payload that writes to a storage variable during execution.
 * When delegatecalled by an executor, this modifies the executor's storage.
 */
contract PayloadWithStorage is IProposalGenericExecutor {
  uint256 internal _randomStorageVariable;

  function execute() external {
    _randomStorageVariable = 42;
  }
}
