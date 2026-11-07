// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Domain} from "../contracts/libraries/Domain.sol";

import {AttachScriptBase} from "../contracts/test/suite/AttachScriptBase.sol";

contract AllowPublicContracts is AttachScriptBase {
    function setUp() public {
        _attachCore();
    }

    function run() external {
        string memory csvPath = vm.envString("CSV_PATH");

        vm.startBroadcast();
        while (true) {
            string memory line = vm.readLine(csvPath);
            if (bytes(line).length == 0) break;
            string[] memory fields = vm.split(line, ",");

            bytes32 bytecodeHash = vm.parseBytes32(fields[0]);
            bytes32 domain = Domain.extractDomain(bytecodeRepository.getBytecode(bytecodeHash).contractType);
            if (bytecodeRepository.isPublicDomain(domain)) bytecodeRepository.allowPublicContract(bytecodeHash);
        }
        vm.stopBroadcast();
    }
}
