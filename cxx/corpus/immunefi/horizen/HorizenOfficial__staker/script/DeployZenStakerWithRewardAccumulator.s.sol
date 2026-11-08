// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEarningPowerCalculator} from "../src/interfaces/IEarningPowerCalculator.sol";
import {IdentityEarningPowerCalculator} from
  "../src/calculators/IdentityEarningPowerCalculator.sol";
import {ZenStaker} from "../src/ZenStaker.sol";
import {RewardAccumulator} from "../src/RewardAccumulator.sol";

/// @notice Deploys IdentityEarningPowerCalculator, ZenStaker, and RewardAccumulator.
/// The deployer is set as the staker's admin temporarily so it can authorize reward
/// notifiers, then hands admin over to ADMIN_ADDRESS via setAdmin() at the end.
/// Required environment variables:
///   ZEN_TOKEN_ADDRESS        — address of the deployed ZEN ERC20 token
///   ADMIN_ADDRESS            — address of the Horizen multisig (final staker admin)
///   PRIVATE_KEY              — deployer private key (hex, with or without 0x prefix)
///   REWARD_NOTIFIER_ADDRESS  — additional address to authorize as reward notifier
///
/// Optional:
///   MAX_BUMP_TIP             — uint256, defaults to 0
///   TIME_WINDOW              — uint256, defaults to 30 days
///   WHITELIST_ENABLED        — bool, defaults to false
///   VERIFY                   — bool, defaults to false. When true, verifies ZenStaker and
///                              RewardAccumulator on a Blockscout instance after deploying.
///                              The chain ID is read automatically from `block.chainid`
///                              (i.e. whatever chain `--rpc-url` points at).
///                              Requires running `forge script` with `--ffi`.
///   VERIFIER_URL             — Blockscout API URL, e.g.
///                              https://horizen-testnet.explorer.caldera.xyz/api
///                              Required when VERIFY=true.
///   VERIFIER_API_KEY         — API key, only if the Blockscout instance requires one. Optional.
contract DeployZenStakerWithRewardAccumulator is Script {
  function run()
    external
    returns (
      IdentityEarningPowerCalculator calculator,
      ZenStaker staker,
      RewardAccumulator accumulator
    )
  {
    address zenToken = vm.envAddress("ZEN_TOKEN_ADDRESS");
    address admin = vm.envAddress("ADMIN_ADDRESS");
    address rewardNotifier = vm.envAddress("REWARD_NOTIFIER_ADDRESS");
    uint256 maxBumpTip = vm.envOr("MAX_BUMP_TIP", uint256(0));
    uint256 timeWindow = vm.envOr("TIME_WINDOW", uint256(30 days));
    bool whitelistEnabled = vm.envOr("WHITELIST_ENABLED", false);
    uint256 deployerKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerKey);
    bool verify = vm.envOr("VERIFY", false);

    vm.startBroadcast(deployerKey);

    calculator = new IdentityEarningPowerCalculator();
    console2.log("IdentityEarningPowerCalculator:", address(calculator));

    // Deployer is set as the initial admin so it can configure reward notifiers below;
    // admin is handed over to the real ADMIN_ADDRESS at the end.
    staker = new ZenStaker(
      IERC20(zenToken),
      IEarningPowerCalculator(address(calculator)),
      maxBumpTip,
      deployer
    );
    console2.log("ZenStaker:                    ", address(staker));

    accumulator = new RewardAccumulator(
      staker,
      ERC20(zenToken),
      timeWindow,
      whitelistEnabled
    );
    console2.log("RewardAccumulator:           ", address(accumulator));

    staker.setRewardNotifier(address(accumulator), true);
    staker.setRewardNotifier(rewardNotifier, true);
    staker.setAdmin(admin);

    console2.log("Admin:                        ", admin);
    console2.log("ZEN token:                    ", zenToken);
    console2.log("Additional reward notifier:   ", rewardNotifier);
    console2.log("Time window:                  ", timeWindow);
    console2.log("Whitelist enabled:            ", whitelistEnabled);

    vm.stopBroadcast();

    if (verify) {
      _verifyOnBlockscout(
        address(staker),
        "src/ZenStaker.sol:ZenStaker",
        abi.encode(zenToken, address(calculator), maxBumpTip, deployer)
      );
      _verifyOnBlockscout(
        address(accumulator),
        "src/RewardAccumulator.sol:RewardAccumulator",
        abi.encode(address(staker), zenToken, timeWindow, whitelistEnabled)
      );
    }
  }

  /// @dev Shells out to `forge verify-contract` against a Blockscout instance. Requires the
  /// script to be run with `--ffi`. The chain ID is read from `block.chainid`, i.e. whatever
  /// chain the script is broadcasting to — no need to pass it explicitly.
  function _verifyOnBlockscout(address deployed, string memory contractPath, bytes memory constructorArgs)
    internal
  {
    string memory verifierUrl = vm.envString("VERIFIER_URL");
    string memory apiKey = vm.envOr("VERIFIER_API_KEY", string(""));

    string[] memory cmd = new string[](15);
    uint256 i;
    cmd[i++] = "forge";
    cmd[i++] = "verify-contract";
    cmd[i++] = vm.toString(deployed);
    cmd[i++] = contractPath;
    cmd[i++] = "--verifier";
    cmd[i++] = "blockscout";
    cmd[i++] = "--verifier-url";
    cmd[i++] = verifierUrl;
    cmd[i++] = "--chain-id";
    cmd[i++] = vm.toString(block.chainid);
    cmd[i++] = "--constructor-args";
    cmd[i++] = vm.toString(constructorArgs);
    cmd[i++] = "--watch";
    if (bytes(apiKey).length > 0) {
      cmd[i++] = "--verifier-api-key";
      cmd[i++] = apiKey;
    }
    // shrink the array to the number of args actually written (only ever shrinking, never
    // growing past the allocated 15 slots, so this is safe).
    assembly {
      mstore(cmd, i)
    }

    console2.log("Verifying", contractPath, "at", deployed);
    vm.ffi(cmd);
  }
}
