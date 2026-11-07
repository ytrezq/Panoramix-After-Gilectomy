// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { Locker } from "src/Locker.sol";
import { Operator } from "src/Operator.sol";
import { YToken } from "src/YToken.sol";
import { Protocol, YB, YBS, CreateX } from "src/utils/Constants.sol";
import { SafeHelper } from "script/utils/SafeHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { IYBSRegistry } from "src/interfaces/ybs/IYBSRegistry.sol";

contract Deploy is Script, SafeHelper, CreateXHelper, TenderlyHelper {

    Locker locker = Locker(payable(Protocol.LOCKER));
    Operator operator = Operator(Protocol.OPERATOR);
    YToken yToken = YToken(Protocol.YTOKEN);

    function run() public isBatch(Protocol.OWNER) {
        deployMode = DeployMode.FORK;
        maxGasPerBatch = 15_000_000;

        (address ybs, address distributor, address utils) = deployYBS();
        console.log("--- YBS deployed ---");
        console.log("ybs", ybs);
        console.log("distributor", distributor);
        console.log("utils", utils);

        if (deployMode == DeployMode.PRODUCTION) executeBatch(true, 0);
    }

    function deployYBS() public returns (address ybs, address distributor, address utils) {
        bytes memory result = addToBatch(
            address(YBS.REGISTRY),
            abi.encodeWithSelector(IYBSRegistry.createNewDeployment.selector,
                YBS.STAKE_TOKEN,
                4, // max_stake_growth_weeks
                0, // start_time
                YBS.REWARD_TOKEN
            )
        );
        (ybs, distributor, utils) = abi.decode(result, (address, address, address));
    }
}