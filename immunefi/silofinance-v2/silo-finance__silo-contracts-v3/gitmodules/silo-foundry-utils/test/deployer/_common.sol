// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

// solhint-disable no-console
import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ICounter} from "./mocks/ICounter.sol";

abstract contract CommonDeploymentTest is Test {
    string internal _anvilPID;

    string internal constant _CHAIN_ID = "9119";
    string internal constant _RPC_URL = "http://127.0.0.1:8546";

    function testDeployContract() public {
        _runAnvil();
        _runDeployments();

        string memory path = string.concat("deployments", "/", _CHAIN_ID, "/", _getFileName(), ".json");

        string memory fileData = vm.readFile(path);

        bytes memory addr = stdJson.parseRaw(fileData, ".address");
        address counterAddr = abi.decode(addr, (address));

        uint256 forkId = vm.createFork(_RPC_URL, 1);
        vm.selectFork(forkId);

        ICounter counter = ICounter(counterAddr);

        assertEq(counter.multiplier(), _getMultiplier(), "Failed to deploy contract with proper constructor arguments");

        counter.increment();
        counter.increment();

        assertEq(counter.someNumber(), 2, "Failed to increment");
    }

    function _runDeployments() internal {
        string[] memory cmds = new string[](7);
        cmds[0] = "forge";
        cmds[1] = "script";
        cmds[2] = _getDeploymentScript();
        cmds[3] = "--ffi";
        cmds[4] = "--broadcast";
        cmds[5] = "--rpc-url";
        cmds[6] = _RPC_URL;

        vm.ffi(cmds);
    }

    function _runAnvil() internal {
        string[] memory cmds = new string[](2);
        cmds[0] = "./bash/run-anvil.sh";

        bytes memory output = vm.ffi(cmds);

        _anvilPID = string(output);

        console.log("Started an Anvil with PID: >>>>>>>> ", _anvilPID);
    }

    function _killAnvil() internal {
        if (bytes(_anvilPID).length != 0) {
            string[] memory cmds = new string[](3);
            cmds[0] = "kill";
            cmds[1] = "-9";
            cmds[2] = _anvilPID;

            vm.ffi(cmds);

            _anvilPID = "";

            console.log("Killed an Anvil with PID: >>>>>>>> ", _anvilPID);
        }
    }

    function _getFileName() internal pure virtual returns (string memory) {}

    function _getDeploymentScript() internal pure virtual returns (string memory) {}

    function _getMultiplier() internal pure virtual returns (uint256) {}
}
