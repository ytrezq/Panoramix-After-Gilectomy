// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ZenStaker} from "../src/ZenStaker.sol";

/// @notice Enables a reward notifier on a deployed ZenStaker. Must be called by the admin.
/// Required environment variables:
///   STAKER_ADDRESS          — address of the deployed ZenStaker
///   REWARD_NOTIFIER_ADDRESS — address of the reward notifier to enable
///   PRIVATE_KEY             — admin private key (hex, with or without 0x prefix)
contract ConfigureRewardNotifier is Script {
  function run() external {
    address stakerAddr = vm.envAddress("STAKER_ADDRESS");
    address notifier = vm.envAddress("REWARD_NOTIFIER_ADDRESS");
    uint256 adminKey = vm.envUint("PRIVATE_KEY");

    vm.startBroadcast(adminKey);
    ZenStaker(stakerAddr).setRewardNotifier(notifier, true);
    console2.log("Reward notifier enabled:      ", notifier);
    console2.log("On staker:                    ", stakerAddr);
    vm.stopBroadcast();
  }
}
