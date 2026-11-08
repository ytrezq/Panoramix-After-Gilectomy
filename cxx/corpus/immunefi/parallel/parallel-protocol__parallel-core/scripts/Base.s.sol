// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script, console2 } from "@forge-std/Script.sol";

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import { Roles } from "contracts/libraries/RolesLib.sol";

contract BaseScript is Script {
    /// @dev The address of the transaction broadcaster.
    address internal broadcaster;
    uint64 public constant ADMIN_ROLE = type(uint64).min;

    IAccessManager accessManager = IAccessManager(0xfD28f108e95f4D41daAE9dbfFf707D677985998E);

    modifier broadcast() {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        broadcaster = vm.addr(privateKey);
        _;
        vm.stopBroadcast();
    }
}
