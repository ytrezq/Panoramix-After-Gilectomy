// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {CommonDeploymentTest} from "./_common.sol";

import {ICounter} from "./mocks/ICounter.sol";
import {SolidityCounterDeploy} from "./deployments-scripts/SolidityCounterDeploy.s.sol";

// ./bash/build-for-tests.sh
// forge clean && forge test --match-contract DeploySolidityTest --ffi -vvv && ./bash/kill-anvil.sh
contract DeploySolidityTest is CommonDeploymentTest {
    string internal constant _FILE = "Counter.sol";
    string internal constant _DEPLOYMENT_SCRIPT = "test/deployer/deployments-scripts/SolidityCounterDeploy.s.sol";
    uint256 internal constant _MULTIPLIER = 111;

    function testDeploymentScriptInTest() public {
        SolidityCounterDeploy script = new SolidityCounterDeploy();
        script.disableDeploymentsSync();

        address counterAddr = script.run();

        ICounter counter = ICounter(counterAddr);

        assertEq(counter.someNumber(), 0, "Invalid number");

        counter.increment();
        counter.increment();

        assertEq(counter.someNumber(), 2, "Failed to increment");
    }

    function _getFileName() internal pure override returns (string memory) {
        return _FILE;
    }

    function _getDeploymentScript() internal pure override returns (string memory) {
        return _DEPLOYMENT_SCRIPT;
    }

    function _getMultiplier() internal pure override returns (uint256) {
        return _MULTIPLIER;
    }
}
