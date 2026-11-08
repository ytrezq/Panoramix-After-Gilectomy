// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {AuditReport} from "../contracts/interfaces/Types.sol";

import {AttachScriptBase} from "../contracts/test/suite/AttachScriptBase.sol";

contract SubmitAuditReports is AttachScriptBase {
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
            AuditReport memory auditReport = AuditReport({
                auditor: vm.parseAddress(fields[1]),
                reportUrl: fields[2],
                signature: vm.parseBytes(fields[3])
            });

            bytecodeRepository.submitAuditReport(bytecodeHash, auditReport);
        }
        vm.stopBroadcast();
    }
}
