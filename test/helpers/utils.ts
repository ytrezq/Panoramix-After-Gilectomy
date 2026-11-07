import hre, { ethers, getNamedAccounts, network } from "hardhat";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ContractTransactionResponse, BigNumberish, Signer, AbiCoder, keccak256, getBigInt } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import {
  ERC20Mock,
  MocRC20,
  MocRC20__factory,
  ERC777Mock,
  PriceProviderMock,
  DataProviderMock,
  MocQueue,
  MocQueue__factory,
  MocCARC20__factory,
  MocCARC20,
  MocCACoinbase,
  MocRC20Decimals,
  MocRC20Decimals__factory,
  CommissionSplitterRC20__factory,
  CommissionSplitterCoinbase__factory,
  CommissionSplitterRC20,
  CommissionSplitterCoinbase,
} from "../../typechain";
import { IGovernor } from "../../typechain/contracts/interfaces/IGovernor";
import { IGovernor__factory } from "../../typechain/factories/contracts/interfaces/IGovernor__factory";
import GovernorCompiled from "../governance/aeropagusImports/Governor.json";
import { BURNER_ROLE, CONSTANTS, DEFAULT_ADMIN_ROLE, MINTER_ROLE } from "../../scripts/utils";
import { MoCRC20Contracts } from "../rc20/fixture";
import { MoCCoinbaseContracts } from "../coinbase/fixture";
import { getNetworkDeployParams, getGovernorAddresses } from "./utils";

export * from "@nomicfoundation/hardhat-network-helpers";
export * from "../../scripts/utils";

export const GAS_LIMIT_PATCH = 30000000;
const PCT_BASE = BigInt(1e18);

export enum OperType {
  none, // avoid using zero as Type
  mintTC,
  redeemTC,
  mintTP,
  redeemTP,
  mintTCandTP,
  redeemTCandTP,
  swapTCforTP,
  swapTPforTC,
  swapTPforTP,
}

export function pEth(eth: string | number): bigint {
  let ethStr: string;
  if (typeof eth === "number") ethStr = eth.toLocaleString("fullwide", { useGrouping: false }).replace(",", ".");
  else ethStr = eth;
  return ethers.parseEther(ethStr);
}

export async function resetFork(jsonRpcUrl?: string, blockNumber?: number): Promise<void> {
  const params =
    jsonRpcUrl === undefined
      ? []
      : [
          {
            forking: {
              jsonRpcUrl,
              ...(blockNumber === undefined ? {} : { blockNumber }),
            },
          },
        ];

  await network.provider.request({
    method: "hardhat_reset",
    params,
  });
}

const { coreParams, feeParams, settlementParams, mocAddresses, queueParams } = getNetworkDeployParams(hre);

export function mocInitialize(
  mocCore: any, // MocCARC20 | MocCACoinbase,
  mocTC: Address,
  mocCoreExpansion: Address,
  mocVendors: Address,
  mocQueue: Address,
  extraArgs: { acTokenAddress?: Address; transferMaxGas?: BigNumberish },
) {
  return ({
    mocGovernorAddress = mocAddresses.governorAddress,
    mocPauserAddress = mocAddresses.pauserAddress,
    feeTokenAddress = mocAddresses.feeTokenAddress,
    feeTokenPriceProviderAddress = mocAddresses.feeTokenPriceProviderAddress,
    mocTCAddress = mocTC,
    mocCoreExpansionAddress = mocCoreExpansion,
    feeFlowAddress = mocAddresses.mocFeeFlowAddress,
    mocAppreciationBeneficiaryAddress = mocAddresses.mocAppreciationBeneficiaryAddress,
    mocVendorsAddress = mocVendors,
    mocQueueAddress = mocQueue,
    protThrld = coreParams.protThrld,
    liqThrld = coreParams.liqThrld,
    feeRetainer = feeParams.feeRetainer,
    tcMintFee = feeParams.tcMintFee,
    tcRedeemFee = feeParams.tcRedeemFee,
    swapTPforTPFee = feeParams.swapTPforTPFee,
    swapTPforTCFee = feeParams.swapTPforTCFee,
    swapTCforTPFee = feeParams.swapTCforTPFee,
    redeemTCandTPFee = feeParams.redeemTCandTPFee,
    mintTCandTPFee = feeParams.mintTCandTPFee,
    feeTokenPct = feeParams.feeTokenPct,
    emaCalculationTimeSpan = coreParams.emaCalculationTimeSpan,
    settlementTimeSpan = settlementParams.settlementTimeSpan,
    successFee = coreParams.successFee,
    appreciationFactor = coreParams.appreciationFactor,
    tcInterestCollectorAddress = mocAddresses.tcInterestCollectorAddress,
    tcInterestRate = coreParams.tcInterestRate,
    tcInterestPaymentTimeSpan = coreParams.tcInterestPaymentTimeSpan,
    maxAbsoluteOpProviderAddress = mocAddresses.maxAbsoluteOpProviderAddress,
    maxOpDiffProviderAddress = mocAddresses.maxOpDiffProviderAddress,
    decayTimeSpan = coreParams.decayTimeSpan,
    allowDifferentRecipient = coreParams.allowDifferentRecipient,
  }: {
    mocGovernorAddress?: Address;
    mocPauserAddress?: Address;
    feeTokenAddress?: Address;
    feeTokenPriceProviderAddress?: Address;
    mocTCAddress?: Address;
    mocCoreExpansionAddress?: Address;
    feeFlowAddress?: Address;
    mocAppreciationBeneficiaryAddress?: Address;
    mocVendorsAddress?: Address;
    mocQueueAddress?: Address;
    protThrld?: BigNumberish;
    liqThrld?: BigNumberish;
    feeRetainer?: BigNumberish;
    tcMintFee?: BigNumberish;
    tcRedeemFee?: BigNumberish;
    swapTPforTPFee?: BigNumberish;
    swapTPforTCFee?: BigNumberish;
    swapTCforTPFee?: BigNumberish;
    redeemTCandTPFee?: BigNumberish;
    mintTCandTPFee?: BigNumberish;
    feeTokenPct?: BigNumberish;
    emaCalculationTimeSpan?: BigNumberish;
    settlementTimeSpan?: BigNumberish;
    successFee?: BigNumberish;
    appreciationFactor?: BigNumberish;
    tcInterestCollectorAddress?: Address;
    tcInterestRate?: BigNumberish;
    tcInterestPaymentTimeSpan?: BigNumberish;
    maxAbsoluteOpProviderAddress?: Address;
    maxOpDiffProviderAddress?: Address;
    decayTimeSpan?: BigNumberish;
    allowDifferentRecipient?: Boolean;
  } = {}) => {
    return mocCore.initialize({
      initializeCoreParams: {
        initializeBaseBucketParams: {
          mocQueueAddress,
          feeTokenAddress,
          feeTokenPriceProviderAddress,
          tcTokenAddress: mocTCAddress,
          mocFeeFlowAddress: feeFlowAddress,
          mocAppreciationBeneficiaryAddress,
          protThrld,
          liqThrld,
          operationsFeeParams: {
            feeRetainer,
            tcMintFee,
            tcRedeemFee,
            swapTPforTPFee,
            swapTPforTCFee,
            swapTCforTPFee,
            redeemTCandTPFee,
            mintTCandTPFee,
            feeTokenPct,
          },
          successFee,
          appreciationFactor,
          settlementTimeSpan,
          tcInterestCollectorAddress,
          tcInterestRate,
          tcInterestPaymentTimeSpan,
          maxAbsoluteOpProviderAddress,
          maxOpDiffProviderAddress,
          decayTimeSpan,
          allowDifferentRecipient,
        },
        governorAddress: mocGovernorAddress,
        pauserAddress: mocPauserAddress,
        mocCoreExpansion: mocCoreExpansionAddress,
        emaCalculationTimeSpan,
        mocVendors: mocVendorsAddress,
      },
      ...extraArgs,
    });
  };
}

export async function deployPeggedToken({
  adminAddress,
  governorAddress,
}: {
  adminAddress: Address;
  governorAddress: Address;
}): Promise<MocRC20> {
  const factory = await ethers.getContractFactory("MocRC20");
  const mocRC20Impl = await factory.deploy();
  const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
  const erc1967Proxy = await erc1967ProxyFactory.deploy(mocRC20Impl.target, "0x");
  let deployer;
  ({ deployer } = await getNamedAccounts());
  const signer = await ethers.getSigner(deployer);

  const mocRC20Proxy = MocRC20__factory.connect(await erc1967Proxy.getAddress(), signer);
  await mocRC20Proxy.initialize("PeggedToken", "PeggedToken", adminAddress, governorAddress);
  return mocRC20Proxy;
}

export async function deployAndInitTC({
  adminAddress,
  governorAddress,
  decimals,
}: {
  adminAddress: Address;
  governorAddress: Address;
  decimals?: bigint;
}): Promise<MocRC20> {
  const mocTCFactory = await ethers.getContractFactory(decimals ? "MocRC20Decimals" : "MocRC20");
  const newMocTCImpl = await mocTCFactory.deploy();
  const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
  const erc1967Proxy = await erc1967ProxyFactory.deploy(newMocTCImpl.target, "0x");
  let deployer;
  ({ deployer } = await getNamedAccounts());
  const signer = await ethers.getSigner(deployer);

  const mocTCProxy = decimals
    ? MocRC20Decimals__factory.connect(erc1967Proxy.target.toString(), signer)
    : MocRC20__factory.connect(erc1967Proxy.target.toString(), signer);

  if (decimals) {
    await (mocTCProxy as MocRC20Decimals)["initialize(string,string,uint8,address,address)"](
      "mocCT",
      "CT",
      decimals,
      adminAddress,
      governorAddress,
    );
  } else {
    await (mocTCProxy as MocRC20).initialize("mocCT", "CT", adminAddress, governorAddress);
  }
  return mocTCProxy as MocRC20;
}

export const deployMocQueue = async ({
  contractName,
  mocMultiCollateralGuardAddress,
  pauser,
}: {
  contractName: "MocQueueMock" | "MocQueue" | "MocQueueBasefeeMock";
  mocMultiCollateralGuardAddress: Address;
  pauser?: Address;
}): Promise<MocQueue> => {
  const mocQueueFactory = await ethers.getContractFactory(contractName);
  const mocQueueImpl = await mocQueueFactory.deploy();
  const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
  const erc1967Proxy = await erc1967ProxyFactory.deploy(mocQueueImpl.target, "0x");
  let deployer: Address;
  ({ deployer } = await getNamedAccounts());
  const signer = await ethers.getSigner(deployer);
  const mocQueueProxy = MocQueue__factory.connect(erc1967Proxy.target.toString(), signer);
  await mocQueueProxy.initialize(
    (await getGovernorAddresses(hre)).governorAddress,
    pauser || mocAddresses.pauserAddress,
    mocMultiCollateralGuardAddress,
    queueParams.minOperWaitingBlk,
    queueParams.maxOperWaitingBlk,
    queueParams.execCostParams,
  );
  return mocQueueProxy;
};

export async function deployBucket({
  governorAddress,
  mocMultiCollateralGuardAddress,
  mocCoreExpansionAddress,
  mocVendorsAddress,
  feeTokenAddress,
  feeTokenPriceProviderAddress,
}: {
  governorAddress: Address;
  mocMultiCollateralGuardAddress: Address;
  mocCoreExpansionAddress: Address;
  mocVendorsAddress: Address;
  feeTokenAddress: Address;
  feeTokenPriceProviderAddress: Address;
}): Promise<{ mocCARC20: MocCARC20; mocQueue: MocQueue; acToken: ERC20Mock; tcToken: MocRC20 }> {
  const { deployer, pauser } = await getNamedAccounts();
  const factory = await ethers.getContractFactory("MocCARC20");
  const mocCARC20Impl = await factory.deploy();
  const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
  const erc1967Proxy = await erc1967ProxyFactory.deploy(mocCARC20Impl.target, "0x");
  const signer = await ethers.getSigner(deployer);
  const mocCARC20 = MocCARC20__factory.connect(erc1967Proxy.target.toString(), signer);
  const acToken = await deployAsset();
  const tcToken = await deployAndInitTC({ adminAddress: deployer, governorAddress });
  const mocQueue = await deployMocQueue({
    contractName: "MocQueueBasefeeMock",
    mocMultiCollateralGuardAddress,
    pauser,
  });

  const DataProviderMockFactory = await ethers.getContractFactory("DataProviderMock");
  const maxAbsoluteOpProviderAddress = (await DataProviderMockFactory.deploy(CONSTANTS.MAX_UINT256)).target.toString();
  const maxOpDiffProviderAddress = (await DataProviderMockFactory.deploy(CONSTANTS.MAX_UINT256)).target.toString();
  await mocInitialize(
    mocCARC20,
    tcToken.target.toString(),
    mocCoreExpansionAddress,
    mocVendorsAddress,
    mocQueue.target.toString(),
    {
      acTokenAddress: acToken.target.toString(),
    },
  )({
    mocGovernorAddress: governorAddress,
    feeTokenAddress,
    feeTokenPriceProviderAddress,
    maxAbsoluteOpProviderAddress,
    maxOpDiffProviderAddress,
    mocPauserAddress: pauser,
  });
  await tcToken.transferAllRoles(mocCARC20.target);
  await mocQueue.registerBucket(mocCARC20.target);

  return { mocCARC20, mocQueue, acToken, tcToken };
}

export const deployCommissionSplitter = async ({
  acToken,
  governorAddress,
  feeToken,
  acTokenAddressRecipient1,
  acTokenAddressRecipient2,
  acTokenPctToRecipient1,
  feeTokenAddressRecipient1,
  feeTokenAddressRecipient2,
  feeTokenPctToRecipient1,
}: {
  acToken?: Address;
  governorAddress: Address;
  feeToken: Address;
  acTokenAddressRecipient1: Address;
  acTokenAddressRecipient2: Address;
  acTokenPctToRecipient1: BigNumberish;
  feeTokenAddressRecipient1: Address;
  feeTokenAddressRecipient2: Address;
  feeTokenPctToRecipient1: BigNumberish;
}) => {
  let deployer: Address;
  ({ deployer } = await getNamedAccounts());
  const signer = await ethers.getSigner(deployer);
  const commissionSplitterFactory = await ethers.getContractFactory(
    acToken ? "CommissionSplitterRC20" : "CommissionSplitterCoinbase",
  );
  const commissionSplitterImpl = await commissionSplitterFactory.deploy();
  const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
  const erc1967Proxy = await erc1967ProxyFactory.deploy(commissionSplitterImpl.target.toString(), "0x");
  const commissionSplitterProxy = acToken
    ? CommissionSplitterRC20__factory.connect(erc1967Proxy.target.toString(), signer)
    : CommissionSplitterCoinbase__factory.connect(erc1967Proxy.target.toString(), signer);

  if (acToken) {
    await (commissionSplitterProxy as CommissionSplitterRC20).initialize(
      acToken,
      governorAddress,
      feeToken,
      acTokenAddressRecipient1,
      acTokenAddressRecipient2,
      acTokenPctToRecipient1,
      feeTokenAddressRecipient1,
      feeTokenAddressRecipient2,
      feeTokenPctToRecipient1,
    );
  } else {
    await (commissionSplitterProxy as CommissionSplitterCoinbase).initialize(
      governorAddress,
      feeToken,
      acTokenAddressRecipient1,
      acTokenAddressRecipient2,
      acTokenPctToRecipient1,
      feeTokenAddressRecipient1,
      feeTokenAddressRecipient2,
      feeTokenPctToRecipient1,
    );
  }
  return commissionSplitterProxy;
};

export const tpParamsDefault = {
  price: PCT_BASE, // 1
  tpCtarg: PCT_BASE * 4n, // 4
  tpMintFee: (PCT_BASE * 5n) / 100n, // 5%
  tpRedeemFee: (PCT_BASE * 5n) / 100n, // 5%
  tpEma: PCT_BASE, // 1
  tpEmaSf: (PCT_BASE * 47619048n) / 10000000000n, // 0,047619048
};

export const bucketParamsDefault = {
  acCoinbasePrice: PCT_BASE, // 1
  maxACtoSwap: PCT_BASE * 1000n, // 10k
  rtcThrld: (PCT_BASE * 15n) / 100n, // 1.5
  rebalancingThrld: PCT_BASE * 2n, // 2
  penaltyRate: (PCT_BASE * 7n) / 1000n, // 0.7%
};

export const tpParams = [
  {
    price: pEth(235),
    tpCtarg: pEth(5),
    tpEma: pEth(212.04),
    tpEmaSf: pEth(0.05),
  },
  {
    price: pEth(5.25),
    tpCtarg: pEth(4),
    tpEma: pEth(5.04),
    tpEmaSf: pEth(0.05),
    tpMintFee: PCT_BASE / 1000n, // 0.1%
  },
  {
    price: pEth(934.58),
    tpCtarg: pEth(3.5),
    tpEma: pEth(837.33),
    tpEmaSf: pEth(0.01),
  },
  {
    price: pEth(20.1),
    tpCtarg: pEth(3),
    tpEma: pEth(20.23),
    tpEmaSf: pEth(0.01),
  },
  {
    price: pEth(5.25),
    tpCtarg: pEth(6),
    tpEma: pEth(5.04),
    tpEmaSf: pEth(0.05),
    tpMintFee: PCT_BASE / 1000n, // 0.1%
  },
];

const getTPparams = ({
  price = tpParamsDefault.price,
  tpCtarg = tpParamsDefault.tpCtarg,
  tpMintFee = tpParamsDefault.tpMintFee,
  tpRedeemFee = tpParamsDefault.tpRedeemFee,
  tpEma = tpParamsDefault.tpEma,
  tpEmaSf = tpParamsDefault.tpEmaSf,
}) => {
  return {
    price,
    tpCtarg,
    tpMintFee,
    tpRedeemFee,
    tpEma,
    tpEmaSf,
  };
};

export async function deployAndAddPeggedToken(
  mocImpl: MocCARC20 | MocCACoinbase,
  tpParams?: any,
  mocPeggedTokenToAdd?: MocRC20,
  assignRoles: boolean = true,
): Promise<{ mocPeggedToken: MocRC20; priceProvider: PriceProviderMock }> {
  const { deployer } = await getNamedAccounts();
  const governorAddress = await mocImpl.governor();
  const mocPeggedToken = mocPeggedTokenToAdd || (await deployPeggedToken({ adminAddress: deployer, governorAddress }));
  const params = tpParams ? getTPparams(tpParams) : getTPparams({});
  const priceProvider = await deployPriceProvider(params.price);
  await mocImpl.addPeggedToken(mocPeggedToken.target, {
    priceProviderAddress: priceProvider.target,
    tpCtarg: params.tpCtarg,
    tpMintFee: params.tpMintFee,
    tpRedeemFee: params.tpRedeemFee,
    tpEma: params.tpEma,
    tpEmaSf: params.tpEmaSf,
  });
  // conditional as Role granting is only possible with mock governor
  if (assignRoles) {
    await mocPeggedToken.grantRole(DEFAULT_ADMIN_ROLE, mocImpl.target);
    await mocPeggedToken.grantRole(MINTER_ROLE, mocImpl.target);
    await mocPeggedToken.grantRole(BURNER_ROLE, mocImpl.target);
  }
  return { mocPeggedToken, priceProvider };
}

export async function deployAndAddPeggedTokens(
  mocImpl: MocCARC20 | MocCACoinbase,
  amountPegTokens: number,
  tpParams?: any[],
  mocPeggedTokenToAdd?: MocRC20[],
  assignRoles: boolean = true,
): Promise<{ mocPeggedTokens: MocRC20[]; priceProviders: PriceProviderMock[] }> {
  const mocPeggedTokens: Array<MocRC20> = [];
  const priceProviders: Array<PriceProviderMock> = [];
  for (let i = 0; i < amountPegTokens; i++) {
    const { mocPeggedToken, priceProvider } = await deployAndAddPeggedToken(
      mocImpl,
      tpParams && tpParams[i],
      mocPeggedTokenToAdd && mocPeggedTokenToAdd[i],
      assignRoles,
    );
    mocPeggedTokens.push(mocPeggedToken);
    priceProviders.push(priceProvider);
  }
  return { mocPeggedTokens, priceProviders };
}

export async function deployPriceProvider(price: bigint): Promise<PriceProviderMock> {
  const factory = await ethers.getContractFactory("PriceProviderMock");
  return factory.deploy(price);
}

export async function deployDataProvider(data: bigint): Promise<DataProviderMock> {
  const factory = await ethers.getContractFactory("DataProviderMock");
  return factory.deploy(data);
}

export async function deployAeropagusGovernor(deployer: Address): Promise<IGovernor> {
  const factory = await ethers.getContractFactory(GovernorCompiled.abi, GovernorCompiled.bytecode);
  const governor = await factory.deploy();
  await governor.waitForDeployment();
  await governor.getFunction("initialize(address)")(deployer);
  return IGovernor__factory.connect(governor.target.toString(), await ethers.getSigner(deployer));
}

export async function deployAsset(): Promise<ERC20Mock> {
  const factory = await ethers.getContractFactory("ERC20Mock");
  const asset = await factory.deploy();
  // Fill users accounts with balance so that they can operate
  const { alice, bob, charlie } = await getNamedAccounts();
  await Promise.all([alice, bob, charlie].map(address => asset.mint(address, pEth(1e16))));
  return asset;
}

export async function deployAssetERC777(): Promise<ERC777Mock> {
  const factory = await ethers.getContractFactory("ERC777Mock");
  const { deployer } = await getNamedAccounts();
  const asset = await factory.deploy([deployer]);
  return asset;
}

export type Balance = bigint;
export type OperId = bigint;

export const ethersGetBalance = (account: Address) => ethers.provider.getBalance(account);
export const ethersSendValue = async (from: Address, to: Address, value: Balance) => {
  const signer = await ethers.getSigner(from);
  return signer.sendTransaction({
    to,
    value,
  });
};

export const ERRORS = {
  ERC20_TRANF_EXCEEDS_BALANCE: "ERC20: transfer amount exceeds balance",
  ERC20_MINT_TO_ZERO_ADDRESS: "ERC20: mint to the zero address",
  CONTRACT_INITIALIZED: "Initializable: contract is already initialized",
  INVALID_ADDRESS: "InvalidAddress",
  INVALID_VALUE: "InvalidValue",
  INVALID_ROLES: "InvalidRoles",
  INVALID_GOVERNOR: "InvalidGovernor",
  INSUFFICIENT_QAC_SENT: "InsufficientQacSent",
  INSUFFICIENT_QTP_SENT: "InsufficientQtpSent",
  INSUFFICIENT_TP_TO_MINT: "InsufficientTPtoMint",
  INSUFFICIENT_TP_TO_REDEEM: "InsufficientTPtoRedeem",
  INSUFFICIENT_TC_TO_REDEEM: "InsufficientTCtoRedeem",
  LIQUIDATED: "Liquidated",
  ONLY_LIQUIDATED: "OnlyWhenLiquidated",
  LOW_COVERAGE: "LowCoverage",
  MISSING_PROVIDER_PRICE: "MissingProviderPrice",
  NOT_WHEN_PAUSED: "NotWhenPaused",
  NOT_AUTH_CHANGER: "NotAuthorizedChanger",
  NOT_UNIQUE_ROLE: "NotUniqueRole",
  ONLY_PAUSER: "OnlyPauser",
  ONLY_WHILE_PAUSED: "OnlyWhilePaused",
  PEGGED_TOKEN_ALREADY_ADDED: "PeggedTokenAlreadyAdded",
  QAC_BELOW_MINIMUM: "QacBelowMinimumRequired",
  QAC_NEEDED_MUST_BE_GREATER_ZERO: "QacNeededMustBeGreaterThanZero",
  QTP_TP_MINT_MUST_BE_GREATER_ZERO: "QTPtoMintMustBeGreaterThanZero",
  QTP_BELOW_MINIMUM: "QtpBelowMinimumRequired",
  QTC_BELOW_MINIMUM: "QtcBelowMinimumRequired",
  RECIPIENT_MUST_BE_SENDER: "RecipientMustBeSender",
  REENTRACYGUARD: "ReentrancyGuard: reentrant call",
  TRANSFER_FAIL: "TransferFailed",
  UNSTOPPABLE: "Unstoppable",
  MISSING_TIME_TO_SETTLEMENT: "MissingTimeToSettlement",
  MISSING_TIME_TO_TC_INTEREST_PAYMENT: "MissingTimeToTCInterestPayment",
  EXEC_FEE_PAYMENT_FAILED: "ExecutionFeePaymentFailed",
  WRONG_EXEC_FEES: "WrongExecutionFee",
  MAX_FLUX_CAPACITOR_REACHED: "MaxFluxCapacitorOperationReached",
  INVALID_FLUX_CAPACITOR_OPERATION: "InvalidFluxCapacitorOperation",
  MISSING_PROVIDER_DATA: "MissingProviderData",
  BUCKET_ALREADY_REGISTERED: "BucketAlreadyRegistered",
  ONLY_QUEUE: "OnlyQueue",
  NOT_BUCKET: "NotMocBucket",
  TP_AMOUNT_UNEQUAL_LENGTH: "TpAmountUnequalLength",
  TP_NOT_IN_BASE_BUCKET: "TpNotInBaseBucket",
  TP_TOTAL_SUPPLY_NOT_ZERO: "TPTotalSupplyNotZero",
  BUCKET_ALREADY_EXISTS: "BucketAlreadyExists",
  INCOMPATIBLE_BUCKET: "IncompatibleBucket",
  UNEQUAL_LENGTH: "UnequalLength",
  BUCKET_DOES_NOT_EXIST: "BucketDoesNotExist",
  BUCKET_PARAM_DUPLICATED: "BucketParamDuplicated",
  ONLY_MULTICOLLATERALGUARD: "OnlyMultiCollateralGuard",
  MICRO_LIQUIDATION_NOT_AVAILABLE: "MicroLiquidationNotAvailable",
  LIQUIDATION_NOT_AVAILABLE: "LiquidationNotAvailable",
  LIQUIDATION_IN_PROCESS: "LiquidationInProcess",
  BUCKET_NOT_LIQUIDATED: "BucketNotLiquidated",
  BUCKET_NOT_AVAILABLE: "NoTargetBucketAvailableToRebalance",
  BUCKET_EMPTY: "BucketEmpty",
};

const getSelectorFor = (error: string) => ethers.dataSlice(ethers.id(error), 0, 4);

const getErrorSelectorFor = (error: string) => {
  const functionSelector = ethers.id("Error(string)").slice(0, 10);
  const encodedErrorMessage = AbiCoder.defaultAbiCoder().encode(["string"], [error]);
  // Concatenate function selector and encoded message
  return functionSelector + encodedErrorMessage.slice(2);
};

export const ERROR_SELECTOR = {
  LOW_COVERAGE: getSelectorFor(ERRORS.LOW_COVERAGE + "(uint256,uint256)"),
  INSUFFICIENT_QAC_SENT: getSelectorFor(ERRORS.INSUFFICIENT_QAC_SENT + "(uint256,uint256)"),
  INSUFFICIENT_TC_TO_REDEEM: getSelectorFor(ERRORS.INSUFFICIENT_TC_TO_REDEEM + "(uint256,uint256)"),
  INSUFFICIENT_TP_TO_MINT: getSelectorFor(ERRORS.INSUFFICIENT_TP_TO_MINT + "(uint256,uint256)"),
  INSUFFICIENT_TP_TO_REDEEM: getSelectorFor(ERRORS.INSUFFICIENT_TP_TO_REDEEM + "(uint256,uint256)"),
  INSUFFICIENT_QTP_SENT: getSelectorFor(ERRORS.INSUFFICIENT_QTP_SENT + "(uint256,uint256)"),
  QAC_NEEDED_MUST_BE_GREATER_ZERO: getSelectorFor(ERRORS.QAC_NEEDED_MUST_BE_GREATER_ZERO + "()"),
  QAC_BELOW_MINIMUM: getSelectorFor(ERRORS.QAC_BELOW_MINIMUM + "(uint256,uint256)"),
  QTP_BELOW_MINIMUM: getSelectorFor(ERRORS.QTP_BELOW_MINIMUM + "(uint256,uint256)"),
  QTC_BELOW_MINIMUM: getSelectorFor(ERRORS.QTC_BELOW_MINIMUM + "(uint256,uint256)"),
  INVALID_FLUX_CAPACITOR_OPERATION: getSelectorFor(ERRORS.INVALID_FLUX_CAPACITOR_OPERATION + "()"),
  TRANSFER_FAILED: getSelectorFor(ERRORS.TRANSFER_FAIL + "()"),
  LIQUIDATED: getSelectorFor(ERRORS.LIQUIDATED + "()"),
  PAUSED: getSelectorFor(ERRORS.NOT_WHEN_PAUSED + "()"),
  MISSING_PROVIDER_PRICE: getSelectorFor(ERRORS.MISSING_PROVIDER_PRICE + "(address)"),
  ERC20_MINT_TO_ZERO_ADDRESS: getErrorSelectorFor(ERRORS.ERC20_MINT_TO_ZERO_ADDRESS),
};

export function mineNBlocks(blocks: number | bigint, secondsPerBlock: number = 1): Promise<any> {
  return network.provider.send("hardhat_mine", ["0x" + blocks.toString(16), "0x" + secondsPerBlock.toString(16)]);
}

export function getBlock(block: any) {
  return ethers.provider.getBlock(block);
}

export function getSigner(account: Address): Promise<Signer> {
  return ethers.getSigner(account);
}

export async function ensureERC1820(): Promise<void> {
  const ERC1820_ADDRESS = "0x1820a4b7618bde71dce8cdc73aab6c95905fad24";
  const ERC1820_DEPLOYER = "0xa990077c3205cbDf861e17Fa532eeB069cE9fF96";
  const ERC1820_PAYLOAD =
    "0xf90a388085174876e800830c35008080b909e5608060405234801561001057600080fd5b506109c5806100206000396000f3fe608060405234801561001057600080fd5b50600436106100a5576000357c010000000000000000000000000000000000000000000000000000000090048063a41e7d5111610078578063a41e7d51146101d4578063aabbb8ca1461020a578063b705676514610236578063f712f3e814610280576100a5565b806329965a1d146100aa5780633d584063146100e25780635df8122f1461012457806365ba36c114610152575b600080fd5b6100e0600480360360608110156100c057600080fd5b50600160a060020a038135811691602081013591604090910135166102b6565b005b610108600480360360208110156100f857600080fd5b5035600160a060020a0316610570565b60408051600160a060020a039092168252519081900360200190f35b6100e06004803603604081101561013a57600080fd5b50600160a060020a03813581169160200135166105bc565b6101c26004803603602081101561016857600080fd5b81019060208101813564010000000081111561018357600080fd5b82018360208201111561019557600080fd5b803590602001918460018302840111640100000000831117156101b757600080fd5b5090925090506106b3565b60408051918252519081900360200190f35b6100e0600480360360408110156101ea57600080fd5b508035600160a060020a03169060200135600160e060020a0319166106ee565b6101086004803603604081101561022057600080fd5b50600160a060020a038135169060200135610778565b61026c6004803603604081101561024c57600080fd5b508035600160a060020a03169060200135600160e060020a0319166107ef565b604080519115158252519081900360200190f35b61026c6004803603604081101561029657600080fd5b508035600160a060020a03169060200135600160e060020a0319166108aa565b6000600160a060020a038416156102cd57836102cf565b335b9050336102db82610570565b600160a060020a031614610339576040805160e560020a62461bcd02815260206004820152600f60248201527f4e6f7420746865206d616e616765720000000000000000000000000000000000604482015290519081900360640190fd5b6103428361092a565b15610397576040805160e560020a62461bcd02815260206004820152601a60248201527f4d757374206e6f7420626520616e204552433136352068617368000000000000604482015290519081900360640190fd5b600160a060020a038216158015906103b85750600160a060020a0382163314155b156104ff5760405160200180807f455243313832305f4143434550545f4d4147494300000000000000000000000081525060140190506040516020818303038152906040528051906020012082600160a060020a031663249cb3fa85846040518363ffffffff167c01000000000000000000000000000000000000000000000000000000000281526004018083815260200182600160a060020a0316600160a060020a031681526020019250505060206040518083038186803b15801561047e57600080fd5b505afa158015610492573d6000803e3d6000fd5b505050506040513d60208110156104a857600080fd5b5051146104ff576040805160e560020a62461bcd02815260206004820181905260248201527f446f6573206e6f7420696d706c656d656e742074686520696e74657266616365604482015290519081900360640190fd5b600160a060020a03818116600081815260208181526040808320888452909152808220805473ffffffffffffffffffffffffffffffffffffffff19169487169485179055518692917f93baa6efbd2244243bfee6ce4cfdd1d04fc4c0e9a786abd3a41313bd352db15391a450505050565b600160a060020a03818116600090815260016020526040812054909116151561059a5750806105b7565b50600160a060020a03808216600090815260016020526040902054165b919050565b336105c683610570565b600160a060020a031614610624576040805160e560020a62461bcd02815260206004820152600f60248201527f4e6f7420746865206d616e616765720000000000000000000000000000000000604482015290519081900360640190fd5b81600160a060020a031681600160a060020a0316146106435780610646565b60005b600160a060020a03838116600081815260016020526040808220805473ffffffffffffffffffffffffffffffffffffffff19169585169590951790945592519184169290917f605c2dbf762e5f7d60a546d42e7205dcb1b011ebc62a61736a57c9089d3a43509190a35050565b600082826040516020018083838082843780830192505050925050506040516020818303038152906040528051906020012090505b92915050565b6106f882826107ef565b610703576000610705565b815b600160a060020a03928316600081815260208181526040808320600160e060020a031996909616808452958252808320805473ffffffffffffffffffffffffffffffffffffffff19169590971694909417909555908152600284528181209281529190925220805460ff19166001179055565b600080600160a060020a038416156107905783610792565b335b905061079d8361092a565b156107c357826107ad82826108aa565b6107b85760006107ba565b815b925050506106e8565b600160a060020a0390811660009081526020818152604080832086845290915290205416905092915050565b6000808061081d857f01ffc9a70000000000000000000000000000000000000000000000000000000061094c565b909250905081158061082d575080155b1561083d576000925050506106e8565b61084f85600160e060020a031961094c565b909250905081158061086057508015155b15610870576000925050506106e8565b61087a858561094c565b909250905060018214801561088f5750806001145b1561089f576001925050506106e8565b506000949350505050565b600160a060020a0382166000908152600260209081526040808320600160e060020a03198516845290915281205460ff1615156108f2576108eb83836107ef565b90506106e8565b50600160a060020a03808316600081815260208181526040808320600160e060020a0319871684529091529020549091161492915050565b7bffffffffffffffffffffffffffffffffffffffffffffffffffffffff161590565b6040517f01ffc9a7000000000000000000000000000000000000000000000000000000008082526004820183905260009182919060208160248189617530fa90519096909550935050505056fea165627a7a72305820377f4a2d4301ede9949f163f319021a6e9c687c292a5e2b2c4734c126b524e6c00291ba01820182018201820182018201820182018201820182018201820182018201820a01820182018201820182018201820182018201820182018201820182018201820";

  const code = await ethers.provider.send("eth_getCode", [ERC1820_ADDRESS, "latest"]);
  if (code === "0x") {
    const [from] = await ethers.provider.send("eth_accounts", []);

    await ethers.provider.send("eth_sendTransaction", [
      {
        from,
        to: ERC1820_DEPLOYER,
        value: "0x11c37937e080000",
      },
    ]);

    await ethers.provider.send("eth_sendRawTransaction", [ERC1820_PAYLOAD]);
  }
}

export function expectEventFor(mocContracts: any, eventName: string): any {
  return async (tx: ContractTransactionResponse, rawArgs: any[]) => {
    // TODO: replace with withNamedArgs when https://github.com/NomicFoundation/hardhat/issues/4166#issuecomment-1640291151 is ready
    let args = [...rawArgs, anyValue];
    await expect(tx)
      .to.emit(mocContracts.mocQueue, eventName)
      .withArgs(...args);
  };
}

// reads the value of a given internal array by accessing the storage slot
export async function getArrayValueAt(contract: Address, slot: number, index: number): Promise<bigint> {
  // Calculate the base slot for the array data (keccak256(slot))
  const dataSlot = keccak256(ethers.zeroPadValue(ethers.toBeHex(slot), 32));
  const elementSlot = getBigInt(dataSlot) + BigInt(index);
  const valueHex = await ethers.provider.getStorage(contract, elementSlot);
  return getBigInt(valueHex);
}

// Simulation params, that can be picked up from ENV variables
export const simParams = () => {
  return {
    tpAmount: process.env.TP_AMOUNT ? Math.max(Number(process.env.TP_AMOUNT), 2) : 5,
    gasPricesWei: {
      min: Number(process.env.GAS_PRICE_MIN) || 65800000,
      avg: Number(process.env.GAS_PRICE_AVG) || 65800000,
      median: Number(process.env.GAS_PRICE_MEDIAN) || 65800000,
      max: Number(process.env.GAS_PRICE_MAX) || 65800000,
    },
    blockGasLimit: process.env.BLOCK_GAS_LIMIT || 6800000,
    gasAdjustmentMultiplier: 1.2,
    feeTokenPrice: Number(process.env.FEE_TOKEN_PRICE) || 95000,
    execFee: {
      bucketAmount: process.env.EXEC_FEE_BUCKET_AMOUNT ? Number(process.env.EXEC_FEE_BUCKET_AMOUNT) : 2,
      iter: process.env.EXEC_FEE_ITER ? Number(process.env.EXEC_FEE_ITER) : 10,
      avgOperPerBatch: process.env.EXEC_FEE_AVG_OPER_PER_BATCH ? Number(process.env.EXEC_FEE_AVG_OPER_PER_BATCH) : 1,
      tpAmount: process.env.EXEC_FEE_TP_AMOUNT ? Number(process.env.EXEC_FEE_TP_AMOUNT) : 1,
    },
    batchSize: {
      tpAmount: process.env.BATCH_SIZE_TP_AMOUNT ? Number(process.env.BATCH_SIZE_TP_AMOUNT) : 1,
      operPerBatch: process.env.BATCH_SIZE_OPER_PER_BATCH ? Number(process.env.BATCH_SIZE_OPER_PER_BATCH) : 1,
    },
  };
};

export function timedDescribe(name: string, tests: Function): void {
  describe(name, function () {
    let startTime: number;

    before(function () {
      startTime = Date.now();
    });
    tests();
    after(function () {
      const endTime = Date.now();

      console.log(`${endTime - startTime} milliseconds to complete ${name} suite `);
    });
  });
}

type SetupFunction = () => Promise<unknown>;

export function finalDescribe(setup: SetupFunction, name: string, tests: Function) {
  describe(name, async function () {
    before(setup);
    tests();
  });
}

export function finalFixturedDescribe(setup: SetupFunction, name: string, tests: Function) {
  const setupFixture = () => {
    return loadFixture(setup);
  };
  finalDescribe(setupFixture, name, tests);
}

export function describeEspecial(beforeEachComponent: SetupFunction, name: string, tests: Function) {
  function setuppedDescribe(name2: string, tests2: Function) {
    describe(name2, function () {
      before(beforeEachComponent);
      tests2();
    });
  }
  function setuppedIt(name2: string, assertion: Function) {
    it(name2, async function () {
      await beforeEachComponent();
      assertion();
    });
  }

  describe(name, async function () {
    before(setup);
    tests(setuppedDescribe, setuppedIt);
  });
}

export type BaseSetupFunction = () => Promise<{ mocContracts: MoCContracts; mocFunctions: MoCFunctions }>;

export type MoCContracts = MoCRC20Contracts | MoCCoinbaseContracts;

export type MoCFunctions = {
  mintTC: Function;
  mintTP: Function;
  mintTCandTP: Function;
  swapTPforTP: Function;
  swapTCforTP: Function;
  swapTPforTC: Function;
  assetBalanceOf: Function;
  assertACResult: Function;
  acBalanceOf: Function;
  refreshACBalance: Function;

  redeemTC: Function;
  redeemTP: Function;
  redeemTCandTP: Function;
  liqRedeemTP: Function;
  tcBalanceOf: Function;
  tpBalanceOf: Function;
  tcTransfer: Function;
  tpTransfer: Function;
  coinbaseTransfer: Function;
  tTransfer: Function;
  pokePrice: Function;
  executeQueue: Function;
  execWrap: Function;
};

export enum FailType {
  notFail,
  failWithFalse,
  failWithRevert,
}
