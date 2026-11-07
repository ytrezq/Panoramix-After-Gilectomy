// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { Protocol, Yearn, Curve } from "src/utils/Constants.sol";
import { IRoleManager } from "src/interfaces/yearn/IRoleManager.sol";
import { IV2Vault } from "src/interfaces/yearn/IV2Vault.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";

contract DeployYearnVault is Script, TenderlyHelper {

    function run() public  {
        address governance = IRoleManager(Yearn.ROLE_MANAGER).governance();
        // vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast(governance);
        // address vault = IRoleManager(Yearn.ROLE_MANAGER).newVault(
        //     Protocol.YTOKEN, // asset
        //     1, // category
        //     100_000_000e18 // depositLimit
        // );
        // console.log("--- Yearn V3 Vault deployed ---");
        // console.log("vault:", vault);

        address vault = IV2Vault(Yearn.REGISTRY_V2).newVault(
            Curve.POOL, // asset
            Protocol.OWNER, // guardian
            Protocol.OWNER, // rewards
            "Yearn YB Vault", // name
            "yYBV" // symbol
        );
        console.log("--- Yearn V2 Vault deployed ---");
        console.log("vault:", vault);
        vm.stopBroadcast();
    }
}
