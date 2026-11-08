// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./Base.s.sol";

contract LabelRole is BaseScript {
    function run() public broadcast {
        accessManager.labelRole(Roles.GOVERNOR_ROLE, "GOVERNOR_ROLE");
        accessManager.labelRole(Roles.GOVERNOR_ROLE_TIMELOCK, "GOVERNOR_ROLE_TIMELOCK");
        accessManager.labelRole(Roles.GUARDIAN_ROLE, "GUARDIAN_ROLE");
        accessManager.labelRole(Roles.GUARDIAN_ROLE_TIMELOCK, "GUARDIAN_ROLE_TIMELOCK");
        accessManager.labelRole(Roles.KEEPER_ROLE, "KEEPER_ROLE");
        accessManager.labelRole(Roles.KEEPER_ROLE_TIMELOCK, "KEEPER_ROLE_TIMELOCK");

        accessManager.labelRole(Roles.EURp_MINTER_ROLE, "EURp_MINTER_ROLE");
        accessManager.labelRole(Roles.EURp_MINTER_ROLE_TIMELOCK, "EURp_MINTER_ROLE_TIMELOCK");
        accessManager.labelRole(Roles.USDp_MINTER_ROLE, "USDp_MINTER_ROLE");
        accessManager.labelRole(Roles.USDp_MINTER_ROLE_TIMELOCK, "USDp_MINTER_ROLE_TIMELOCK");
        accessManager.labelRole(Roles.ETHp_MINTER_ROLE, "ETHp_MINTER_ROLE");
        accessManager.labelRole(Roles.ETHp_MINTER_ROLE_TIMELOCK, "ETHp_MINTER_ROLE_TIMELOCK");
        accessManager.labelRole(Roles.BTCp_MINTER_ROLE, "BTCp_MINTER_ROLE");
        accessManager.labelRole(Roles.BTCp_MINTER_ROLE_TIMELOCK, "BTCp_MINTER_ROLE_TIMELOCK");
    }
}
