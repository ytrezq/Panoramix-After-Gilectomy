import type {
  IgnitionModuleBuilder,
  ContractFuture,
  ModuleParameterRuntimeValue,
} from "@nomicfoundation/ignition-core";
import { getPrefixedParameterName } from "./parameterPrefixes";

// Type aliases for parameters
type StringParam = string | ModuleParameterRuntimeValue<string>;
type BigintParam = bigint | ModuleParameterRuntimeValue<bigint>;
// AddressOrFuture can be: a literal string, a ContractFuture from another deployment, or a ModuleParameterRuntimeValue
type AddressOrFuture = string | ContractFuture<string> | ModuleParameterRuntimeValue<string>;

/**
 * Parameters for deploying FeeFlow
 * Swapper addresses can be either literal strings or ContractFutures from MocSwappers deployment
 */
export interface FeeFlowParams {
  governorAddress: StringParam;
  docTokenAddress: StringParam;
  mocTokenAddress: StringParam;
  // These can be ContractFutures from MocSwappers deployment
  mocSwapperV3Multihop: AddressOrFuture;
  mocRewardsBuffer: StringParam;
  // Splitter parameters
  foundationTreasury: StringParam;
  feesSplitterAcTokenPct1: BigintParam;
  feesSplitterFeeTokenPct1: BigintParam;
  mocRewardsSplitterThreshold: BigintParam;
  mocRewardsSplitterSplits: bigint[] | ModuleParameterRuntimeValue<bigint[]>;
  mocRewardsSplitterThresholds: bigint[] | ModuleParameterRuntimeValue<bigint[]>;
  // ReverseAuction parameters
  docToMocOrderThreshold: BigintParam;
  docToMocSlippage: BigintParam;
  mocToDocOrderThreshold: BigintParam;
  mocToDocSlippage: BigintParam;
  mocToDocPriceProvider: StringParam;
}

/**
 * Partial params for FeeFlow - swapper addresses provided separately (from another deployment)
 */
export type FeeFlowParamsWithoutSwappers = Omit<FeeFlowParams, "mocSwapperV3Multihop">;

/**
 * Helper to get FeeFlow parameters from module parameters (excluding swapper addresses)
 * @param m - The IgnitionModuleBuilder
 * @param parameterPrefix - Optional prefix for namespaced parameters (e.g., "FeeFlow" for Full module)
 */
export function getFeeFlowParams(m: IgnitionModuleBuilder, parameterPrefix?: string): FeeFlowParamsWithoutSwappers {
  const getParameter = <T extends string | bigint | boolean | string[] | bigint[]>(parameterName: string) =>
    m.getParameter<T>(getPrefixedParameterName(parameterName, parameterPrefix));

  return {
    governorAddress: getParameter<string>("governorAddress"),
    docTokenAddress: getParameter<string>("docTokenAddress"),
    mocTokenAddress: getParameter<string>("mocTokenAddress"),
    mocRewardsBuffer: getParameter<string>("mocRewardsBuffer"),
    foundationTreasury: getParameter<string>("foundationTreasury"),
    feesSplitterAcTokenPct1: getParameter<bigint>("feesSplitterAcTokenPct1"),
    feesSplitterFeeTokenPct1: getParameter<bigint>("feesSplitterFeeTokenPct1"),
    mocRewardsSplitterThreshold: getParameter<bigint>("mocRewardsSplitterThreshold"),
    mocRewardsSplitterSplits: getParameter<bigint[]>("mocRewardsSplitterSplits"),
    mocRewardsSplitterThresholds: getParameter<bigint[]>("mocRewardsSplitterThresholds"),
    docToMocOrderThreshold: getParameter<bigint>("docToMocOrderThreshold"),
    docToMocSlippage: getParameter<bigint>("docToMocSlippage"),
    mocToDocOrderThreshold: getParameter<bigint>("mocToDocOrderThreshold"),
    mocToDocSlippage: getParameter<bigint>("mocToDocSlippage"),
    mocToDocPriceProvider: getParameter<string>("mocToDocPriceProvider"),
  };
}

/**
 * Deploy FeeFlow infrastructure with the given parameters
 * This function can be called from the standalone module or from FullMultiCollateralUpgrade
 */
export function deployFeeFlow(m: IgnitionModuleBuilder, params: FeeFlowParams, idPrefix: string = "") {
  const prefix = idPrefix ? `${idPrefix}_` : "";

  // Deploy for DOC/MOC price provider for DOC -> MOC reverse auction
  const docToMocPriceProvider = m.contract("PriceProviderInverse", [params.mocToDocPriceProvider], {
    id: `${prefix}DocToMocPriceProvider`,
  });

  // Deploy MOC -> DOC ReverseAuction with temporary output account.
  // The final output account (DocBucket) is set in MultiCollateralUpgradeChanger.execute().
  const reverseAuctionMOCtoDOC = m.contract(
    "MocReverseAuction",
    [
      params.governorAddress,
      params.mocSwapperV3Multihop,
      params.mocTokenAddress,
      params.docTokenAddress,
      params.mocRewardsBuffer, // placeholder output account, will be updated to DocBucket in MultiCollateralUpgradeChanger
      params.mocToDocOrderThreshold,
      params.mocToDocPriceProvider,
      params.mocToDocSlippage,
    ],
    { id: `${prefix}ReverseAuctionMOCtoDOC` },
  );

  // Deploy MOC BufferToken behind proxy and initialize in constructor data.
  const rocrRewardsBufferImpl = m.contract("BufferToken", [], {
    id: `${prefix}RocrRewardsBufferImplementation`,
  });

  const rocrRewardsBufferInitData = m.encodeFunctionCall(rocrRewardsBufferImpl, "initialize", [
    params.governorAddress,
    params.mocTokenAddress,
    params.mocRewardsSplitterThreshold,
    [params.mocRewardsBuffer, reverseAuctionMOCtoDOC],
    params.mocRewardsSplitterSplits,
    params.mocRewardsSplitterThresholds,
  ]);

  const rocrRewardsBuffer = m.contract("ERC1967Proxy", [rocrRewardsBufferImpl, rocrRewardsBufferInitData], {
    id: `${prefix}RocrRewardsBuffer`,
  });

  // Deploy DOC -> MOC ReverseAuction (splitters need its address)
  const reverseAuctionDOCtoMOC = m.contract(
    "MocReverseAuction",
    [
      params.governorAddress,
      params.mocSwapperV3Multihop,
      params.docTokenAddress,
      params.mocTokenAddress,
      params.mocRewardsBuffer,
      params.docToMocOrderThreshold,
      docToMocPriceProvider,
      params.docToMocSlippage,
    ],
    { id: `${prefix}ReverseAuctionDOCtoMOC` },
  );

  // Deploy CommissionSplitterRC20 for FeesSplitter
  const feesSplitterImpl = m.contract("CommissionSplitterRC20", [], {
    id: `${prefix}FeesSplitterImplementation`,
  });

  const feesSplitterInitData = m.encodeFunctionCall(feesSplitterImpl, "initialize", [
    params.docTokenAddress, // acToken (DOC)
    params.governorAddress,
    params.mocTokenAddress, // feeToken (MOC)
    params.foundationTreasury, // acTokenAddressRecipient1_ (foundation)
    reverseAuctionDOCtoMOC, // acTokenAddressRecipient2_ (DOC -> MOC auction)
    params.feesSplitterAcTokenPct1, // acTokenPctToRecipient1_
    params.foundationTreasury, // feeTokenAddressRecipient1_ (foundation)
    rocrRewardsBuffer, // feeTokenAddressRecipient2_ (MOC rewards buffer)
    params.feesSplitterFeeTokenPct1, // feeTokenPctToRecipient1_
  ]);

  const feesSplitterProxy = m.contract("ERC1967Proxy", [feesSplitterImpl, feesSplitterInitData], {
    id: `${prefix}FeesSplitterProxy`,
  });

  return {
    feesSplitterImpl,
    feesSplitterProxy,
    reverseAuctionDOCtoMOC,
    reverseAuctionMOCtoDOC,
    rocrRewardsBuffer,
  };
}
