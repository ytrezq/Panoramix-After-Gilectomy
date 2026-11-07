import { ContractTransactionReceipt, ContractTransactionResponse } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types/runtime";
import { Address } from "hardhat-deploy/types";
import { DeployParameters, TPParams } from "./types";
export declare const CONSTANTS: {
    ZERO_ADDRESS: string;
    MAX_UINT256: bigint;
    MAX_BALANCE: bigint;
    PRECISION: bigint;
    ONE: bigint;
    SWAP_FEE: bigint;
};
export declare const DEFAULT_ADMIN_ROLE: string;
export declare const MINTER_ROLE: string;
export declare const BURNER_ROLE: string;
export declare const noVendor: string;
export declare const waitForTxConfirmation: (tx: Promise<ContractTransactionResponse>, confirmations?: number) => Promise<null | ContractTransactionReceipt>;
export declare const deployUUPSArtifact: ({ hre, artifactBaseName, contract, initializeArgs, }: {
    hre: HardhatRuntimeEnvironment;
    artifactBaseName?: string;
    contract: string;
    initializeArgs?: any[];
}) => Promise<import("hardhat-deploy/dist/types").DeployResult>;
export declare const deployCollateralToken: (artifactBaseName: string) => (hre: HardhatRuntimeEnvironment) => Promise<boolean>;
export declare const deployQueue: (hre: HardhatRuntimeEnvironment, artifactBaseName: string, mocMultiCollateralGuard: Address) => Promise<import("hardhat-deploy/dist/types").DeployResult>;
export declare const deployMultiCollateralGuard: (artifactBaseName: string) => (hre: HardhatRuntimeEnvironment) => Promise<boolean>;
export declare const getGovernorAddresses: (hre: HardhatRuntimeEnvironment) => Promise<{
    governorAddress: string;
    interimGovernor: string;
}>;
export declare const deployVendors: (artifactBaseName: string) => (hre: HardhatRuntimeEnvironment) => Promise<boolean>;
export declare const getNetworkDeployParams: (hre: HardhatRuntimeEnvironment) => DeployParameters;
export declare const addMissingPriceProviders: ({ hre, tpParams, gasLimit, }: {
    hre: HardhatRuntimeEnvironment;
    tpParams: TPParams[];
    gasLimit: number;
}) => Promise<void>;
export declare const addPeggedTokens: (hre: HardhatRuntimeEnvironment, governorAddress: string, mocCore: any, tpParams: any) => Promise<void>;
export declare const deployCARC20: (hre: HardhatRuntimeEnvironment, mocCARC20Variant: string, ctVariant: string, extraInitParams?: {}) => Promise<void>;
export declare const deployCARC20With: (hre: HardhatRuntimeEnvironment, mocCARC20Variant: string, extraInitParams: {} | undefined, deployParameters: DeployParameters, tcTokenAddress: Address, mocQueueAddress: Address) => Promise<any>;
