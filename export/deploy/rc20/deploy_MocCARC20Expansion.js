"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const utils_1 = require("../../scripts/utils");
const deployFunc = async (hre) => {
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;
    const gasLimit = (0, utils_1.getNetworkDeployParams)(hre).gasLimit;
    const deployImplResult = await deploy("MocCARC20Expansion", {
        contract: "MocCoreExpansion",
        from: deployer,
        gasLimit,
    });
    console.log(`"MocCARC20Expansion, as MocCoreExpansion implementation deployed at ${deployImplResult.address}`);
    return hre.network.live; // prevents re execution on live networks
};
exports.default = deployFunc;
deployFunc.id = "deployed_MocCARC20Expansion"; // id required to prevent re-execution
deployFunc.tags = ["MocCARC20Expansion"];
//# sourceMappingURL=deploy_MocCARC20Expansion.js.map