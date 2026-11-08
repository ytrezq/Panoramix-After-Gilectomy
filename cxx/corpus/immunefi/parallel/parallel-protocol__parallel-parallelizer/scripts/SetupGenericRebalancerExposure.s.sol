// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./Base.s.sol";

import { GenericRebalancer } from "contracts/helpers/GenericRebalancer.sol";
import { BaseRebalancer } from "contracts/helpers/BaseRebalancer.sol";

contract SetupGenericRebalancerExposure is BaseScript {
  BaseRebalancer genericRebalancer = BaseRebalancer(0x57770C1721Eb35509f38210A935c8b1911db7E0e);

  function run() public broadcast {
    accessManager.grantRole(Roles.GUARDIAN_ROLE, broadcaster, 0);
    genericRebalancer.setYieldBearingAssetData(
      // yieldBearingAsset
      address(0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2),
      // asset
      address(0xcA727511c9d542AAb9eF406d24E5bbbE4567c22d),
      // targetExposure
      900_000_000, // targetExposure 90%
      200_000_000, // minExposure 20%
      950_000_000, // maxExposure 95%
      1, // overrideExposures
      1_000_000 // maxSlippage 1%
    );
  }
}
