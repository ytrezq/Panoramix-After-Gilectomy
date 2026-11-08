// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IDiamondCut } from "contracts/interfaces/IDiamondCut.sol";

import { LibDiamond } from "../libraries/LibDiamond.sol";

import { AccessManagedModifiers } from "./AccessManagedModifiers.sol";
import "../Storage.sol";

/// @title DiamondCut
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev Reference: EIP-2535 Diamonds
/// @dev Forked from https://github.com/mudgen/diamond-3/blob/master/contracts/facets/DiamondCutFacet.sol by mudgen
contract DiamondCut is IDiamondCut, AccessManagedModifiers {
  /// @inheritdoc IDiamondCut
  function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external restricted {
    LibDiamond.diamondCut(_diamondCut, _init, _calldata);
  }
}
