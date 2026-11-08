// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {CircuitBreaker} from "../src/CircuitBreaker.sol";
import {DeployParams} from "./helpers/DeployParams.sol";

/// @title  Deploy
/// @notice Deploys CircuitBreaker. Constructor parameters are loaded from a
///         JSON file referenced by the DEPLOY_PARAMS env var.
///
/// Usage:
///   DEPLOY_PARAMS=deploy-params/<network>.json \
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url <rpc-url> \
///     --account <keystore-name> \
///     --broadcast \
///     --verify
///
/// Output:
///   Writes deploy artifact to <DEPLOY_NAME or chainid>.json.
contract Deploy is Script {
    function run() external {
        string memory paramsPath = vm.envString("DEPLOY_PARAMS");
        DeployParams.Params memory p = DeployParams.load(vm, paramsPath);

        console.log("Deploying CircuitBreaker");
        console.log("  chainid:                  ", block.chainid);
        console.log("  paramsPath:               ", paramsPath);
        console.log("  admin:                    ", p.admin);
        console.log("  minPauseDuration:         ", p.minPauseDuration);
        console.log("  maxPauseDuration:         ", p.maxPauseDuration);
        console.log("  minHeartbeatInterval:     ", p.minHeartbeatInterval);
        console.log("  maxHeartbeatInterval:     ", p.maxHeartbeatInterval);
        console.log("  initialPauseDuration:     ", p.initialPauseDuration);
        console.log("  initialHeartbeatInterval: ", p.initialHeartbeatInterval);

        // Capture the broadcaster — the account that actually signs and sends
        // the deploy tx. It must be read inside the broadcast context: outside
        // it (e.g. after stopBroadcast) msg.sender is Foundry's default sender,
        // not the configured --account / --sender / --ledger signer.
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        CircuitBreaker circuitBreaker = new CircuitBreaker(
            p.admin,
            p.minPauseDuration,
            p.maxPauseDuration,
            p.minHeartbeatInterval,
            p.maxHeartbeatInterval,
            p.initialPauseDuration,
            p.initialHeartbeatInterval
        );
        vm.stopBroadcast();

        string memory args = "args";
        vm.serializeAddress(args, "admin", p.admin);
        vm.serializeUint(args, "minPauseDuration", p.minPauseDuration);
        vm.serializeUint(args, "maxPauseDuration", p.maxPauseDuration);
        vm.serializeUint(args, "minHeartbeatInterval", p.minHeartbeatInterval);
        vm.serializeUint(args, "maxHeartbeatInterval", p.maxHeartbeatInterval);
        vm.serializeUint(args, "initialPauseDuration", p.initialPauseDuration);
        string memory argsJson = vm.serializeUint(args, "initialHeartbeatInterval", p.initialHeartbeatInterval);

        string memory meta = "meta";
        vm.serializeAddress(meta, "deployer", deployer);
        vm.serializeUint(meta, "chainId", block.chainid);
        // The deploy tx is not yet mined when this artifact is written, so its
        // hash, mined block number and timestamp are unknowable here. They are
        // emitted as empty placeholders to be filled in by hand from the
        // broadcast receipt / explorer once the deployment is confirmed.
        vm.serializeString(meta, "txHash", "");
        vm.serializeString(meta, "blockNumber", "");
        string memory metaJson = vm.serializeString(meta, "timestamp", "");

        string memory root = "root";
        vm.serializeAddress(root, "circuitBreaker", address(circuitBreaker));
        vm.serializeString(root, "constructorArgs", argsJson);
        string memory output = vm.serializeString(root, "meta", metaJson);

        string memory path = string.concat(vm.envOr("DEPLOY_NAME", vm.toString(block.chainid)), ".json");
        vm.writeJson(output, path);

        console.log("CircuitBreaker deployed at:", address(circuitBreaker));
        console.log("Artifact written to", path);
    }
}
