// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {Counter} from "../mocks/Counter.sol";
import {CommonDeploy} from "./_CommonDeploy.sol";

/**
 * forge script test/deployer/deployments-scripts/SolidityCounterDeploy.s.sol \
 *     --ffi --broadcast --rpc-url http://127.0.0.1:8545
 */
contract SolidityCounterDeploy is CommonDeploy {
    uint256 public testMultiplier = 111;

    function setUp() public {}

    function run() public returns (address counter) {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY", uint256(bytes32(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80))
        );

        vm.startBroadcast(deployerPrivateKey);

        counter = address(new Counter(testMultiplier));

        _registerDeployment(counter, _COUNTER_SOL);

        vm.stopBroadcast();

        _syncDeployments();
    }
}
