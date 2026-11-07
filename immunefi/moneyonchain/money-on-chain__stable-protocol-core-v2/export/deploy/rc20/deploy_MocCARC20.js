"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const utils_1 = require("../../scripts/utils");
const deployFunc = async (hre) => {
    await (0, utils_1.deployCARC20)(hre, "MocCARC20", "CollateralTokenCARC20");
    return hre.network.live; // prevents re execution on live networks
};
exports.default = deployFunc;
deployFunc.id = "deployed_MocCARC20"; // id required to prevent re-execution
deployFunc.tags = ["MocCARC20"];
deployFunc.dependencies = ["CollateralTokenCARC20", "MocVendorsCARC20", "MocCARC20Expansion", "MocQueueCARC20"];
//# sourceMappingURL=deploy_MocCARC20.js.map