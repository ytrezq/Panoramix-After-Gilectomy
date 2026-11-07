"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const utils_1 = require("../../scripts/utils");
const deployFunc = async (hre) => {
    const deployedMocMultiCollateralGuard = await hre.deployments.getOrNull("MocMultiCollateralGuardCoinbaseProxy");
    if (!deployedMocMultiCollateralGuard)
        throw new Error("No MocMultiCollateralGuard deployed.");
    await (0, utils_1.deployQueue)(hre, "MocQueueCoinbase", deployedMocMultiCollateralGuard.address);
    return hre.network.live; // prevents re execution on live networks
};
exports.default = deployFunc;
deployFunc.id = "deployed_MocQueueCoinbase"; // id required to prevent re-execution
deployFunc.tags = ["MocQueueCoinbase"];
deployFunc.dependencies = ["MocMultiCollateralGuardCoinbase"];
//# sourceMappingURL=deploy_MocQueue.js.map