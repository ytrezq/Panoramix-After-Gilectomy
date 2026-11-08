// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { console2 as console, Script } from "../modules/forge-std/src/Script.sol";

import { SyrupRouter } from "../contracts/SyrupRouter.sol";

contract DeployRouter is Script {

    function run() external {
        address deployer = vm.envAddress("ETH_SENDER");
        address pool     = vm.envAddress("MAPLE_POOL");

        console.log("Deployer set to: %s", deployer);
        console.log("SyrupRouter configured for MaplePool: %s", pool);

        vm.broadcast(deployer);
        address router = address(new SyrupRouter(pool));

        console.log("SyrupRouter deployed at: %s", router);
    }

}
