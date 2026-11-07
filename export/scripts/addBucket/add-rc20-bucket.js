"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const hardhat_1 = require("hardhat");
const utils_1 = require("../utils");
const add_bucket_config_1 = require("./add-bucket.config");
// global scope, and execute the script.
const hre = require("hardhat");
async function main() {
    console.log(`Script: Add Bucket started`);
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    const signer = await hardhat_1.ethers.getSigner(deployer);
    const defaultDeployParams = (0, utils_1.getNetworkDeployParams)(hre);
    const addBucketParams = { ...defaultDeployParams, ...add_bucket_config_1.addBucketConfig };
    const { bucketId } = addBucketParams;
    const ctVariant = "CTCARC20" + bucketId;
    const queueVariant = "MocQueueCARC20" + bucketId;
    const mocCoreVariant = "MocCARC20" + bucketId;
    let mocMultiCollateralGuardAddress;
    if (!addBucketParams.mocMultiCollateralGuard) {
        const deployedMocMultiCollateralGuard = await deployments.getOrNull("MocMultiCollateralGuardCARC20Proxy");
        if (!deployedMocMultiCollateralGuard)
            throw new Error(`No deployedMocMultiCollateralGuard deployed.`);
        console.log("No mocMultiCollateralGuard provided, using deployment one:", deployedMocMultiCollateralGuard.address);
        mocMultiCollateralGuardAddress = deployedMocMultiCollateralGuard.address;
    }
    else {
        mocMultiCollateralGuardAddress = addBucketParams.mocMultiCollateralGuard;
    }
    await (0, utils_1.deployCollateralToken)(ctVariant)(hre);
    await (0, utils_1.deployQueue)(hre, queueVariant, mocMultiCollateralGuardAddress);
    const deployedTCContract = await deployments.getOrNull(ctVariant + "Proxy");
    if (!deployedTCContract)
        throw new Error(`No ${ctVariant} deployed.`);
    const deployedMocQueue = await deployments.getOrNull(queueVariant + "Proxy");
    if (!deployedMocQueue)
        throw new Error(`No ${queueVariant} deployed.`);
    const mocCARC20 = await (0, utils_1.deployCARC20With)(hre, mocCoreVariant, {}, addBucketParams, deployedTCContract.address, deployedMocQueue.address);
    const bucket0Deployment = await deployments.getOrNull("MocCARC20Proxy");
    if (!bucket0Deployment)
        throw new Error(`No MocCARC20Proxy deployed.`);
    const bucket0 = await hardhat_1.ethers.getContractAt("MocCARC20", bucket0Deployment.target.toString(), signer);
    const baseBucketTPAmount = await bucket0.getTpAmount();
    const mocCore = await hardhat_1.ethers.getContractAt("MocCARC20", mocCARC20.target.toString(), signer);
    const { tpParams, gasLimit } = add_bucket_config_1.addBucketConfig;
    for (let i = 0; i < Number(baseBucketTPAmount); i++) {
        const tpAddress = await bucket0.tpTokens(i);
        if (!tpParams || !tpParams.tpParams[i])
            throw new Error(`No params for the given TP ${i}, ${tpAddress}.`);
        await (0, utils_1.addMissingPriceProviders)({ hre, tpParams: tpParams.tpParams, gasLimit });
        console.log(`Adding existent TP ${tpAddress} to the new bucket`);
        await (0, utils_1.waitForTxConfirmation)(mocCore.addPeggedToken(tpAddress, {
            priceProviderAddress: tpParams.tpParams[i].priceProviderAddress,
            tpCtarg: tpParams.tpParams[i].tpCtarg,
            tpMintFee: tpParams.tpParams[i].tpMintFee,
            tpRedeemFee: tpParams.tpParams[i].tpRedeemFee,
            tpEma: tpParams.tpParams[i].tpEma,
            tpEmaSf: tpParams.tpParams[i].tpEmaSf,
        }, {
            gasLimit,
        }));
    }
    console.log(`Deploying AddBucket changer for mocMultiCollateralGuard: ${mocMultiCollateralGuardAddress} and bucket: ${mocCARC20.target.toString()}`);
    const addBucketChangerDeploy = await deployments.deploy("AddBucketChangerTemplate", {
        from: deployer,
        args: [mocMultiCollateralGuardAddress, mocCARC20.target.toString()],
        gasLimit,
    });
    const addBucketChanger = await hardhat_1.ethers.getContractAt("AddBucketChangerTemplate", addBucketChangerDeploy.target.toString(), signer);
    console.log(`Executing AddBucket changer`);
    await addBucketChanger.execute();
    console.log(`Script: Add Bucket completed`);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
//# sourceMappingURL=add-rc20-bucket.js.map