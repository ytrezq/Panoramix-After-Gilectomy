// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOnRampClient {
  /// @notice Get the pool for a specific token
  function getPoolBySourceToken(
    uint64 destChainSelector,
    address sourceToken
  ) external view returns (address);
}
