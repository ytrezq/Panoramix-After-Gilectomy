import { Address } from "hardhat-deploy/dist/types";

export type TPParams = {
  // if it is needed to deploy a TP contract, use this artifact. By default MocRC20
  artifact?: string;
  // token name, optional for existent TP
  name?: string;
  // token symbol, optional for existent TP
  symbol?: string;
  // token decimals, optional for existent TP
  decimals?: bigint;
  // Pegged Token price provider contract address, optional for existent TP
  priceProviderAddress?: Address;
  // Pegged Token target coverage [PREC]
  tpCtarg: bigint;
  // additional fee pct applied on mint [PREC]
  tpMintFee: bigint;
  // additional fee pct applied on redeem [PREC]
  tpRedeemFee: bigint;
  // initial Pegged Token exponential moving average [PREC]
  tpEma: bigint;
  // Pegged Token smoothing factor [PREC]
  tpEmaSf: bigint;
};

export type DeployParameters = {
  coreParams: {
    // protected coverage threshold [PREC]
    protThrld: bigint;
    // liquidation coverage threshold [PREC]
    liqThrld: bigint;
    // amount of time to wait for next ema calculation
    emaCalculationTimeSpan: bigint;
    // pct of the gain because Pegged Tokens devaluation that is transferred in Collateral Asset to Moc Fee Flow during the settlement [PREC]
    successFee: bigint;
    // pct of the gain because Pegged Tokens devaluation that is returned in Pegged Tokens to appreciation beneficiary during the settlement [PREC]
    appreciationFactor: bigint;
    // pct interest charged to TC holders on the total collateral in the protocol [PREC]
    tcInterestRate: bigint;
    // amount of time to wait for next TC interest payment
    tcInterestPaymentTimeSpan: bigint;
    // amount of time that have to elapse for the linear decay factor to be 0
    decayTimeSpan: bigint;
    // max amount of gas forwarded on AC transfer(only for coinbase flavor)
    transferMaxGas?: bigint;
    // RC20 only. If false, operation's recipient field must be msg.sender or the tx will revert
    allowDifferentRecipient?: boolean;
  };
  settlementParams: {
    // time between settlements
    settlementTimeSpan: bigint;
  };
  vendorsParams: {
    // max markup percentage allowed on vendors [PREC]
    maxMarkup: bigint;
  };
  feeParams: {
    // pct retain on fees to be re-injected as Collateral, while paying fees with AC [PREC]
    feeRetainer: bigint;
    // additional fee pct applied on mint Collateral Tokens operations [PREC]
    tcMintFee: bigint;
    // additional fee pct applied on redeem Collateral Tokens operations [PREC]
    tcRedeemFee: bigint;
    // additional fee pct applied on swap a Pegged Token for another Pegged Token [PREC]
    swapTPforTPFee: bigint;
    // additional fee pct applied on swap a Pegged Token for Collateral Token [PREC]
    swapTPforTCFee: bigint;
    // additional fee pct applied on swap Collateral Token for a Pegged Token [PREC]
    swapTCforTPFee: bigint;
    // additional fee pct applied on redeem Collateral Token and Pegged Token [PREC]
    redeemTCandTPFee: bigint;
    // additional fee pct applied on mint Collateral Token and Pegged Token [PREC]
    mintTCandTPFee: bigint;
    // pct applied on the top of the operation`s fee when using Fee Token as fee payment method [PREC]
    // e.g. if tcMintFee = 1%, feeTokenPct = 50% => qFeeToken = 0.5%
    feeTokenPct: bigint;
  };
  ctParams: {
    // collateral token name
    name: string;
    // collateral token symbols
    symbol: string;
    // collateral token decimals, optional for non 18 decimals tokens
    decimals?: bigint;
  };
  // only for initialization in testnet
  tpParams?: {
    tpParams: TPParams[];
  };
  mocAddresses: {
    // collateral asset token address, only used for RC20 implementation
    collateralAssetAddress?: Address;
    // the address that will define when a change contract is authorized
    governorAddress: Address;
    // the address that is authorized to pause this contract
    pauserAddress: Address;
    // the Fee Token contract address used as an alternative method for paying fees instead of collateral asset
    feeTokenAddress: Address;
    // the Fee Token price provider contract address
    feeTokenPriceProviderAddress: Address;
    // moc Fee Flow contract address
    mocFeeFlowAddress: Address;
    // moc appreciation beneficiary Address
    mocAppreciationBeneficiaryAddress: Address;
    // address authorized to change a vendor markup
    vendorsGuardianAddress: Address;
    // TC interest collector address
    tcInterestCollectorAddress: Address;
    // max absolute operation provider address
    maxAbsoluteOpProviderAddress: Address;
    // max operation difference provider address
    maxOpDiffProviderAddress: Address;
  };
  queueParams: {
    // min amount of blocks the Operation should wait in the Queue before execution
    minOperWaitingBlk: bigint;
    // max amount of blocks the Operation should wait in the Queue. Even if there is no price update
    // it can be executed after this amount of blocks
    maxOperWaitingBlk: bigint;
    execCostParams: {
      tpMintExecCost: bigint;
      tpRedeemExecCost: bigint;
      tcMintExecCost: bigint;
      tcRedeemExecCost: bigint;
      swapTPforTPExecCost: bigint;
      swapTPforTCExecCost: bigint;
      swapTCforTPExecCost: bigint;
      redeemTCandTPExecCost: bigint;
      mintTCandTPExecCost: bigint;
    };
  };
  multiCollateralParams: {
    // max amount of Operations that can be executed on a single batch
    maxOperPerBatch: bigint;
    // switches the way that price providers trigger the queue execution using the last publication block
    // false: use the minimum, so operations enqueued before the oldest price are executed. New operations
    //  have to wait until all the prices are updated
    // true: use the maximum, so operations enqueued before the newest price are executed. New operations
    //  have to wait until only one price is updated
    useMaxLastPublicationBlock: boolean;
    // coinbase micro liquidation execution fee. Paid from the micro liquidated bucket to the executor
    microLiquidationExecCost: bigint;
    // coinbase liquidation execution fee. Paid from the liquidated bucket to the executor
    liquidationExecCost: bigint;
    // address who receives all the coinbase execution fees
    coinbaseExecFeeRecipient: Address;
  };
  liquidationParams: {
    // bucket AC to coinbase price provider
    acCoinbasePriceProviderAddress: Address;
    // target coverage to reach during a micro liquidation [PREC]
    rtcThrld: bigint;
    // thrld_ to trigger the micro liquidation [PREC]
    microLiquidationThrld: bigint;
    // additional pct of AC sent to the target bucket during a micro liquidation [PREC]
    penaltyRate: bigint;
    // MocSwapper contracts for the originBucketAC / targetBucketAC pool
    mocSwappers: Address[];
  };
  // gas limit applied for each tx during deployment
  // Hardhat gas limit config cannot be used because we are using ethers.js library. https://github.com/NomicFoundation/hardhat/pull/2406
  gasLimit: number;
};
