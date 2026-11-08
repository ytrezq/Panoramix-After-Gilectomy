// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EthereumScript} from 'aave-helpers/ScriptUtils.sol';
import {ProposalPayloadStkAave, ProposalPayloadStkAbpt} from '../src/contracts/ProposalPayload.sol';

contract DeployPayloads is EthereumScript {
  function run() external broadcast {
    new ProposalPayloadStkAave();
    new ProposalPayloadStkAbpt();
  }
}
