import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { deployMocSwappers, getMocSwappersParams } from "../deployers";

/**
 * Hardhat Ignition module for MocSwappers deployment (refactored version)
 *
 * This module uses the shared deployMocSwappers function, which can also be
 * called from FullMultiCollateralUpgrade to avoid code duplication.
 *
 * Usage:
 *   npx hardhat ignition deploy ignition/modules/MocSwappers.ts \
 *     --parameters ignition/parameters/mocSwappers/rskMainnet.json \
 *     --network rskMainnet
 */
const MocSwappersModule = buildModule("MocSwappers", m => {
  // Get all parameters from the module parameters (no prefix for standalone)
  const params = getMocSwappersParams(m);

  // Deploy using the shared deployer function
  return deployMocSwappers(m, params);
});

export default MocSwappersModule;
