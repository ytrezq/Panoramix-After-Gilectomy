// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEarningPowerCalculator} from "../src/interfaces/IEarningPowerCalculator.sol";
import {IdentityEarningPowerCalculator} from "../src/calculators/IdentityEarningPowerCalculator.sol";
import {ZenStaker} from "../src/ZenStaker.sol";
import {ERC20VotesMock} from "../test/mocks/MockERC20Votes.sol";

/// @notice Testnet deployment: deploys a public-mint ERC20 test token, then
/// IdentityEarningPowerCalculator + ZenStaker.
/// The deployer becomes the staker admin.
///
/// Required env:
///   PRIVATE_KEY — deployer private key (hex, with or without 0x prefix)
contract DeployZenStakerTestnet is Script {
  function run()
    external
    returns (
      ERC20VotesMock testToken,
      IdentityEarningPowerCalculator calculator,
      ZenStaker staker
    )
  {
    uint256 deployerKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerKey);

    vm.startBroadcast(deployerKey);

    testToken = new ERC20VotesMock();
    console2.log("TestToken (ERC20VotesMock):    ", address(testToken));

    calculator = new IdentityEarningPowerCalculator();
    console2.log("IdentityEarningPowerCalculator:", address(calculator));

    staker = new ZenStaker(
      IERC20(address(testToken)),
      IEarningPowerCalculator(address(calculator)),
      0,
      deployer
    );
    console2.log("ZenStaker:                     ", address(staker));
    console2.log("Admin (deployer):              ", deployer);

    vm.stopBroadcast();
  }
}
