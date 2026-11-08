// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISettersGovernor } from "contracts/interfaces/ISetters.sol";

import { LibManager } from "../libraries/LibManager.sol";
import { LibOracle } from "../libraries/LibOracle.sol";
import { LibSetters } from "../libraries/LibSetters.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";
import { AccessManagedModifiers } from "./AccessManagedModifiers.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title SettersGovernor
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev This contract is an authorized fork of Angle's `SettersGovernor` contract
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/transmuter/facets/SettersGovernor.sol
contract SettersGovernor is AccessManagedModifiers, ISettersGovernor {
  using SafeERC20 for IERC20;

  event Recovered(address indexed token, address indexed to, uint256 amount);

  /// @inheritdoc ISettersGovernor
  /// @dev No check is made on the collateral that is redeemed: this function could typically be used by a
  /// governance during a manual rebalance of the reserves of the system
  /// @dev `collateral` is different from `token` only in the case of a managed collateral
  function recoverERC20(address collateral, IERC20 token, address to, uint256 amount) external restricted {
    Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
    if (collatInfo.isManaged > 0) LibManager.release(address(token), to, amount, collatInfo.managerData.config);
    else token.safeTransfer(to, amount);
    emit Recovered(address(token), to, amount);
  }

  /// @inheritdoc ISettersGovernor
  function setAccessManager(address _newAccessManager) external restricted {
    LibSetters.setAccessManager(IAccessManager(_newAccessManager));
  }

  /// @inheritdoc ISettersGovernor
  /// @dev Funds need to have been withdrawn from the eventual previous manager prior to this call
  function setCollateralManager(
    address collateral,
    bool checkExternalManagerBalance,
    ManagerStorage memory managerData
  )
    external
    restricted
  {
    LibSetters.setCollateralManager(collateral, checkExternalManagerBalance, managerData);
  }

  /// @inheritdoc ISettersGovernor
  /// @dev This function can typically be used to grant allowance to a newly added manager for it to pull the
  /// funds associated to the collateral it corresponds to
  function changeAllowance(IERC20 token, address spender, uint256 amount) external restricted {
    uint256 currentAllowance = token.allowance(address(this), spender);
    if (currentAllowance < amount) {
      token.safeIncreaseAllowance(spender, amount - currentAllowance);
    } else if (currentAllowance > amount) {
      token.safeDecreaseAllowance(spender, currentAllowance - amount);
    }
  }

  /// @inheritdoc ISettersGovernor
  function toggleTrusted(address sender, TrustedType t) external restricted {
    LibSetters.toggleTrusted(sender, t);
  }

  /// @inheritdoc ISettersGovernor
  /// @dev Collateral assets with a fee on transfer are not supported by the system
  function addCollateral(address collateral) external restricted {
    LibSetters.addCollateral(collateral);
  }

  /// @inheritdoc ISettersGovernor
  /// @dev The amount passed here must be an absolute amount
  function adjustStablecoins(address collateral, uint128 amount, bool increase) external restricted {
    LibSetters.adjustStablecoins(collateral, amount, increase);
  }

  /// @inheritdoc ISettersGovernor
  /// @dev Require `collatInfo.normalizedStables == 0`, that is to say that the collateral
  /// is not used to back stables
  /// @dev The system may still have a non null balance of the collateral that is revoked: this should later
  /// be handled through a recoverERC20 call
  /// @dev Funds needs to have been withdrew from the manager prior to this call if `checkExternalManagerBalance` is
  /// true
  function revokeCollateral(address collateral, bool checkExternalManagerBalance) external restricted {
    LibSetters.revokeCollateral(collateral, checkExternalManagerBalance);
  }

  /// @inheritdoc ISettersGovernor
  function setOracle(address collateral, bytes memory oracleConfig) external restricted {
    LibSetters.setOracle(collateral, oracleConfig);
  }

  /// @inheritdoc ISettersGovernor
  function updateOracle(address collateral) external {
    if (s.transmuterStorage().isSellerTrusted[msg.sender] == 0) revert NotTrusted();
    LibOracle.updateOracle(collateral);
  }

  /// @inheritdoc ISettersGovernor
  function setWhitelistStatus(
    address collateral,
    uint8 whitelistStatus,
    bytes memory whitelistData
  )
    external
    restricted
  {
    LibSetters.setWhitelistStatus(collateral, whitelistStatus, whitelistData);
  }

  /// @inheritdoc ISettersGovernor
  function updatePayees(address[] memory _payees, uint256[] memory _shares, bool _skipRelease) external restricted {
    LibSetters.updatePayees(_payees, _shares, _skipRelease);
  }

  /// @inheritdoc ISettersGovernor
  function updateSlippageTolerance(address collateral, uint256 slippageTolerance) external restricted {
    LibSetters.updateSlippageTolerance(collateral, slippageTolerance);
  }

  /// @inheritdoc ISettersGovernor
  function updateSurplusBufferRatio(uint64 _surplusBufferRatio) external restricted {
    LibSetters.updateSurplusBufferRatio(_surplusBufferRatio);
  }

  /// @inheritdoc ISettersGovernor
  function setSwapRouter(address swapRouter) external restricted {
    LibSetters.setSwapRouter(swapRouter);
  }
}
