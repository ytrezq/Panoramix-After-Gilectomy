// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from 'forge-std/Script.sol';
import {GovHelpers} from 'aave-helpers/GovHelpers.sol';

contract ProposalDeployment is Script {
  function run() external {
    GovHelpers.Payload[] memory payloads = new GovHelpers.Payload[](5);
    payloads[0] = GovHelpers.buildMainnet(
      address(0x7fc3FCb14eF04A48Bb0c12f0c39CD74C249c37d8) // deployed mainnet payload
    );
    payloads[1] = GovHelpers.buildPolygon(
      address(0xA9F30e6ED4098e9439B2ac8aEA2d3fc26BcEbb45) // deployed polygon payload
    );
    payloads[2] = GovHelpers.buildPolygon(
      address(0xC383AAc4B3dC18D9ce08AB7F63B4632716F1e626) // deployed polygon v2 payload
    );
    payloads[3] = GovHelpers.buildArbitrum(
      address(0x05225Cd708bCa9253789C1374e4337a019e99D56) // deployed arbitrum payload
    );
    payloads[4] = GovHelpers.buildOptimism(
      address(0xA9F30e6ED4098e9439B2ac8aEA2d3fc26BcEbb45) // deployed optimism payload
    );

    vm.startBroadcast();

    GovHelpers.createProposal(
      payloads,
      0xb1fe8b52c60e67743e3f9d406bb267f517fc87b6cd63e23b0754fa8e52c67441
    );

    vm.stopBroadcast();
  }
}
