// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISurplus } from "contracts/interfaces/ISurplus.sol";
import { ISwapper } from "contracts/interfaces/ISwapper.sol";
import { IGetters } from "contracts/interfaces/IGetters.sol";
import { ITokenP } from "contracts/interfaces/ITokenP.sol";

import { LibOracle } from "../libraries/LibOracle.sol";
import { LibGetters } from "../libraries/LibGetters.sol";
import { LibHelpers } from "../libraries/LibHelpers.sol";
import { LibManager } from "../libraries/LibManager.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";
import { LibSurplus } from "../libraries/LibSurplus.sol";
import { AccessManagedModifiers } from "./AccessManagedModifiers.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title Surplus
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
contract Surplus is AccessManagedModifiers, ISurplus {
  using SafeERC20 for IERC20;

  event SurplusProcessed(address collateral, uint256 collateralSurplus, uint256 stableSurplus, uint256 issuedAmount);

  /// @inheritdoc ISurplus
  function processSurplus(
    address collateral,
    uint256 maxCollateralAmount
  )
    external
    restricted
    returns (uint256 collateralSurplus, uint256 stableSurplus, uint256 issuedAmount)
  {
    ParallelizerStorage storage ts = s.transmuterStorage();
    (collateralSurplus, stableSurplus) = LibSurplus._computeCollateralSurplus(collateral);
    if (collateralSurplus == 0) revert ZeroAmount();
    if (maxCollateralAmount > 0 && maxCollateralAmount < collateralSurplus) {
      stableSurplus = (stableSurplus * maxCollateralAmount) / collateralSurplus;
      collateralSurplus = maxCollateralAmount;
    }
    uint256 minExpectedAmount = LibSurplus._minExpectedAmount(stableSurplus, ts.slippageTolerance[collateral]);
    Collateral storage collatInfo = ts.collaterals[collateral];
    if (collatInfo.isManaged > 0) {
      LibManager.release(collateral, address(this), collateralSurplus, collatInfo.managerData.config);
    }
    IERC20(collateral).forceApprove(address(this), collateralSurplus);
    issuedAmount = ISwapper(address(this))
      .swapExactInput(
        collateralSurplus, minExpectedAmount, collateral, address(ts.tokenP), address(this), block.timestamp
      );
    (uint64 collatRatio,,,,) = LibGetters.getCollateralRatio();
    if (collatRatio < ts.surplusBufferRatio) revert Undercollateralized();
    emit SurplusProcessed(collateral, collateralSurplus, stableSurplus, issuedAmount);
  }

  /// @inheritdoc ISurplus
  function release() external nonReentrant restricted returns (address[] memory payees, uint256[] memory amounts) {
    ParallelizerStorage storage ts = s.transmuterStorage();
    uint256 income = ts.tokenP.balanceOf(address(this));
    if (income == 0) revert ZeroAmount();
    if (ts.payees.length == 0) revert InvalidLengths();
    (payees, amounts) = LibSurplus.release(income, ts.payees);
  }
}
