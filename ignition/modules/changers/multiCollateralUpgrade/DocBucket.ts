import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { deployDocBucket, getDocBucketParams } from "./deployers";

/**
 * Hardhat Ignition module for DocBucket deployment (refactored version)
 *
 * This module uses the shared deployDocBucket function, which can also be
 * called from FullMultiCollateralUpgrade to avoid code duplication.
 *
 * Note: This module requires FeeFlow to be deployed first.
 * The fees splitter and TC interest collector addresses must be provided via parameters.
 *
 * Usage:
 *   npx hardhat ignition deploy ignition/modules/DocBucket.ts \
 *     --parameters ignition/parameters/docBucket/rskMainnet.json \
 *     --network rskMainnet
 */
const DocBucketModule = buildModule("DocBucket", m => {
  // Get base parameters from module parameters (no prefix for standalone)
  const baseParams = getDocBucketParams(m);

  // Fee-flow addresses must be provided via parameters for standalone deployment
  const params = {
    ...baseParams,
    feesSplitterAddress: m.getParameter<string>("feesSplitterAddress"),
    tcInterestCollectorAddress: m.getParameter<string>("tcInterestCollectorAddress"),
  };

  // Deploy using the shared deployer function
  return deployDocBucket(m, params);
});

export default DocBucketModule;
