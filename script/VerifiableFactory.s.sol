// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {VerifiableFactory} from "../src/VerifiableFactory.sol";

contract CounterScript is Script {
    VerifiableFactory public factory;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        factory = new VerifiableFactory();

        vm.stopBroadcast();
    }
}
