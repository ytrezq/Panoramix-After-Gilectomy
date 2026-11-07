// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../parallelizer/Storage.sol";

/// @title IDiamondCut
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev Reference: EIP-2535 Diamonds
/// @dev Forked from https://github.com/mudgen/diamond-3/blob/master/contracts/interfaces/IDiamondCut.sol by mudgen
/// @dev This interface is an authorized fork of Angle's `IDiamondCut` interface
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/interfaces/IDiamondCut.sol
interface IDiamondCut {
  /// @notice Add/replace/remove any number of functions and optionally execute a function with delegatecall
  /// @param _diamondCut Contains the facet addresses and function selectors
  /// @param _init The address of the contract or facet to execute _calldata
  /// @param _calldata A function call, including function selector and arguments, executed with delegatecall on
  /// _init
  function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external;
}
