import type { IgnitionModuleBuilder, ModuleParameterRuntimeValue } from "@nomicfoundation/ignition-core";
import { getPrefixedParameterName } from "./parameterPrefixes";

// Type aliases for parameters that can be either literal values or runtime values
type StringParam = string | ModuleParameterRuntimeValue<string>;
type BigintParam = bigint | ModuleParameterRuntimeValue<bigint>;
type StringArrayParam = string[] | ModuleParameterRuntimeValue<string[]>;
type BigintArrayParam = bigint[] | ModuleParameterRuntimeValue<bigint[]>;

/**
 * Parameters for deploying MocSwappers
 * Can be either literal values or ModuleParameterRuntimeValues from m.getParameter()
 */
export interface MocSwappersParams {
  governorAddress: StringParam;
  pauserAddress: StringParam;
  swapRouterAddress: StringParam;
  coinbaseWrapperAddress: StringParam;
  docTokenAddress: StringParam;
  mocTokenAddress: StringParam;
  rifTokenAddress: StringParam;
  docToMocPath: StringArrayParam;
  docToMocFees: BigintArrayParam;
  maxDocToMocToSwap: BigintParam;
  mocToDocPath: StringArrayParam;
  mocToDocFees: BigintArrayParam;
  maxMocToDocToSwap: BigintParam;
  rifToDocPath: StringArrayParam;
  rifToDocFees: BigintArrayParam;
  maxRifToDocToSwap: BigintParam;
  docToRifPath: StringArrayParam;
  docToRifFees: BigintArrayParam;
  maxDocToRifToSwap: BigintParam;
}

/**
 * Helper to get MocSwappers parameters from module parameters
 * @param m - The IgnitionModuleBuilder
 * @param parameterPrefix - Optional prefix for namespaced parameters (e.g., "MocSwappers" for Full module)
 */
export function getMocSwappersParams(m: IgnitionModuleBuilder, parameterPrefix?: string): MocSwappersParams {
  const getParameter = <T extends string | bigint | boolean | string[] | bigint[]>(parameterName: string) =>
    m.getParameter<T>(getPrefixedParameterName(parameterName, parameterPrefix));

  return {
    governorAddress: getParameter<string>("governorAddress"),
    pauserAddress: getParameter<string>("pauserAddress"),
    swapRouterAddress: getParameter<string>("swapRouterAddress"),
    coinbaseWrapperAddress: getParameter<string>("coinbaseWrapperAddress"),
    docTokenAddress: getParameter<string>("docTokenAddress"),
    mocTokenAddress: getParameter<string>("mocTokenAddress"),
    rifTokenAddress: getParameter<string>("rifTokenAddress"),
    docToMocPath: getParameter<string[]>("docToMocPath"),
    docToMocFees: getParameter<bigint[]>("docToMocFees"),
    maxDocToMocToSwap: getParameter<bigint>("maxDocToMocToSwap"),
    mocToDocPath: getParameter<string[]>("mocToDocPath"),
    mocToDocFees: getParameter<bigint[]>("mocToDocFees"),
    maxMocToDocToSwap: getParameter<bigint>("maxMocToDocToSwap"),
    rifToDocPath: getParameter<string[]>("rifToDocPath"),
    rifToDocFees: getParameter<bigint[]>("rifToDocFees"),
    maxRifToDocToSwap: getParameter<bigint>("maxRifToDocToSwap"),
    docToRifPath: getParameter<string[]>("docToRifPath"),
    docToRifFees: getParameter<bigint[]>("docToRifFees"),
    maxDocToRifToSwap: getParameter<bigint>("maxDocToRifToSwap"),
  };
}

/**
 * Deploy MocSwappers with the given parameters
 * This function can be called from the standalone module or from FullMultiCollateralUpgrade
 */
export function deployMocSwappers(m: IgnitionModuleBuilder, params: MocSwappersParams, idPrefix: string = "") {
  const prefix = idPrefix ? `${idPrefix}_` : "";

  // Deploy InterimGovernor
  const interimGovernor = m.contract("InterimGovernor", [], {
    id: `${prefix}InterimGovernor`,
  });

  // Deploy one shared MocSwapperV3MultiHop for all pairs
  const mocSwapperV3MultihopImpl = m.contract("MocSwapperV3MultiHop", [], {
    id: `${prefix}MocSwapperV3MultihopImplementation`,
  });

  const mocSwapperV3MultihopInitData = m.encodeFunctionCall(mocSwapperV3MultihopImpl, "initialize", [
    interimGovernor,
    params.pauserAddress,
    params.swapRouterAddress,
    params.coinbaseWrapperAddress,
  ]);

  const mocSwapperV3MultihopProxy = m.contract(
    "ERC1967Proxy",
    [mocSwapperV3MultihopImpl, mocSwapperV3MultihopInitData],
    {
      id: `${prefix}MocSwapperV3MultihopProxy`,
    },
  );

  const mocSwapperV3Multihop = m.contractAt("MocSwapperV3MultiHop", mocSwapperV3MultihopProxy, {
    id: `${prefix}MocSwapperV3Multihop`,
  });

  // Deploy DataProvider instances for max amount to swap (owner = pauserAddress)
  const docToMocMaxAmountProvider = m.contract("DataProvider", [params.pauserAddress, params.maxDocToMocToSwap], {
    id: `${prefix}DocToMocMaxAmountProvider`,
  });

  const mocToDocMaxAmountProvider = m.contract("DataProvider", [params.pauserAddress, params.maxMocToDocToSwap], {
    id: `${prefix}MocToDocMaxAmountProvider`,
  });

  const rifToDocMaxAmountProvider = m.contract("DataProvider", [params.pauserAddress, params.maxRifToDocToSwap], {
    id: `${prefix}RifToDocMaxAmountProvider`,
  });

  const docToRifMaxAmountProvider = m.contract("DataProvider", [params.pauserAddress, params.maxDocToRifToSwap], {
    id: `${prefix}DocToRifMaxAmountProvider`,
  });

  // Configure swapper paths
  m.call(
    mocSwapperV3Multihop,
    "setPath",
    [
      params.docTokenAddress,
      params.mocTokenAddress,
      params.docToMocPath,
      params.docToMocFees,
      docToMocMaxAmountProvider,
    ],
    { id: `${prefix}SetPathDOCtoMOC` },
  );

  m.call(
    mocSwapperV3Multihop,
    "setPath",
    [
      params.mocTokenAddress,
      params.docTokenAddress,
      params.mocToDocPath,
      params.mocToDocFees,
      mocToDocMaxAmountProvider,
    ],
    { id: `${prefix}SetPathMOCtoDOC` },
  );

  m.call(
    mocSwapperV3Multihop,
    "setPath",
    [
      params.rifTokenAddress,
      params.docTokenAddress,
      params.rifToDocPath,
      params.rifToDocFees,
      rifToDocMaxAmountProvider,
    ],
    { id: `${prefix}SetPathRIFtoDOC` },
  );

  m.call(
    mocSwapperV3Multihop,
    "setPath",
    [
      params.docTokenAddress,
      params.rifTokenAddress,
      params.docToRifPath,
      params.docToRifFees,
      docToRifMaxAmountProvider,
    ],
    { id: `${prefix}SetPathDOCtoRIF` },
  );

  // Transfer governance to real governor
  m.call(mocSwapperV3Multihop, "changeGovernor", [params.governorAddress], {
    id: `${prefix}TransferGovernanceMocSwapperV3Multihop`,
  });

  return {
    interimGovernor,
    mocSwapperV3MultihopImpl,
    mocSwapperV3MultihopProxy,
    mocSwapperV3Multihop,
    docToMocMaxAmountProvider,
    mocToDocMaxAmountProvider,
    rifToDocMaxAmountProvider,
    docToRifMaxAmountProvider,
  };
}
