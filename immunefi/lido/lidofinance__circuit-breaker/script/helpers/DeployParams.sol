// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";

/// @title  DeployParams
/// @notice Loads CircuitBreaker constructor parameters from a JSON file.
library DeployParams {
    struct Params {
        address admin;
        uint256 minPauseDuration;
        uint256 maxPauseDuration;
        uint256 minHeartbeatInterval;
        uint256 maxHeartbeatInterval;
        uint256 initialPauseDuration;
        uint256 initialHeartbeatInterval;
    }

    function load(Vm vm, string memory path) internal view returns (Params memory p) {
        string memory json = vm.readFile(path);
        p.admin = vm.parseJsonAddress(json, ".admin");
        p.minPauseDuration = vm.parseJsonUint(json, ".minPauseDuration");
        p.maxPauseDuration = vm.parseJsonUint(json, ".maxPauseDuration");
        p.minHeartbeatInterval = vm.parseJsonUint(json, ".minHeartbeatInterval");
        p.maxHeartbeatInterval = vm.parseJsonUint(json, ".maxHeartbeatInterval");
        p.initialPauseDuration = vm.parseJsonUint(json, ".initialPauseDuration");
        p.initialHeartbeatInterval = vm.parseJsonUint(json, ".initialHeartbeatInterval");
    }
}
