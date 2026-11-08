// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IDiamondEtherscan
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
interface IDiamondEtherscan {
  /// @notice Sets a dummy implementation with the same layout at the diamond proxy contract with all its facets
  function setDummyImplementation(address _implementation) external;

  /// @notice Address of the dummy implementation used to make the DiamondProxy contract interpretable by Etherscan
  function implementation() external view returns (address);
}
