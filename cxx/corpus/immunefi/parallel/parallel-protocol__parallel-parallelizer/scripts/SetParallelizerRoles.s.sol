// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./Base.s.sol";

import { ISettersGuardian, ISettersGovernor } from "contracts/interfaces/ISetters.sol";
import { IDiamondEtherscan } from "contracts/interfaces/IDiamondEtherscan.sol";
import { ISurplus } from "contracts/interfaces/ISurplus.sol";

contract SetParallelizerRoles is BaseScript {
  address parallelizer = 0x1250304F66404cd153fA39388DDCDAec7E0f1707;

  function run() public broadcast {
    bytes4[] memory guardianSelectors = new bytes4[](7);
    guardianSelectors[0] = ISettersGuardian.pause.selector;
    guardianSelectors[1] = ISettersGuardian.unpause.selector;
    guardianSelectors[2] = ISettersGuardian.setFees.selector;
    guardianSelectors[3] = ISettersGuardian.setRedemptionCurveParams.selector;
    guardianSelectors[4] = ISettersGuardian.toggleWhitelist.selector;
    guardianSelectors[5] = ISettersGuardian.setStablecoinCap.selector;
    guardianSelectors[6] = IDiamondEtherscan.setDummyImplementation.selector;
    accessManager.setTargetFunctionRole(parallelizer, guardianSelectors, Roles.GUARDIAN_ROLE);

    bytes4[] memory governorSelectors = new bytes4[](15);
    governorSelectors[0] = ISettersGovernor.recoverERC20.selector;
    governorSelectors[1] = ISettersGovernor.setAccessManager.selector;
    governorSelectors[2] = ISettersGovernor.setCollateralManager.selector;
    governorSelectors[3] = ISettersGovernor.changeAllowance.selector;
    governorSelectors[4] = ISettersGovernor.toggleTrusted.selector;
    governorSelectors[5] = ISettersGovernor.addCollateral.selector;
    governorSelectors[6] = ISettersGovernor.adjustStablecoins.selector;
    governorSelectors[7] = ISettersGovernor.revokeCollateral.selector;
    governorSelectors[8] = ISettersGovernor.setOracle.selector;
    governorSelectors[9] = ISettersGovernor.updateOracle.selector;
    governorSelectors[10] = ISettersGovernor.setWhitelistStatus.selector;
    governorSelectors[11] = ISettersGovernor.updatePayees.selector;
    governorSelectors[12] = ISettersGovernor.updateSlippageTolerance.selector;
    governorSelectors[13] = ISettersGovernor.updateSurplusBufferRatio.selector;
    governorSelectors[14] = ISettersGovernor.setSwapRouter.selector;
    accessManager.setTargetFunctionRole(parallelizer, governorSelectors, Roles.GOVERNOR_ROLE);

    bytes4[] memory keeperSelectors = new bytes4[](2);
    keeperSelectors[0] = ISurplus.processSurplus.selector;
    keeperSelectors[1] = ISurplus.release.selector;
    accessManager.setTargetFunctionRole(parallelizer, keeperSelectors, Roles.KEEPER_ROLE);

    accessManager.grantRole(Roles.USDp_MINTER_ROLE, address(parallelizer), 0);
  }
}
