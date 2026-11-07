import { Address } from "hardhat-deploy/types";
import { DeployParameters } from "../types";

const ONE = BigInt(1e18);
const DAY_TIME_SPAN = 2880n;
const WEEK_TIME_SPAN = DAY_TIME_SPAN * 7n;
const MONTH_TIME_SPAN = DAY_TIME_SPAN * 30n;

// Moc Addresses are picked up by network configuration
type AddBucketParams = Omit<DeployParameters, "mocAddresses"> & { bucketId: string; mocMultiCollateralGuard?: Address };

export const addBucketConfig: AddBucketParams = {
  bucketId: "_bucket4",
  coreParams: {
    protThrld: ONE * 2n, // 2
    liqThrld: (ONE * 104n) / 100n, // 1.04
    emaCalculationTimeSpan: DAY_TIME_SPAN,
    successFee: ONE / 10n, // 10%
    appreciationFactor: (ONE * 50n) / 100n, // 50%
    tcInterestRate: (ONE * 5n) / 100000n, // 0.005% : weekly 0.0025 / 365 * 7
    tcInterestPaymentTimeSpan: WEEK_TIME_SPAN,
    decayTimeSpan: DAY_TIME_SPAN,
    transferMaxGas: 3000n,
  },
  settlementParams: {
    settlementTimeSpan: MONTH_TIME_SPAN,
  },
  vendorsParams: {
    maxMarkup: ONE / 10n, // 10%
  },
  feeParams: {
    feeRetainer: 0n, // 0%
    tcMintFee: (ONE * 5n) / 100n, // 5%
    tcRedeemFee: (ONE * 5n) / 100n, // 5%
    swapTPforTPFee: (ONE * 1n) / 100n, // 1%
    swapTPforTCFee: (ONE * 1n) / 100n, // 1%
    swapTCforTPFee: (ONE * 1n) / 100n, // 1%
    redeemTCandTPFee: (ONE * 8n) / 100n, // 8%
    mintTCandTPFee: (ONE * 8n) / 100n, // 8%
    feeTokenPct: (ONE * 5n) / 10n, // 50%
  },
  ctParams: {
    name: "CollateralToken",
    symbol: "CT",
    decimals: 18n,
  },
  tpParams: {
    tpParams: [
      {
        tpMintFee: (ONE * 5n) / 100n, // 5%
        tpRedeemFee: (ONE * 5n) / 100n, // 5%
        tpCtarg: ONE * 5n, // 5
        tpEma: ONE, // 1
        tpEmaSf: (ONE * 5n) / 100n, // 0.05
      },
    ],
  },
  queueParams: {
    minOperWaitingBlk: 1n,
    maxOperWaitingBlk: 2n,
    execCostParams: {
      tcMintExecCost: 1000000n,
      tcRedeemExecCost: 1000001n,
      tpMintExecCost: 1000002n,
      tpRedeemExecCost: 1000003n,
      mintTCandTPExecCost: 2000000n,
      redeemTCandTPExecCost: 2000001n,
      swapTPforTPExecCost: 2000002n,
      swapTPforTCExecCost: 1000003n,
      swapTCforTPExecCost: 1000004n,
    },
  },
  multiCollateralParams: {
    maxOperPerBatch: 10n,
    useMaxLastPublicationBlock: true,
    microLiquidationExecCost: ONE / 100n, // 0.01 ether
    liquidationExecCost: ONE / 10n, // 0.1 ether
    coinbaseExecFeeRecipient: "0x28A00Af444928D689ddEC7B4D17c0e4a8c9d4061",
  },
  liquidationParams: {
    acCoinbasePriceProviderAddress: "",
    rtcThrld: (ONE * 18n) / 10n, // 1.8
    microLiquidationThrld: (ONE * 13n) / 10n, // 1.3
    penaltyRate: (ONE * 7n) / 1000n, // 0.7%
    mocSwappers: [],
  },
  gasLimit: 6800000,
};
