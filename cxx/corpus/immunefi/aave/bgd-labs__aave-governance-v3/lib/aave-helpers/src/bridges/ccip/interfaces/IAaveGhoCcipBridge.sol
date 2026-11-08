// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Client} from '../../../dependencies/chainlink/libraries/Client.sol';

/**
 * @title IAaveGhoCcipBridge
 * @author TokenLogic
 * @notice Defines the behaviour of an AaveGhoCcipBridge
 */
interface IAaveGhoCcipBridge {
  /**
   * Struct representing a destination chain
   * @return extraArgsOverride The bytes representation of an address (EVM or non-EVM)
   * @return destination Any extra arguments to pass with message to the destination chain
   * @return gasLimit The gas limit to set for the destination chain's ccipReceive() function
   */
  struct RemoteChainConfig {
    bytes destination; // Can be non-EVM address
    // If set, extraArgsOverride overrides the default extraArgs. This enables both sending to non-EVM chains and
    // allows supporting future extraArgs without needing to redeploy this contract.
    bytes extraArgsOverride;
    uint32 gasLimit;
  }

  /**
   * @dev Emitted when a new GHO transfer is issued
   * @param messageId The ID of the cross-chain message
   * @param destinationChainSelector The selector of the destination chain
   * @param from The address of sender on source chain
   * @param amount The total amount of GHO transferred
   */
  event BridgeMessageInitiated(
    bytes32 indexed messageId,
    uint64 indexed destinationChainSelector,
    address indexed from,
    uint256 amount
  );

  /**
   * @dev Emitted when the token transfer is executed on the destination chain
   * @param messageId The ID of the cross-chain message
   * @param to The address of receiver on destination chain
   * @param amount The amount of token transferred
   */
  event BridgeMessageFinalized(bytes32 indexed messageId, address indexed to, uint256 amount);

  /**
   * @dev Emitted when the destination bridge data is updated
   * @param chainSelector The selector of the destination chain
   * @param destination The address of the bridge on the destination chain
   * @param gasLimit The gas limit on the ccipReceive() function on the destination chain
   * @param extraArgs The extra arguments to pass with message to the destination chain
   */
  event DestinationChainSet(
    uint64 indexed chainSelector,
    bytes destination,
    uint32 gasLimit,
    bytes extraArgs
  );

  /**
   * @dev Emitted when an invalid message is received by the bridge
   * @param messageId The ID of message
   * @param err The error on why the transfer failed
   */
  event BridgeMessageFailed(bytes32 indexed messageId, bytes err);

  /**
   * @dev Emits when receive invalid message
   * @param messageId The id of message
   */
  event BridgeMessageRecovered(bytes32 indexed messageId);

  /**
   * @dev The bridge's bridge limit has been exceeded
   */
  error BridgeLimitExceeded(uint256 limit);

  /**
   * @dev Insufficient fee paid for transfer
   */
  error InsufficientFee();

  /**
   *
   * @dev Received token is not expected token
   */
  error InvalidToken();

  /**
   * @dev Address cannot be the zero-address
   */
  error InvalidZeroAddress();

  /**
   * @dev Amount must be greater than zero
   */
  error InvalidZeroAmount();

  /**
   * @dev Function is only callable by self
   */
  error OnlySelf();

  /**
   * @dev The message with the specified ID cannot be found
   */
  error MessageNotFound();

  /**
   * @dev The bridge's rate limit has been exceeded
   */
  error RateLimitExceeded(uint256 limit);

  /**
   * @dev The source destination of the message is invalid
   */
  error UnknownSourceDestination();

  /**
   * @dev The destination chain is invalid
   */
  error UnsupportedChain();

  /**
   * @notice Transfers tokens to specified destination chain.
   * @dev chain selector can be found https://docs.chain.link/ccip/directory/mainnet
   * @param chainSelector The chain selector of the destination chain
   * @param amount The amount of GHO to transfer
   * @param feeToken The address of the fee token to pay transfer with
   * @return The ID of the cross-chain message
   */
  function send(uint64 chainSelector, uint256 amount, address feeToken) external returns (bytes32);

  /**
   * @notice Wraps _ccipReceive() as an external function in order to leverage try/catch functionality.
   * @dev Only callable by the contract itself
   * @param message Struct containing the message's data
   */
  function processMessage(Client.Any2EVMMessage calldata message) external;

  /**
   * @notice Recovers tokens received via an invalid message
   * @dev Withdraws tokens included in invalid message to collector
   * @param messageId The ID of message received
   */
  function recoverFailedMessageTokens(bytes32 messageId) external;

  /**
   * @notice Sets a destination chain and corresponding bridge address.
   * @dev Only callable by ADMIN.
   * @param chainSelector The chain selector of the destination chain
   * @param destination The address of the bridge on the destination chain
   * @param extraArgs Any extra arguments to pass with message to the destination chain
   * @param gasLimit The gas limit to set for the destination chain's ccipReceive() function
   * @dev The bridge address refers to an instance of this contract deployed
   * by the Aave DAO on the remote chain specified by the chainSelector.
   */
  function setDestinationChain(
    uint64 chainSelector,
    bytes calldata destination,
    bytes calldata extraArgs,
    uint32 gasLimit
  ) external;

  /**
   * @notice Removes a destination chain and corresponding bridge address.
   * @dev Only callable by ADMIN.
   * @param chainSelector The chain selector of the destination chain
   */
  function removeDestinationChain(uint64 chainSelector) external;

  /**
   * @notice Returns the configuration of the corresponding bridge for a specified chain selector.
   * @param chainSelector The chain selector of destination chain
   * @return The struct representation of the destination configuration which consists of:
   * The bytes representation of the address of AaveGhoCcipBridge on the destination chain
   * The extra arguments to send to the destination chain in the bridge message
   * The gas limit to send to the destination chain
   */
  function getDestinationRemoteConfig(
    uint64 chainSelector
  ) external view returns (RemoteChainConfig memory);

  /**
   * @notice Returns contents of specified invalid message.
   * @param messageId The ID of the message to query
   * @return Array of the message's tokens and amounts transferred
   */
  function getInvalidMessage(
    bytes32 messageId
  ) external view returns (Client.EVMTokenAmount[] memory);

  /**
   * @notice Returns the bridge rate limit for a given chain.
   * @dev If call is made on Mainnet it check the bridge limit of the ETH Token Pool
   * @param chainSelector The chain selector of the destination chain
   * @return The rate limit of the chain
   */
  function getRateLimit(uint64 chainSelector) external view returns (uint128);

  /**
   * @notice Returns the fee amount cost to execute the bridge transfer.
   * @param chainSelector The chain selector of the destination chain
   * @param amount The amount of GHO to transfer
   * @param feeToken The address of fee token to pay transfer with
   * @return The amount of fee tokens required
   */
  function quoteBridge(
    uint64 chainSelector,
    uint256 amount,
    address feeToken
  ) external view returns (uint256);

  /**
   * @notice Returns the GHO token address on the deployed chain.
   * @return The address of the GHO token contract
   */
  function GHO_TOKEN() external view returns (address);

  /**
   * @notice Returns the Chainlink CCIP router address
   * @return The address of the Chainlink CCIP router
   */
  function ROUTER() external view returns (address);

  /**
   * @notice Returns the AaveCollector address on the deployed chain.
   * @return The address of the Collector contract
   */
  function COLLECTOR() external view returns (address);
}
