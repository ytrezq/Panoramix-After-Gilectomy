// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {RewardAccumulator} from "../src/RewardAccumulator.sol";
import {Staker} from "../src/Staker.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Deploys RewardAccumulator.
/// Required environment variables:
///   STAKER_ADDRESS      — address of the deployed Staker-compatible contract
///   REWARD_TOKEN_ADDRESS — address of the ERC20 reward token
///   PRIVATE_KEY         — deployer private key (hex, with or without 0x prefix)
///
/// Optional:
///   TIME_WINDOW         — uint256, defaults to 1 days
///   WHITELIST_ENABLED   — bool, defaults to false
contract DeployRewardAccumulator is Script {
    function run() external returns (RewardAccumulator accumulator) {
        address stakerAddress = vm.envAddress("STAKER_ADDRESS");
        address rewardTokenAddress = vm.envAddress("REWARD_TOKEN_ADDRESS");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        uint256 timeWindow = vm.envOr("TIME_WINDOW", uint256(1 days));
        bool whitelistEnabled = vm.envOr("WHITELIST_ENABLED", false);

        vm.startBroadcast(deployerKey);

        accumulator = new RewardAccumulator(
            Staker(stakerAddress),
            ERC20(rewardTokenAddress),
            timeWindow,
            whitelistEnabled
        );

        console2.log("RewardAccumulator:", address(accumulator));
        console2.log("Staker:            ", stakerAddress);
        console2.log("Reward token:      ", rewardTokenAddress);
        console2.log("Time window:       ", timeWindow);
        console2.log("Whitelist enabled:", whitelistEnabled);
        vm.stopBroadcast();
    }
}
