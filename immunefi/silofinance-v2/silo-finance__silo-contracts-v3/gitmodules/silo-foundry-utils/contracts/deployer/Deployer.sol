// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {VyperDeployer} from "./Vyper.sol";
import {ChainsLib} from "../lib/ChainsLib.sol";

abstract contract Deployer is VyperDeployer {
    function _syncSolidityDeployments(Deployment storage deployment) internal override {
        uint256 cmdLen = 14;

        if (bytes(deployment.deploymentsSubDir).length != 0) {
            cmdLen += 2;
        }

        uint256 i;
        string[] memory cmds = new string[](cmdLen);
        cmds[i++] = "./silo-foundry-utils";
        cmds[i++] = "sync";
        cmds[i++] = "--network";
        cmds[i++] = ChainsLib.chainAlias();
        cmds[i++] = "--file";
        cmds[i++] = deployment.name;
        cmds[i++] = "--output";
        cmds[i++] = deployment.fileName;
        cmds[i++] = "--address";
        cmds[i++] = vm.toString(deployment.addr);
        cmds[i++] = "--out_dir";
        cmds[i++] = deployment.forgeOutDir;
        cmds[i++] = "--deployed_at_block";
        cmds[i++] = vm.toString(deployment.deployedAtBlock);

        if (bytes(deployment.deploymentsSubDir).length != 0) {
            cmds[i++] = "--deployments_sub_dir";
            cmds[i++] = deployment.deploymentsSubDir;
        }

        vm.ffi(cmds);
    }

    function _syncVyperDeployments(Deployment storage deployment) internal override {
        uint256 cmdLen = 18;

        if (bytes(deployment.deploymentsSubDir).length != 0) {
            cmdLen += 2;
        }

        string[] memory cmds = new string[](cmdLen);
        cmds[0] = "./silo-foundry-utils";
        cmds[1] = "sync";
        cmds[2] = "--network";
        cmds[3] = ChainsLib.chainAlias();
        cmds[4] = "--file";
        cmds[5] = deployment.name;
        cmds[6] = "--address";
        cmds[7] = vm.toString(deployment.addr);
        cmds[8] = "--bytecode";
        cmds[9] = deployment.bytecode;
        cmds[10] = "--d_bytecode";
        cmds[11] = deployment.deployedByteCode;
        cmds[12] = "--abi";
        cmds[13] = deployment.contractABI;
        cmds[14] = "--compiler";
        cmds[15] = deployment.compilerVersion;
        cmds[16] = "--deployed_at_block";
        cmds[17] = vm.toString(deployment.deployedAtBlock);

        if (bytes(deployment.deploymentsSubDir).length != 0) {
            cmds[18] = "--deployments_sub_dir";
            cmds[19] = deployment.deploymentsSubDir;
        }

        // run command
        vm.ffi(cmds);
    }
}
