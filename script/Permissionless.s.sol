// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {CCGHelper} from "../contracts/test/helpers/CCGHelper.sol";
import {GlobalSetup} from "../contracts/test/helpers/GlobalSetup.sol";
import {TestKeys} from "../contracts/test/helpers/TestKeys.sol";

contract PermissionlessScript is Script, GlobalSetup {
    function run() public {
        // Setup test keys
        TestKeys testKeys = new TestKeys();

        if (!_isTestMode()) {
            // Print debug info
            testKeys.printKeys();
        }

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        uint256 length = testKeys.initialSigners().length;

        address[] memory addressesToFund = new address[](3);
        addressesToFund[0] = testKeys.initialSigners()[length - 1].addr;
        addressesToFund[1] = testKeys.bytecodeAuthor().addr;
        addressesToFund[2] = testKeys.dao().addr;

        _fundActors(addressesToFund, 1 ether);
        _deployGlobalContracts(
            testKeys.initialSigners(),
            testKeys.bytecodeAuthor(),
            testKeys.auditor(),
            "Initial Auditor",
            testKeys.threshold(),
            testKeys.dao().addr
        );

        vm.stopBroadcast();

        _exportJson();
    }
}
