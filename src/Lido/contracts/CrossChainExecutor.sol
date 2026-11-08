// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IBaseReceiverPortal} from '../../contracts/interfaces/IBaseReceiverPortal.sol';

import {BridgeExecutorBase} from './BridgeExecutorBase.sol';

/**
 * @title CrossChainExecutor
 * @author Lido
 * @notice Contract that implements receiver portal role along with the ability to execute actions sets.
 * @dev Queuing an ActionsSet into this Executor can only be done by sending a message from Ethereum Governance Agent
 * via a.DI CrossChainController contract on the Ethereum mainnet using this contract as a destination.
 */
contract CrossChainExecutor is BridgeExecutorBase, IBaseReceiverPortal {

  /**
   * @dev Address of the CrossChainController contract on the current chain.
   */
  address private immutable CROSS_CHAIN_CONTROLLER;

  /**
   * @dev Address of the DAO Agent contract on the root chain.
   */
  address private immutable GOVERNANCE_EXECUTOR;

  /**
   * @dev Root Chain ID of the DAO Agent contract, must be 1 for Ethereum.
   */
  uint256 private immutable GOVERNANCE_CHAIN_ID;

  error InvalidCrossChainController();
  error InvalidEthereumGovernanceExecutor();
  error InvalidEthereumGovernanceChainId();
  error InvalidCaller();
  error InvalidSenderAddress();
  error InvalidSenderChainId();

  event MessageReceived(address indexed originSender, uint256 indexed originChainId, bytes message);

  /**
   * @dev Only allows the CrossChainController to call the function
   */
  modifier onlyCrossChainController() {
    if (msg.sender != CROSS_CHAIN_CONTROLLER) revert InvalidCaller();
    _;
  }

  /**
   * @dev Constructor
   *
   * @param crossChainController - Address of the CrossChainController contract on the current chain
   * @param ethereumGovernanceExecutor - Address of the DAO Aragon Agent contract on the root chain
   * @param ethereumGovernanceChainId - Chain ID of the DAO Aragon Agent contract
   * @param delay - The delay before which an actions set can be executed
   * @param gracePeriod - The time period after a delay during which an actions set can be executed
   * @param minimumDelay - The minimum bound a delay can be set to
   * @param maximumDelay - The maximum bound a delay can be set to
   * @param guardian - The address of the guardian, which can cancel queued proposals (can be zero)
   */
  constructor(
    address crossChainController,
    address ethereumGovernanceExecutor,
    uint256 ethereumGovernanceChainId,
    uint256 delay,
    uint256 gracePeriod,
    uint256 minimumDelay,
    uint256 maximumDelay,
    address guardian
  ) BridgeExecutorBase(delay, gracePeriod, minimumDelay, maximumDelay, guardian) {
    if (crossChainController == address(0)) revert InvalidCrossChainController();
    if (ethereumGovernanceExecutor == address(0)) revert InvalidEthereumGovernanceExecutor();
    if (ethereumGovernanceChainId == 0) revert InvalidEthereumGovernanceChainId();

    CROSS_CHAIN_CONTROLLER = crossChainController;
    GOVERNANCE_EXECUTOR = ethereumGovernanceExecutor;
    GOVERNANCE_CHAIN_ID = ethereumGovernanceChainId;
  }

  /**
   * @notice method called by CrossChainController when a message has been confirmed
   * @param originSender address of the sender of the bridged message
   * @param originChainId id of the chain where the message originated
   * @param message bytes bridged containing the desired information
   */
  function receiveCrossChainMessage(
    address originSender,
    uint256 originChainId,
    bytes memory message
  ) external override onlyCrossChainController {
    if (originSender != GOVERNANCE_EXECUTOR) revert InvalidSenderAddress();
    if (originChainId != GOVERNANCE_CHAIN_ID) revert InvalidSenderChainId();

    emit MessageReceived(originSender, originChainId, message);

    _receiveCrossChainMessage(message);
  }

  /**
   * @notice method called by receiveCrossChainMessage to put the message into the queue
   * @param data bytes containing the message to be queued
   */
  function _receiveCrossChainMessage(bytes memory data) internal {
    address[] memory targets;
    uint256[] memory values;
    string[] memory signatures;
    bytes[] memory calldatas;
    bool[] memory withDelegatecalls;

    (targets, values, signatures, calldatas, withDelegatecalls) = abi.decode(
      data,
      (address[], uint256[], string[], bytes[], bool[])
    );

    _queue(targets, values, signatures, calldatas, withDelegatecalls);
  }

  /**
   * @notice Returns the address of the Ethereum Governance Executor
   * @return The address of the EthereumGovernanceExecutor
   **/
  function getEthereumGovernanceExecutor() external view returns (address) {
    return GOVERNANCE_EXECUTOR;
  }

  /**
   * @notice Returns the chain ID of the Ethereum Governance Executor
   * @return The chain ID of the EthereumGovernanceExecutor
   **/
  function getEthereumGovernanceChainId() external view returns (uint256) {
    return GOVERNANCE_CHAIN_ID;
  }

  /**
   * @notice Returns the address of the CrossChainController
   * @return The address of the CrossChainController
   **/
  function getCrossChainController() external view returns (address) {
    return CROSS_CHAIN_CONTROLLER;
  }
}
