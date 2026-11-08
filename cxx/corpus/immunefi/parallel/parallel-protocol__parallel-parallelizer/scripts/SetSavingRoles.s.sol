// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { SavingsNameable } from "contracts/savings/nameable/SavingsNameable.sol";
import { Savings } from "contracts/savings/Savings.sol";

import "./Base.s.sol";

contract SetSavingRoles is BaseScript {
  address saving = 0x9B3a8f7CEC208e247d97dEE13313690977e24459;

  function run() public broadcast {
    bytes4[] memory guardianSelectors = new bytes4[](3);
    guardianSelectors[0] = Savings.pause.selector;
    guardianSelectors[1] = Savings.unpause.selector;
    guardianSelectors[2] = Savings.toggleTrusted.selector;
    accessManager.setTargetFunctionRole(saving, guardianSelectors, Roles.GUARDIAN_ROLE);

    bytes4[] memory keeperSelectors = new bytes4[](1);
    keeperSelectors[0] = Savings.setRate.selector;
    accessManager.setTargetFunctionRole(saving, keeperSelectors, Roles.KEEPER_ROLE);

    bytes4[] memory governorSelectors = new bytes4[](5);
    governorSelectors[0] = SavingsNameable.setNameAndSymbol.selector;
    governorSelectors[1] = Savings.setMaxRate.selector;
    governorSelectors[2] = UUPSUpgradeable.upgradeToAndCall.selector;
    governorSelectors[3] = Savings.recoverSurplus.selector;
    governorSelectors[4] = Savings.initializeStoredAssets.selector;
    accessManager.setTargetFunctionRole(saving, governorSelectors, Roles.GOVERNOR_ROLE);

    accessManager.grantRole(Roles.USDp_MINTER_ROLE, address(saving), 0);
  }
}
