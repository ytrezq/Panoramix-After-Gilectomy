import { Address } from "hardhat-deploy/types";
import { DeployParameters } from "../types";
type AddBucketParams = Omit<DeployParameters, "mocAddresses"> & {
    bucketId: string;
    mocMultiCollateralGuard?: Address;
};
export declare const addBucketConfig: AddBucketParams;
export {};
