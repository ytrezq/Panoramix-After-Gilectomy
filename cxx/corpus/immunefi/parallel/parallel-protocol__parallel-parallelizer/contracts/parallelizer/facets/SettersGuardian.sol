// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { ISettersGuardian } from "contracts/interfaces/ISetters.sol";

import { LibSetters } from "../libraries/LibSetters.sol";
import { AccessManagedModifiers } from "./AccessManagedModifiers.sol";

import "../Storage.sol";

/// @title SettersGuardian
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev This contract is an authorized fork of Angle's `SettersGuardian` contract
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/transmuter/facets/SettersGuardian.sol
contract SettersGuardian is AccessManagedModifiers, ISettersGuardian {
  /// @inheritdoc ISettersGuardian
  function pause(address collateral, ActionType action) external restricted {
    LibSetters.pause(collateral, action);
  }

  /// @inheritdoc ISettersGuardian
  function unpause(address collateral, ActionType action) external restricted {
    LibSetters.unpause(collateral, action);
  }

  /// @inheritdoc ISettersGuardian
  function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external restricted {
    LibSetters.setFees(collateral, xFee, yFee, mint);
  }

  /// @inheritdoc ISettersGuardian
  function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external restricted {
    LibSetters.setRedemptionCurveParams(xFee, yFee);
  }

  /// @inheritdoc ISettersGuardian
  function toggleWhitelist(WhitelistType whitelistType, address who) external restricted {
    LibSetters.toggleWhitelist(whitelistType, who);
  }

  /// @inheritdoc ISettersGuardian
  function setStablecoinCap(address collateral, uint256 stablecoinCap) external restricted {
    LibSetters.setStablecoinCap(collateral, stablecoinCap);
  }
}
