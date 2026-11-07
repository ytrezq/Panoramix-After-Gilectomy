import type {
  IgnitionModuleBuilder,
  ContractFuture,
  ModuleParameterRuntimeValue,
} from "@nomicfoundation/ignition-core";
import { getPrefixedParameterName } from "./parameterPrefixes";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

// Type aliases for parameters
type StringParam = string | ModuleParameterRuntimeValue<string>;
type BigintParam = bigint | ModuleParameterRuntimeValue<bigint>;
type BooleanParam = boolean | ModuleParameterRuntimeValue<boolean>;
// AddressOrFuture can be: a literal string, a ContractFuture from another deployment, or a ModuleParameterRuntimeValue
type AddressOrFuture = string | ContractFuture<string> | ModuleParameterRuntimeValue<string>;

/**
 * Parameters for deploying DocBucket
 * Fee-flow addresses can be either literal strings or ContractFutures from FeeFlow deployment
 */
export interface DocBucketParams {
  governorAddress: StringParam;
  pauserAddress: StringParam;
  docTokenAddress: StringParam;
  feeTokenAddress: StringParam;
  feeTokenPriceProviderAddress: StringParam;
  mocVendorsAddress: StringParam;
  // These can be ContractFutures from FeeFlow deployment
  feesSplitterAddress: AddressOrFuture;
  tcInterestCollectorAddress: AddressOrFuture;
  // Coverage thresholds
  protThrld: BigintParam;
  liqThrld: BigintParam;
  // Fee parameters
  tcMintFee: BigintParam;
  tcRedeemFee: BigintParam;
  swapTPforTPFee: BigintParam;
  swapTPforTCFee: BigintParam;
  swapTCforTPFee: BigintParam;
  redeemTCandTPFee: BigintParam;
  mintTCandTPFee: BigintParam;
  feeTokenPct: BigintParam;
  feeRetainer: BigintParam;
  // Settlement parameters
  successFee: BigintParam;
  appreciationFactor: BigintParam;
  settlementTimeSpan: BigintParam;
  // TC Interest parameters
  tcInterestRate: BigintParam;
  tcInterestPaymentTimeSpan: BigintParam;
  // Operational parameters
  decayTimeSpan: BigintParam;
  emaCalculationTimeSpan: BigintParam;
  maxAbsoluteOpProviderAddress: StringParam;
  maxOpDiffProviderAddress: StringParam;
  allowDifferentRecipient: BooleanParam;
  // Queue parameters
  minOperWaitingBlk: BigintParam;
  maxOperWaitingBlk: BigintParam;
  tcMintExecCost: BigintParam;
  tcRedeemExecCost: BigintParam;
  tpMintExecCost: BigintParam;
  tpRedeemExecCost: BigintParam;
  mintTCandTPExecCost: BigintParam;
  redeemTCandTPExecCost: BigintParam;
  swapTPforTPExecCost: BigintParam;
  swapTPforTCExecCost: BigintParam;
  swapTCforTPExecCost: BigintParam;
  // Token parameters
  tcTokenName: StringParam;
  tcTokenSymbol: StringParam;
}

/**
 * Partial params for DocBucket - fee-flow addresses provided separately (from another deployment)
 */
export type DocBucketParamsWithoutSplitters = Omit<
  DocBucketParams,
  "feesSplitterAddress" | "tcInterestCollectorAddress"
>;

/**
 * Helper to get DocBucket parameters from module parameters (excluding fee-flow addresses)
 * @param m - The IgnitionModuleBuilder
 * @param parameterPrefix - Optional prefix for namespaced parameters (e.g., "DocBucket" for Full module)
 */
export function getDocBucketParams(
  m: IgnitionModuleBuilder,
  parameterPrefix?: string,
): DocBucketParamsWithoutSplitters {
  const getParameter = <T extends string | bigint | boolean | string[] | bigint[]>(parameterName: string) =>
    m.getParameter<T>(getPrefixedParameterName(parameterName, parameterPrefix));

  return {
    governorAddress: getParameter<string>("governorAddress"),
    pauserAddress: getParameter<string>("pauserAddress"),
    docTokenAddress: getParameter<string>("docTokenAddress"),
    feeTokenAddress: getParameter<string>("feeTokenAddress"),
    feeTokenPriceProviderAddress: getParameter<string>("feeTokenPriceProviderAddress"),
    mocVendorsAddress: getParameter<string>("mocVendorsAddress"),
    protThrld: getParameter<bigint>("protThrld"),
    liqThrld: getParameter<bigint>("liqThrld"),
    tcMintFee: getParameter<bigint>("tcMintFee"),
    tcRedeemFee: getParameter<bigint>("tcRedeemFee"),
    swapTPforTPFee: getParameter<bigint>("swapTPforTPFee"),
    swapTPforTCFee: getParameter<bigint>("swapTPforTCFee"),
    swapTCforTPFee: getParameter<bigint>("swapTCforTPFee"),
    redeemTCandTPFee: getParameter<bigint>("redeemTCandTPFee"),
    mintTCandTPFee: getParameter<bigint>("mintTCandTPFee"),
    feeTokenPct: getParameter<bigint>("feeTokenPct"),
    feeRetainer: getParameter<bigint>("feeRetainer"),
    successFee: getParameter<bigint>("successFee"),
    appreciationFactor: getParameter<bigint>("appreciationFactor"),
    settlementTimeSpan: getParameter<bigint>("settlementTimeSpan"),
    tcInterestRate: getParameter<bigint>("tcInterestRate"),
    tcInterestPaymentTimeSpan: getParameter<bigint>("tcInterestPaymentTimeSpan"),
    decayTimeSpan: getParameter<bigint>("decayTimeSpan"),
    emaCalculationTimeSpan: getParameter<bigint>("emaCalculationTimeSpan"),
    maxAbsoluteOpProviderAddress: getParameter<string>("maxAbsoluteOpProviderAddress"),
    maxOpDiffProviderAddress: getParameter<string>("maxOpDiffProviderAddress"),
    allowDifferentRecipient: getParameter<boolean>("allowDifferentRecipient"),
    minOperWaitingBlk: getParameter<bigint>("minOperWaitingBlk"),
    maxOperWaitingBlk: getParameter<bigint>("maxOperWaitingBlk"),
    tcMintExecCost: getParameter<bigint>("tcMintExecCost"),
    tcRedeemExecCost: getParameter<bigint>("tcRedeemExecCost"),
    tpMintExecCost: getParameter<bigint>("tpMintExecCost"),
    tpRedeemExecCost: getParameter<bigint>("tpRedeemExecCost"),
    mintTCandTPExecCost: getParameter<bigint>("mintTCandTPExecCost"),
    redeemTCandTPExecCost: getParameter<bigint>("redeemTCandTPExecCost"),
    swapTPforTPExecCost: getParameter<bigint>("swapTPforTPExecCost"),
    swapTPforTCExecCost: getParameter<bigint>("swapTPforTCExecCost"),
    swapTCforTPExecCost: getParameter<bigint>("swapTCforTPExecCost"),
    tcTokenName: getParameter<string>("tcTokenName"),
    tcTokenSymbol: getParameter<string>("tcTokenSymbol"),
  };
}

/**
 * Deploy DocBucket with the given parameters
 * This function can be called from the standalone module or from FullMultiCollateralUpgrade
 */
export function deployDocBucket(m: IgnitionModuleBuilder, params: DocBucketParams, idPrefix: string = "") {
  const prefix = idPrefix ? `${idPrefix}_` : "";
  const deployer = m.getAccount(0);

  // Deploy MocTC
  const mocTCImpl = m.contract("moc-main-latest/contracts/tokens/MocRC20.sol:MocRC20", [], {
    id: `${prefix}DocBucketTCImplementation`,
  });

  const tcInitData = m.encodeFunctionCall(mocTCImpl, "initialize", [
    params.tcTokenName,
    params.tcTokenSymbol,
    deployer,
    params.governorAddress,
  ]);

  const mocTCProxy = m.contract("ERC1967Proxy", [mocTCImpl, tcInitData], {
    id: `${prefix}DocBucketTCProxy`,
  });

  // Deploy MocCoreExpansion
  const mocCoreExpansion = m.contract("MocCoreExpansion", [], {
    id: `${prefix}DocBucketCoreExpansion`,
  });

  // Deploy MocQueue
  const mocQueueImpl = m.contract("MocQueue", [], { id: `${prefix}DocBucketQueueImplementation` });

  const execCostParams = {
    tcMintExecCost: params.tcMintExecCost,
    tcRedeemExecCost: params.tcRedeemExecCost,
    tpMintExecCost: params.tpMintExecCost,
    tpRedeemExecCost: params.tpRedeemExecCost,
    mintTCandTPExecCost: params.mintTCandTPExecCost,
    redeemTCandTPExecCost: params.redeemTCandTPExecCost,
    swapTPforTPExecCost: params.swapTPforTPExecCost,
    swapTPforTCExecCost: params.swapTPforTCExecCost,
    swapTCforTPExecCost: params.swapTCforTPExecCost,
  };

  const queueInitData = m.encodeFunctionCall(mocQueueImpl, "initialize", [
    params.governorAddress,
    params.pauserAddress,
    ZERO_ADDRESS, // mocMultiCollateralGuard - set via changer
    params.minOperWaitingBlk,
    params.maxOperWaitingBlk,
    execCostParams,
  ]);

  const mocQueueProxy = m.contract("ERC1967Proxy", [mocQueueImpl, queueInitData], {
    id: `${prefix}DocBucketQueueProxy`,
  });

  // Deploy MocCARC20 (DOC Bucket)
  const mocCARC20Impl = m.contract("moc-main-latest/contracts/collateral/rc20/MocCARC20.sol:MocCARC20", [], {
    id: `${prefix}DocBucketImplementation`,
  });

  const operationsFeeParams = {
    tcMintFee: params.tcMintFee,
    tcRedeemFee: params.tcRedeemFee,
    swapTPforTPFee: params.swapTPforTPFee,
    swapTPforTCFee: params.swapTPforTCFee,
    swapTCforTPFee: params.swapTCforTPFee,
    redeemTCandTPFee: params.redeemTCandTPFee,
    mintTCandTPFee: params.mintTCandTPFee,
    feeTokenPct: params.feeTokenPct,
    feeRetainer: params.feeRetainer,
  };

  const initializeBaseBucketParams = {
    mocQueueAddress: mocQueueProxy,
    feeTokenAddress: params.feeTokenAddress,
    feeTokenPriceProviderAddress: params.feeTokenPriceProviderAddress,
    tcTokenAddress: mocTCProxy,
    mocFeeFlowAddress: params.feesSplitterAddress,
    mocAppreciationBeneficiaryAddress: params.governorAddress,
    protThrld: params.protThrld,
    liqThrld: params.liqThrld,
    operationsFeeParams,
    successFee: params.successFee,
    appreciationFactor: params.appreciationFactor,
    settlementTimeSpan: params.settlementTimeSpan,
    tcInterestCollectorAddress: params.tcInterestCollectorAddress,
    tcInterestRate: params.tcInterestRate,
    tcInterestPaymentTimeSpan: params.tcInterestPaymentTimeSpan,
    maxAbsoluteOpProviderAddress: params.maxAbsoluteOpProviderAddress,
    maxOpDiffProviderAddress: params.maxOpDiffProviderAddress,
    decayTimeSpan: params.decayTimeSpan,
    allowDifferentRecipient: params.allowDifferentRecipient,
  };

  const initializeCoreParams = {
    initializeBaseBucketParams,
    governorAddress: params.governorAddress,
    pauserAddress: params.pauserAddress,
    mocCoreExpansion,
    emaCalculationTimeSpan: params.emaCalculationTimeSpan,
    mocVendors: params.mocVendorsAddress,
  };

  const initializeParams = {
    initializeCoreParams,
    acTokenAddress: params.docTokenAddress,
  };

  const bucketInitData = m.encodeFunctionCall(mocCARC20Impl, "initialize", [initializeParams]);

  const docBucketProxy = m.contract("ERC1967Proxy", [mocCARC20Impl, bucketInitData], {
    id: `${prefix}DocBucketProxy`,
  });

  // Get MocRC20 interface for the TC proxy to call transferAllRoles
  const mocTC = m.contractAt("moc-main-latest/contracts/tokens/MocRC20.sol:MocRC20", mocTCProxy, {
    id: `${prefix}MocTCInterface`,
  });

  // Transfer TC roles to bucket
  m.call(mocTC, "transferAllRoles", [docBucketProxy], {
    id: `${prefix}TransferTCRolesToDocBucket`,
    from: deployer,
  });

  return {
    mocCARC20Impl,
    mocTCImpl,
    mocQueueImpl,
    mocCoreExpansion,
    docBucketProxy,
    mocTCProxy,
    mocQueueProxy,
  };
}
