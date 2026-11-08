// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {AttachBase} from "./AttachBase.sol";

contract AttachTestBase is AttachBase, Test {
    function _setUp() internal virtual override {
        deployer = vm.createWallet("Fake Deployer");
        author = vm.createWallet("Fake Author");
        auditor = vm.createWallet("Fake Auditor");
        riskCurator = vm.createWallet("Fake Risk Curator");

        super._setUp();
    }
}
