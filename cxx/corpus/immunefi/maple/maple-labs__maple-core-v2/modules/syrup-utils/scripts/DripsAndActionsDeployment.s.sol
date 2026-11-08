// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { console2 as console, Script } from "../modules/forge-std/src/Script.sol";

import { MplUserActions }   from "../contracts/MplUserActions.sol";
import { SyrupDrip }        from "../contracts/SyrupDrip.sol";

contract DeploySyrupDripsAndActions is Script {

    function run() external {
        address deployer = vm.envAddress("ETH_SENDER");

        address globals   = 0x804a6F5F667170F545Bf14e5DDB48C70B788390C;
        address migrator  = 0x9c9499edD0cd2dCBc3C9Dd5070bAf54777AD8F2C;
        address syrup     = 0x643C4E15d7d62Ad0aBeC4a9BD4b001aA3Ef52d66;
        address stSyrup   = 0xc7E8b36E0766D9B04c93De68A9D47dD11f260B45;
        address xmpl      = 0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c;

        vm.startBroadcast(deployer);

        address drips = address(new SyrupDrip(syrup, globals, stSyrup));
        console.log("SyrupDrips deployed at: %s", drips);

        address mplUserActions = address(new MplUserActions(migrator, xmpl, stSyrup));
        console.log("MplUserActions deployed at: %s", mplUserActions);

        vm.stopBroadcast();
    }

}
