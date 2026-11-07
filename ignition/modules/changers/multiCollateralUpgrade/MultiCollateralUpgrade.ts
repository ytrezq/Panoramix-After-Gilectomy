import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { deployMultiCollateralUpgrade, getMultiCollateralUpgradeParams } from "./deployers";

/**
 * Hardhat Ignition module for MultiCollateralUpgrade deployment (refactored version)
 *
 * This module uses the shared deployMultiCollateralUpgrade function, which can also be
 * called from FullMultiCollateralUpgrade to avoid code duplication.
 *
 * Usage:
 *   npx hardhat ignition deploy ignition/modules/MultiCollateralUpgrade.ts \
 *     --parameters ignition/parameters/multiCollateralUpgrade/rskMainnet.json \
 *     --network rskMainnet
 */
const MultiCollateralUpgradeModule = buildModule("MultiCollateralUpgrade", m => {
  // Get all parameters from module parameters (no prefix for standalone)
  const params = getMultiCollateralUpgradeParams(m);

  const reverseAuctionDOCtoMOCAddress = m.getParameter<string>("reverseAuctionDOCtoMOCAddress");

  // Deploy using the shared deployer function
  return deployMultiCollateralUpgrade(m, {
    ...params,
    reverseAuctionDOCtoMOCAddress,
  });
});

export default MultiCollateralUpgradeModule;
