// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {CircuitBreaker, IPausable} from "../src/CircuitBreaker.sol";
import {DeployParams} from "./helpers/DeployParams.sol";

contract MockPausable is IPausable {
    uint256 private _resumeSince;

    function isPaused() external view returns (bool) {
        return block.timestamp < _resumeSince;
    }

    function pauseFor(uint256 _duration) external {
        _resumeSince = block.timestamp + _duration;
    }
}

/// @title  PostDeploy
/// @notice Verifies a deployed CircuitBreaker against the constructor
///         parameters loaded from the same JSON file used at deploy time,
///         then runs a simple happy path on fork.
///
/// Usage (do NOT pass --broadcast; happy path relies on prank cheatcodes):
///
///   CB=<deployed-address> \
///   DEPLOY_PARAMS=deploy-params/hoodi.json \
///   forge script script/PostDeploy.s.sol:PostDeploy \
///     --rpc-url $FORK_RPC_URL
contract PostDeploy is Script {
    function run() external {
        CircuitBreaker cb = CircuitBreaker(vm.envAddress("CB"));
        DeployParams.Params memory p = DeployParams.load(vm, vm.envString("DEPLOY_PARAMS"));

        console.log("CircuitBreaker:", address(cb));
        console.log("chainid:       ", block.chainid);

        // ---------------------------------------------------------------
        // Parameter verification
        // ---------------------------------------------------------------
        require(cb.ADMIN() == p.admin, "ADMIN mismatch");
        require(cb.MIN_PAUSE_DURATION() == p.minPauseDuration, "MIN_PAUSE_DURATION mismatch");
        require(cb.MAX_PAUSE_DURATION() == p.maxPauseDuration, "MAX_PAUSE_DURATION mismatch");
        require(cb.MIN_HEARTBEAT_INTERVAL() == p.minHeartbeatInterval, "MIN_HEARTBEAT_INTERVAL mismatch");
        require(cb.MAX_HEARTBEAT_INTERVAL() == p.maxHeartbeatInterval, "MAX_HEARTBEAT_INTERVAL mismatch");
        require(cb.pauseDuration() == p.initialPauseDuration, "pauseDuration mismatch");
        require(cb.heartbeatInterval() == p.initialHeartbeatInterval, "heartbeatInterval mismatch");
        require(cb.getPausables().length == 0, "getPausables() should be empty at post-deploy");
        console.log("Parameter verification: OK");

        // ---------------------------------------------------------------
        // Happy path (fork simulation only)
        // ---------------------------------------------------------------
        MockPausable pausable = new MockPausable();
        address pauser = makeAddr("post-deploy-pauser");

        vm.prank(p.admin);
        cb.registerPauser(address(pausable), pauser);
        require(cb.getPauser(address(pausable)) == pauser, "pauser not registered");
        require(cb.isPauserLive(pauser), "pauser not live after register");

        vm.prank(pauser);
        cb.pause(address(pausable));
        require(pausable.isPaused(), "pausable not paused");
        require(cb.getPauser(address(pausable)) == address(0), "pauser not cleared after pause");

        console.log("Happy path (register -> pause): OK");
        console.log("PostDeploy: all checks passed");
    }
}
