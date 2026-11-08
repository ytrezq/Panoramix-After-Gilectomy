// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { Protocol, YB, Curve } from "src/utils/Constants.sol";
import { ICurvePool } from "src/interfaces/curve/ICurvePool.sol";
import { SafeHelper } from "script/utils/SafeHelper.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";

contract DeployCurvePool is Script, SafeHelper, TenderlyHelper {

    function run() public  {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        uint8[] memory assetTypes = new uint8[](2);
        assetTypes[0] = 0; // Standard ERC20
        assetTypes[1] = 0; // Standard ERC20

        address[] memory coins = new address[](2);
        coins[0] = YB.TOKEN;
        coins[1] = Protocol.YTOKEN;

        bytes4[] memory methods = new bytes4[](2);
        address[] memory oracles = new address[](2);

        address pool = Curve.POOL;
        pool = ICurvePool(Curve.CURVE_STABLE_FACTORY).deploy_plain_pool(
            "YB/yYB", // name
            "yYB-LP", // symbol
            coins, // coins
            37, // A
            25000000, // fee
            20000000000, // offpeg_fee_multiplier
            866, // ma_exp_time
            0, // implementation_idx
            assetTypes, // asset_types
            methods, // method_ids
            oracles // oracles
        );
        console.log("--- Curve Pool deployed ---");
        console.log("pool", pool);

        address gauge = ICurvePool(Curve.CURVE_STABLE_FACTORY).deploy_gauge(pool);
        console.log("--- Curve Gauge deployed ---");
        console.log("gauge:", gauge);
    }
}