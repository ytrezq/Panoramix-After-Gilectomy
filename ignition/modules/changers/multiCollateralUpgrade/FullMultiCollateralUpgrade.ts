import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import {
  deployMocSwappers,
  deployFeeFlow,
  deployDocBucket,
  deployMultiCollateralUpgrade,
  getMocSwappersParams,
  getFeeFlowParams,
  getDocBucketParams,
  getMultiCollateralUpgradeParams,
} from "./deployers";

/**
 * Full Multi-Collateral Upgrade Module (Orchestrator using deployers)
 *
 * This module orchestrates the deployment of all components needed for the
 * MultiCollateral upgrade. It uses the shared deployer functions to avoid
 * code duplication - the same functions can be used for standalone deployment.
 *
 * Deployment order:
 * 1. MocSwappers - Deploy swappers (independent)
 * 2. FeeFlow - Deploy splitters and reverse auctions (depends on swapper outputs)
 * 3. DocBucket - Deploy DOC bucket (depends on FeeFlow outputs)
 * 4. MultiCollateralUpgrade - Deploy Guard, RIF Queue, etc. (depends on DocBucket, FeeFlow, Swappers)
 *
 *
 */
const FullMultiCollateralUpgradeModule = buildModule("FullMultiCollateralUpgrade", m => {
  // ============================================================================
  // STEP 1: Deploy MocSwappers (using shared deployer)
  // Parameters are read directly (same as MocSwappers module)
  // ============================================================================
  const swappersParams = getMocSwappersParams(m, "MocSwappers");
  const swappers = deployMocSwappers(m, swappersParams, "Swappers");

  // ============================================================================
  // STEP 2: Deploy FeeFlow (using shared deployer, depends on swappers)
  // Parameters are read directly (same as FeeFlow module)
  // Swapper addresses come from step 1 outputs (not from params)
  // ============================================================================
  const feeFlowBaseParams = getFeeFlowParams(m, "FeeFlow");
  const feeFlow = deployFeeFlow(
    m,
    {
      ...feeFlowBaseParams,
      // Inject swapper addresses from MocSwappers deployment
      mocSwapperV3Multihop: swappers.mocSwapperV3MultihopProxy,
    },
    "FeeFlow",
  );

  // ============================================================================
  // STEP 3: Deploy DocBucket (using shared deployer, depends on FeeFlow)
  // Parameters are read directly (same as DocBucket module)
  // Fee-flow addresses come from step 2 outputs (not from params)
  // ============================================================================
  const docBucketBaseParams = getDocBucketParams(m, "DocBucket");
  const docBucket = deployDocBucket(
    m,
    {
      ...docBucketBaseParams,
      // Inject fee-flow addresses from FeeFlow deployment
      feesSplitterAddress: feeFlow.feesSplitterProxy,
      tcInterestCollectorAddress: feeFlow.reverseAuctionDOCtoMOC,
    },
    "DocBucket",
  );

  // ============================================================================
  // STEP 4: Deploy MultiCollateralUpgrade (depends on DocBucket, FeeFlow, Swappers)
  // Parameters are read directly (same as MultiCollateralUpgrade module)
  // Needs docBucket and swapper addresses from previous steps
  // ============================================================================
  const multiCollateralParams = getMultiCollateralUpgradeParams(m, "MultiCollateralUpgrade");
  const multiCollateral = deployMultiCollateralUpgrade(
    m,
    {
      ...multiCollateralParams,
      // Inject addresses from other deployments
      docBucketAddress: docBucket.docBucketProxy,
      rifToDocSwapperAddress: swappers.mocSwapperV3MultihopProxy,
      reverseAuctionDOCtoMOCAddress: feeFlow.reverseAuctionDOCtoMOC,
      reverseAuctionMOCtoDOCAddress: feeFlow.reverseAuctionMOCtoDOC,
      rocrRewardsBufferAddress: feeFlow.rocrRewardsBuffer,
    },
    "MultiCollateral",
  );

  // ============================================================================
  // Return all deployed contracts
  // ============================================================================
  return {
    // === MocSwappers ===
    interimGovernor: swappers.interimGovernor,
    mocSwapperV3MultihopImpl: swappers.mocSwapperV3MultihopImpl,
    mocSwapperV3MultihopProxy: swappers.mocSwapperV3MultihopProxy,
    mocSwapperV3Multihop: swappers.mocSwapperV3Multihop,

    // === FeeFlow ===
    feesSplitterImpl: feeFlow.feesSplitterImpl,
    feesSplitterProxy: feeFlow.feesSplitterProxy,
    reverseAuctionDOCtoMOC: feeFlow.reverseAuctionDOCtoMOC,
    reverseAuctionMOCtoDOC: feeFlow.reverseAuctionMOCtoDOC,
    rocrRewardsBuffer: feeFlow.rocrRewardsBuffer,

    // === DocBucket ===
    docBucketImpl: docBucket.mocCARC20Impl,
    docBucketProxy: docBucket.docBucketProxy,
    docBucketTCImpl: docBucket.mocTCImpl,
    docBucketTCProxy: docBucket.mocTCProxy,
    docBucketQueueImpl: docBucket.mocQueueImpl,
    docBucketQueueProxy: docBucket.mocQueueProxy,
    docBucketCoreExpansion: docBucket.mocCoreExpansion,

    // === MultiCollateralUpgrade (RIF Bucket) ===
    mocMultiCollateralGuardImpl: multiCollateral.mocMultiCollateralGuardImpl,
    mocMultiCollateralGuardProxy: multiCollateral.mocMultiCollateralGuardProxy,
    rifBucketQueueImpl: multiCollateral.mocQueueImpl,
    rifBucketQueueProxy: multiCollateral.mocQueueProxy,
    mocRifImplementation: multiCollateral.mocRifImplementation,
    usdRifImplementation: multiCollateral.usdRifImplementation,
    rifBucketCoreExpansion: multiCollateral.mocCoreExpansion,
    multiCollateralUpgradeChanger: multiCollateral.multiCollateralUpgradeChanger,
  };
});

export default FullMultiCollateralUpgradeModule;
