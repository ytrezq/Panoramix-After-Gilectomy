import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { deployFeeFlow, getFeeFlowParams } from "./deployers";

/**
 * Hardhat Ignition module for FeeFlow deployment (refactored version)
 *
 * This module uses the shared deployFeeFlow function, which can also be
 * called from FullMultiCollateralUpgrade to avoid code duplication.
 *
 * Note: This module requires the DOC/MOC swapper to be deployed first.
 * The DOC/MOC swapper address must be provided via parameters.
 *
 * Usage:
 *   npx hardhat ignition deploy ignition/modules/FeeFlow.ts \
 *     --parameters ignition/parameters/feeFlow/rskMainnet.json \
 *     --network rskMainnet
 */
const FeeFlowModule = buildModule("FeeFlow", m => {
  // Get base parameters from module parameters (no prefix for standalone)
  const baseParams = getFeeFlowParams(m);

  // Swapper address must be provided via parameters for standalone deployment
  const params = {
    ...baseParams,
    mocSwapperV3Multihop: m.getParameter<string>("mocSwapperV3Multihop"),
  };

  // Deploy using the shared deployer function
  return deployFeeFlow(m, params);
});

export default FeeFlowModule;
