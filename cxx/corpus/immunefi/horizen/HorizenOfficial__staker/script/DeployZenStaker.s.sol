// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEarningPowerCalculator} from "../src/interfaces/IEarningPowerCalculator.sol";
import {IdentityEarningPowerCalculator} from
  "../src/calculators/IdentityEarningPowerCalculator.sol";
import {ZenStaker} from "../src/ZenStaker.sol";

/// @notice Deploys IdentityEarningPowerCalculator then ZenStaker.
/// Required environment variables:
///   ZEN_TOKEN_ADDRESS  — address of the deployed ZEN ERC20 token
///   ADMIN_ADDRESS      — address of the Horizen multisig (becomes staker admin)
///   PRIVATE_KEY        — deployer private key (hex, with or without 0x prefix)
///
/// Optional:
///   MAX_BUMP_TIP       — uint256, defaults to 0
contract DeployZenStaker is Script {
  function run() external returns (IdentityEarningPowerCalculator calculator, ZenStaker staker) {
    address zenToken = vm.envAddress("ZEN_TOKEN_ADDRESS");
    address admin = vm.envAddress("ADMIN_ADDRESS");
    uint256 maxBumpTip = vm.envOr("MAX_BUMP_TIP", uint256(0));
    uint256 deployerKey = vm.envUint("PRIVATE_KEY");

    vm.startBroadcast(deployerKey);

    calculator = new IdentityEarningPowerCalculator();
    console2.log("IdentityEarningPowerCalculator:", address(calculator));

    staker = new ZenStaker(
      IERC20(zenToken),
      IEarningPowerCalculator(address(calculator)),
      maxBumpTip,
      admin
    );
    console2.log("ZenStaker:                    ", address(staker));
    console2.log("Admin:                        ", admin);
    console2.log("ZEN token:                    ", zenToken);

    vm.stopBroadcast();
  }
}
