// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { AccessManager, IAccessManaged } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { Savings } from "contracts/savings/Savings.sol";
import { SavingsNameable } from "contracts/savings/nameable/SavingsNameable.sol";
import { BaseSavings } from "contracts/savings/BaseSavings.sol";
import { BaseRebalancer } from "contracts/helpers/BaseRebalancer.sol";
import { MultiBlockRebalancer } from "contracts/helpers/MultiBlockRebalancer.sol";
import { GenericRebalancer } from "contracts/helpers/GenericRebalancer.sol";
import { SettersGuardian } from "contracts/parallelizer/facets/SettersGuardian.sol";
import { SettersGovernor } from "contracts/parallelizer/facets/SettersGovernor.sol";
import { DiamondEtherscan } from "contracts/parallelizer/facets/DiamondEtherscan.sol";
import { Surplus } from "contracts/parallelizer/facets/Surplus.sol";
import "contracts/utils/Constants.sol";
import "./Helper.sol";

import "@forge-std/console.sol";

abstract contract ConfigAccessManager is Helper {
  AccessManager public accessManager;

  function deployAccessManager(
    address _initialAdmin,
    address _governor,
    address _guardian,
    address _governorAndGuardian
  )
    internal
  {
    accessManager = new AccessManager(_initialAdmin);
    vm.label({ account: address(accessManager), newLabel: "AccessManager" });
    // Set the roles
    vm.startPrank(_initialAdmin);
    accessManager.grantRole(GOVERNOR_ROLE, _governor, 0);
    accessManager.grantRole(GUARDIAN_ROLE, _guardian, 0);
    accessManager.grantRole(KEEPER_ROLE, _governor, 0);
    accessManager.grantRole(GOVERNOR_ROLE, _governorAndGuardian, 0);
    accessManager.grantRole(GUARDIAN_ROLE, _governorAndGuardian, 0);
    accessManager.grantRole(KEEPER_ROLE, _governorAndGuardian, 0);
    vm.stopPrank();
  }

  function getGuardianSavingsSelectorAccess() internal pure returns (bytes4[] memory) {
    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = Savings.pause.selector;
    selectors[1] = Savings.unpause.selector;
    selectors[2] = Savings.toggleTrusted.selector;
    selectors[3] = Savings.setRate.selector;
    return selectors;
  }

  function getGovernorSavingsSelectorAccess() internal pure returns (bytes4[] memory) {
    bytes4[] memory selectors = new bytes4[](5);
    selectors[0] = SavingsNameable.setNameAndSymbol.selector;
    selectors[1] = Savings.setMaxRate.selector;
    selectors[2] = UUPSUpgradeable.upgradeToAndCall.selector;
    selectors[3] = Savings.recoverSurplus.selector;
    selectors[4] = Savings.initializeStoredAssets.selector;
    return selectors;
  }

  function getGuardianBaseRebalancerSelectorAccess() internal pure returns (bytes4[] memory) {
    bytes4[] memory selectors = new bytes4[](6);
    selectors[0] = BaseRebalancer.setYieldBearingAssetData.selector;
    selectors[1] = BaseRebalancer.setMaxSlippage.selector;
    selectors[2] = BaseRebalancer.toggleTrusted.selector;
    selectors[3] = BaseRebalancer.recoverERC20.selector;
    selectors[4] = BaseRebalancer.setTargetExposure.selector;
    selectors[5] = BaseRebalancer.resetAllowance.selector;
    return selectors;
  }

  function getGovernorMultiBlockRebalancerSelectorAccess() internal pure returns (bytes4[] memory) {
    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = MultiBlockRebalancer.setYieldBearingToDepositAddress.selector;
    return selectors;
  }

  function getGovernorGenericRebalancerSelectorAccess() internal pure returns (bytes4[] memory) {
    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = GenericRebalancer.setTokenTransferAddress.selector;
    selectors[1] = GenericRebalancer.setSwapRouter.selector;
    return selectors;
  }

  function getParallelizerGuardianSelectorAccess() internal pure returns (bytes4[] memory) {
    bytes4[] memory selectors = new bytes4[](7);
    selectors[0] = SettersGuardian.pause.selector;
    selectors[1] = SettersGuardian.unpause.selector;
    selectors[2] = SettersGuardian.setFees.selector;
    selectors[3] = SettersGuardian.setRedemptionCurveParams.selector;
    selectors[4] = SettersGuardian.toggleWhitelist.selector;
    selectors[5] = SettersGuardian.setStablecoinCap.selector;
    selectors[6] = DiamondEtherscan.setDummyImplementation.selector;
    return selectors;
  }

  function getParallelizerGovernorSelectorAccess() internal pure returns (bytes4[] memory) {
    bytes4[] memory selectors = new bytes4[](15);
    selectors[0] = SettersGovernor.recoverERC20.selector;
    selectors[1] = SettersGovernor.setAccessManager.selector;
    selectors[2] = SettersGovernor.setCollateralManager.selector;
    selectors[3] = SettersGovernor.changeAllowance.selector;
    selectors[4] = SettersGovernor.toggleTrusted.selector;
    selectors[5] = SettersGovernor.addCollateral.selector;
    selectors[6] = SettersGovernor.adjustStablecoins.selector;
    selectors[7] = SettersGovernor.revokeCollateral.selector;
    selectors[8] = SettersGovernor.setOracle.selector;
    selectors[9] = SettersGovernor.updateOracle.selector;
    selectors[10] = SettersGovernor.setWhitelistStatus.selector;
    selectors[11] = SettersGovernor.updatePayees.selector;
    selectors[12] = SettersGovernor.updateSlippageTolerance.selector;
    selectors[13] = SettersGovernor.updateSurplusBufferRatio.selector;
    selectors[14] = SettersGovernor.setSwapRouter.selector;
    return selectors;
  }

  function getParallelizerKeeperSelectorAccess() internal pure returns (bytes4[] memory) {
    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = Surplus.processSurplus.selector;
    selectors[1] = Surplus.release.selector;
    return selectors;
  }
}
