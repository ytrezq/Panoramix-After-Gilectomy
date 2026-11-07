import type {
  IgnitionModuleBuilder,
  ModuleParameterRuntimeValue,
  ContractFuture,
} from "@nomicfoundation/ignition-core";
import { getPrefixedParameterName } from "./parameterPrefixes";

// Type aliases for parameters
type StringParam = string | ModuleParameterRuntimeValue<string>;
type BigintParam = bigint | ModuleParameterRuntimeValue<bigint>;
type BooleanParam = boolean | ModuleParameterRuntimeValue<boolean>;
type AddressParam = string | ContractFuture<string>;

/**
 * BucketParams structure for rebalancing
 */
export interface BucketParams {
  rebalanceExecFeeRecipient: StringParam;
  rtcThrld: BigintParam;
  microLiquidationThrld: BigintParam;
  penaltyRate: BigintParam;
}
/**
 * Parameters for deploying MultiCollateralUpgrade
 */
export interface MultiCollateralUpgradeParams {
  governorAddress: StringParam;
  pauserAddress: StringParam;
  rifBucketAddress: StringParam;
  mocState: StringParam;
  rifPriceProvider: StringParam;
  rbtcUsdPriceProvider: StringParam;
  blockSpan: BigintParam;
  // Guard parameters
  microLiquidationExecCost: BigintParam;
  liquidationExecCost: BigintParam;
  coinbaseExecFeeRecipient: StringParam;
  maxOperPerBatch: BigintParam;
  useMaxLastPublicationBlock: BooleanParam;
  // Queue parameters
  rifMinOperWaitingBlk: BigintParam;
  rifMaxOperWaitingBlk: BigintParam;
  rifTcMintExecCost: BigintParam;
  rifTcRedeemExecCost: BigintParam;
  rifTpMintExecCost: BigintParam;
  rifTpRedeemExecCost: BigintParam;
  rifMintTCandTPExecCost: BigintParam;
  rifRedeemTCandTPExecCost: BigintParam;
  rifSwapTPforTPExecCost: BigintParam;
  rifSwapTPforTCExecCost: BigintParam;
  rifSwapTCforTPExecCost: BigintParam;
  rifNewProtectedThrld: BigintParam;
  // Changer parameters (can be injected from other modules)
  docBucketAddress?: AddressParam;
  rifBucketParams?: BucketParams;
  docBucketParams?: BucketParams;
  rifToDocSwapperAddress?: AddressParam;
  governedRegistryAddress: StringParam;
  reverseAuctionDOCtoMOCAddress?: AddressParam;
  reverseAuctionMOCtoDOCAddress?: AddressParam;
  rocrRewardsBufferAddress?: AddressParam;

  // PeggedTokenParams for DOC bucket
  peggedTokenParams?: {
    tpCtarg: BigintParam;
    tpMintFee: BigintParam;
    tpRedeemFee: BigintParam;
    tpEma: BigintParam;
    tpEmaSf: BigintParam;
  };
}

/**
 * Helper to get MultiCollateralUpgrade parameters from module parameters
 * @param m - The IgnitionModuleBuilder
 * @param parameterPrefix - Optional prefix for namespaced parameters (e.g., "MultiCollateralUpgrade" for Full module)
 */
export function getMultiCollateralUpgradeParams(
  m: IgnitionModuleBuilder,
  parameterPrefix?: string,
): MultiCollateralUpgradeParams {
  const getParameter = <T extends string | bigint | boolean | string[] | bigint[]>(parameterName: string) =>
    m.getParameter<T>(getPrefixedParameterName(parameterName, parameterPrefix));

  return {
    governorAddress: getParameter<string>("governorAddress"),
    pauserAddress: getParameter<string>("pauserAddress"),
    rifBucketAddress: getParameter<string>("rifBucketAddress"),
    mocState: getParameter<string>("mocState"),
    rifPriceProvider: getParameter<string>("rifPriceProvider"),
    rbtcUsdPriceProvider: getParameter<string>("rbtcUsdPriceProvider"),
    blockSpan: getParameter<bigint>("blockSpan"),
    microLiquidationExecCost: getParameter<bigint>("microLiquidationExecCost"),
    liquidationExecCost: getParameter<bigint>("liquidationExecCost"),
    coinbaseExecFeeRecipient: getParameter<string>("coinbaseExecFeeRecipient"),
    maxOperPerBatch: getParameter<bigint>("maxOperPerBatch"),
    useMaxLastPublicationBlock: getParameter<boolean>("useMaxLastPublicationBlock"),
    rifMinOperWaitingBlk: getParameter<bigint>("rifMinOperWaitingBlk"),
    rifMaxOperWaitingBlk: getParameter<bigint>("rifMaxOperWaitingBlk"),
    rifTcMintExecCost: getParameter<bigint>("rifTcMintExecCost"),
    rifTcRedeemExecCost: getParameter<bigint>("rifTcRedeemExecCost"),
    rifTpMintExecCost: getParameter<bigint>("rifTpMintExecCost"),
    rifTpRedeemExecCost: getParameter<bigint>("rifTpRedeemExecCost"),
    rifMintTCandTPExecCost: getParameter<bigint>("rifMintTCandTPExecCost"),
    rifRedeemTCandTPExecCost: getParameter<bigint>("rifRedeemTCandTPExecCost"),
    rifSwapTPforTPExecCost: getParameter<bigint>("rifSwapTPforTPExecCost"),
    rifSwapTPforTCExecCost: getParameter<bigint>("rifSwapTPforTCExecCost"),
    rifSwapTCforTPExecCost: getParameter<bigint>("rifSwapTCforTPExecCost"),
    rifNewProtectedThrld: getParameter<bigint>("rifNewProtectedThrld"),
    governedRegistryAddress: getParameter<string>("governedRegistryAddress"),
    // BucketParams for rebalancing
    rifBucketParams: {
      rebalanceExecFeeRecipient: getParameter<string>("rifRebalanceExecFeeRecipient"),
      rtcThrld: getParameter<bigint>("rifRtcThrld"),
      microLiquidationThrld: getParameter<bigint>("rifMicroLiquidationThrld"),
      penaltyRate: getParameter<bigint>("rifPenaltyRate"),
    },
    docBucketParams: {
      rebalanceExecFeeRecipient: getParameter<string>("docRebalanceExecFeeRecipient"),
      rtcThrld: getParameter<bigint>("docRtcThrld"),
      microLiquidationThrld: getParameter<bigint>("docMicroLiquidationThrld"),
      penaltyRate: getParameter<bigint>("docPenaltyRate"),
    },
    peggedTokenParams: {
      tpCtarg: getParameter<bigint>("peggedTokenTpCtarg"),
      tpMintFee: getParameter<bigint>("peggedTokenTpMintFee"),
      tpRedeemFee: getParameter<bigint>("peggedTokenTpRedeemFee"),
      tpEma: getParameter<bigint>("peggedTokenTpEma"),
      tpEmaSf: getParameter<bigint>("peggedTokenTpEmaSf"),
    },
  };
}

/**
 * Deploy MultiCollateralUpgrade with the given parameters
 * This function can be called from the standalone module or from FullMultiCollateralUpgrade
 */
export function deployMultiCollateralUpgrade(
  m: IgnitionModuleBuilder,
  params: MultiCollateralUpgradeParams,
  idPrefix: string = "",
) {
  const prefix = idPrefix ? `${idPrefix}_` : "";

  // Build execution cost params struct
  const execCostParams = {
    tcMintExecCost: params.rifTcMintExecCost,
    tcRedeemExecCost: params.rifTcRedeemExecCost,
    tpMintExecCost: params.rifTpMintExecCost,
    tpRedeemExecCost: params.rifTpRedeemExecCost,
    mintTCandTPExecCost: params.rifMintTCandTPExecCost,
    redeemTCandTPExecCost: params.rifRedeemTCandTPExecCost,
    swapTPforTPExecCost: params.rifSwapTPforTPExecCost,
    swapTPforTCExecCost: params.rifSwapTPforTCExecCost,
    swapTCforTPExecCost: params.rifSwapTCforTPExecCost,
  };

  // Deploy MocMultiCollateralGuard Implementation
  const mocMultiCollateralGuardImpl = m.contract("MocMultiCollateralGuard", [], {
    id: `${prefix}MocMultiCollateralGuardImplementation`,
  });

  // Encode initialize data for MocMultiCollateralGuard
  const guardInitData = m.encodeFunctionCall(mocMultiCollateralGuardImpl, "initialize", [
    params.governorAddress,
    params.pauserAddress,
    params.microLiquidationExecCost,
    params.liquidationExecCost,
    params.coinbaseExecFeeRecipient,
    params.maxOperPerBatch,
    params.useMaxLastPublicationBlock,
  ]);

  // Deploy MocMultiCollateralGuard Proxy (ERC1967)
  const mocMultiCollateralGuardProxy = m.contract("ERC1967Proxy", [mocMultiCollateralGuardImpl, guardInitData], {
    id: `${prefix}MocMultiCollateralGuardProxy`,
  });

  // Deploy MocQueue Implementation
  const mocQueueImpl = m.contract("moc-main-latest/contracts/queue/MocQueue.sol:MocQueue", [], {
    id: `${prefix}MocQueueImplementation`,
  });

  // Encode initialize data for MocQueue
  const queueInitData = m.encodeFunctionCall(mocQueueImpl, "initialize", [
    params.governorAddress,
    params.pauserAddress,
    mocMultiCollateralGuardProxy,
    params.rifMinOperWaitingBlk,
    params.rifMaxOperWaitingBlk,
    execCostParams,
  ]);

  // Deploy MocQueue Proxy (ERC1967)
  const mocQueueProxy = m.contract("ERC1967Proxy", [mocQueueImpl, queueInitData], {
    id: `${prefix}MocQueueProxy`,
  });

  // Deploy MocRif Implementation (MocCoreRif)
  const mocRifImplementation = m.contract("MocRif", [], {
    id: `${prefix}MocRifImplementation`,
  });

  // Deploy StableTokenV2 (USDRif) Implementation
  const usdRifImplementation = m.contract("StableTokenV2", [], {
    id: `${prefix}USDRifImplementation`,
  });

  // Deploy MocCoreExpansion
  const mocCoreExpansion = m.contract("moc-main-latest/contracts/core/MocCoreExpansion.sol:MocCoreExpansion", [], {
    id: `${prefix}MocCoreExpansion`,
  });

  // Deploy WrapperPriceProvider using rifPriceProvider as the underlying provider
  const rifPriceProvider = m.contract("WrapperPriceProvider", [params.rifPriceProvider], {
    id: `${prefix}RifPriceProvider`,
  });

  // Deploy PriceProviderDocUsd for DOC pegged token
  const docToUsdRifPriceProvider = m.contract("PriceProviderDocUsd", [params.mocState], {
    id: `${prefix}DocToUsdRifPriceProvider`,
  });

  // Deploy PriceProviderDocRbtc for DOC/RBTC price
  const docToRbtcPriceProvider = m.contract("PriceProviderDocRbtc", [params.mocState], {
    id: `${prefix}DocToRbtcPriceProvider`,
  });

  // Deploy PriceProviderRifRbtc for RIF/RBTC price
  const rifToRbtcPriceProvider = m.contract("PriceProviderDiv", [rifPriceProvider, params.rbtcUsdPriceProvider], {
    id: `${prefix}RifToRbtcPriceProvider`,
  });

  // Build BucketParams structs for the changer
  const rifBucketParamsStruct = {
    acCoinbasePriceProvider: rifToRbtcPriceProvider,
    rebalanceExecFeeRecipient: params.rifBucketParams!.rebalanceExecFeeRecipient,
    rtcThrld: params.rifBucketParams!.rtcThrld,
    microLiquidationThrld: params.rifBucketParams!.microLiquidationThrld,
    penaltyRate: params.rifBucketParams!.penaltyRate,
  };

  const docBucketParamsStruct = {
    acCoinbasePriceProvider: docToRbtcPriceProvider,
    rebalanceExecFeeRecipient: params.docBucketParams!.rebalanceExecFeeRecipient,
    rtcThrld: params.docBucketParams!.rtcThrld,
    microLiquidationThrld: params.docBucketParams!.microLiquidationThrld,
    penaltyRate: params.docBucketParams!.penaltyRate,
  };

  // Build PeggedTokenParams struct for DOC bucket
  const peggedTokenParamsStruct = {
    priceProviderAddress: docToUsdRifPriceProvider,
    tpCtarg: params.peggedTokenParams!.tpCtarg,
    tpMintFee: params.peggedTokenParams!.tpMintFee,
    tpRedeemFee: params.peggedTokenParams!.tpRedeemFee,
    tpEma: params.peggedTokenParams!.tpEma,
    tpEmaSf: params.peggedTokenParams!.tpEmaSf,
  };

  // Deploy MultiCollateralUpgradeChanger using the wrapper as the price provider and peggedTokenParams
  const multiCollateralUpgradeChanger = m.contract(
    "MultiCollateralUpgradeChanger",
    [
      params.rifBucketAddress, // rifBucket_
      mocRifImplementation, // mocRifImplementation_
      usdRifImplementation, // usdRifNewImplementation_
      mocCoreExpansion, // mocMocCoreExpansionImplementation_
      mocQueueProxy, // newMocQueueRifProxy_
      rifPriceProvider, // newPriceProvider_
      params.blockSpan, // blockSpan_
      params.docBucketAddress!, // docBucket_
      rifBucketParamsStruct, // rifBucketParams_
      docBucketParamsStruct, // docBucketParams_
      params.rifToDocSwapperAddress!, // rifDocMocSwapper_
      params.rifNewProtectedThrld, // rifNewProtectedThrld_
      peggedTokenParamsStruct, // peggedTokenParams_
      params.governedRegistryAddress, // governedRegistry_
      params.reverseAuctionDOCtoMOCAddress!, // reverseAuctionDOCtoMOC_
      params.reverseAuctionMOCtoDOCAddress!, // reverseAuctionMOCtoDOC_
      params.rocrRewardsBufferAddress!, // rocrRewardsBuffer_
    ],
    { id: `${prefix}MultiCollateralUpgradeChanger` },
  );

  return {
    mocMultiCollateralGuardImpl,
    mocMultiCollateralGuardProxy,
    mocQueueImpl,
    mocQueueProxy,
    mocRifImplementation,
    usdRifImplementation,
    mocCoreExpansion,
    multiCollateralUpgradeChanger,
  };
}
