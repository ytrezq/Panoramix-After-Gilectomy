// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity ^0.8.0;

import {IHub} from 'src/hub/interfaces/IHub.sol';

/// @title IHubInstance
/// @author Aave Labs
/// @notice Hub instance interface exposing the initializer and revision.
interface IHubInstance is IHub {
  /// @notice Initializes the Hub instance with the given authority.
  /// @param authority The address of the access-control authority contract.
  function initialize(address authority) external;

  /// @notice Returns the revision number of this Hub implementation.
  function HUB_REVISION() external view returns (uint64);
}
