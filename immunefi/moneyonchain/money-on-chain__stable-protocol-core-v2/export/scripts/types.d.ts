import { Address } from "hardhat-deploy/dist/types";
export type TPParams = {
    artifact?: string;
    name?: string;
    symbol?: string;
    decimals?: bigint;
    priceProviderAddress?: Address;
    tpCtarg: bigint;
    tpMintFee: bigint;
    tpRedeemFee: bigint;
    tpEma: bigint;
    tpEmaSf: bigint;
};
export type DeployParameters = {
    coreParams: {
        protThrld: bigint;
        liqThrld: bigint;
        emaCalculationTimeSpan: bigint;
        successFee: bigint;
        appreciationFactor: bigint;
        tcInterestRate: bigint;
        tcInterestPaymentTimeSpan: bigint;
        decayTimeSpan: bigint;
        transferMaxGas?: bigint;
        allowDifferentRecipient?: boolean;
    };
    settlementParams: {
        settlementTimeSpan: bigint;
    };
    vendorsParams: {
        maxMarkup: bigint;
    };
    feeParams: {
        feeRetainer: bigint;
        tcMintFee: bigint;
        tcRedeemFee: bigint;
        swapTPforTPFee: bigint;
        swapTPforTCFee: bigint;
        swapTCforTPFee: bigint;
        redeemTCandTPFee: bigint;
        mintTCandTPFee: bigint;
        feeTokenPct: bigint;
    };
    ctParams: {
        name: string;
        symbol: string;
        decimals?: bigint;
    };
    tpParams?: {
        tpParams: TPParams[];
    };
    mocAddresses: {
        collateralAssetAddress?: Address;
        governorAddress: Address;
        pauserAddress: Address;
        feeTokenAddress: Address;
        feeTokenPriceProviderAddress: Address;
        mocFeeFlowAddress: Address;
        mocAppreciationBeneficiaryAddress: Address;
        vendorsGuardianAddress: Address;
        tcInterestCollectorAddress: Address;
        maxAbsoluteOpProviderAddress: Address;
        maxOpDiffProviderAddress: Address;
    };
    queueParams: {
        minOperWaitingBlk: bigint;
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
        maxOperPerBatch: bigint;
        useMaxLastPublicationBlock: boolean;
        microLiquidationExecCost: bigint;
        liquidationExecCost: bigint;
        coinbaseExecFeeRecipient: Address;
    };
    liquidationParams: {
        acCoinbasePriceProviderAddress: Address;
        rtcThrld: bigint;
        microLiquidationThrld: bigint;
        penaltyRate: bigint;
        mocSwappers: Address[];
    };
    gasLimit: number;
};
