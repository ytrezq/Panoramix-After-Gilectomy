// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ITokenP } from "contracts/interfaces/ITokenP.sol";
import { AccessManagedUpgradeable, IAccessManager } from "../utils/AccessManagedUpgradeable.sol";

import "../utils/Constants.sol";
import "../utils/Errors.sol";

/// @title BaseSavings
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Parallel Savings contracts are contracts where users can deposit an `asset` and earn a yield on this asset
/// when it is distributed
/// @dev These contracts are functional within the Parallelizer system if they have mint right on `asset` and
/// if they are trusted by the Parallelizer contract
/// @dev Implementations assume that `asset` is safe to interact with, on which there cannot be reentrancy attacks
/// @dev The ERC4626 interface does not allow users to specify a slippage protection parameter for the main entry
/// points
/// (like `deposit`, `mint`, `redeem` or `withdraw`). Even though there should be no specific sandwiching
/// issue with current implementations, it is still recommended to interact with Parallel Savings contracts
/// through a router that can implement such a protection.
/// @dev This contract is an authorized fork of Angle's Savings contract:
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/savings/BaseSavings.sol
abstract contract BaseSavings is Initializable, AccessManagedUpgradeable, ERC4626Upgradeable, UUPSUpgradeable {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Upgrade the implementation of the contract
  /// @dev This function can only be called by the governor only
  /// @param newImplementation The address of the new implementation
  function _authorizeUpgrade(address newImplementation) internal override restricted { }
}
