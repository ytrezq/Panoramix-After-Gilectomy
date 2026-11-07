// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { Protocol, YBS, Curve, YB } from "src/utils/Constants.sol";
import { Zap } from "src/Zap.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";

contract DeployZap is Script, TenderlyHelper {

    function run() public  {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        Zap zap = new Zap(
            YB.TOKEN, // asset
            Protocol.YTOKEN, // yYB
            Protocol.YV_YYB, // st-yYB
            Protocol.YV_LPYYB, // lp-yYB
            YBS.YBS_YB, // ybs-yYB
            Curve.POOL, // pool
            YB.VEYB // veYb
        );
        console.log("--- Zap deployed ---");
        console.log("zap:", address(zap));
        vm.stopBroadcast();
    }
}
