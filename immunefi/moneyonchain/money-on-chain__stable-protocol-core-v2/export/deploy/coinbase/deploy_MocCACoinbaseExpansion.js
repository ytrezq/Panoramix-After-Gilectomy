"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const utils_1 = require("../../scripts/utils");
const deployFunc = async (hre) => {
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;
    const gasLimit = (0, utils_1.getNetworkDeployParams)(hre).gasLimit;
    const deployImplResult = await deploy("MocCACoinbaseExpansion", {
        contract: "MocCoreExpansion",
        from: deployer,
        gasLimit,
    });
    console.log(`"MocCACoinbaseExpansion, as MocCoreExpansion implementation deployed at ${deployImplResult.address}`);
    return hre.network.live; // prevents re execution on live networks
};
exports.default = deployFunc;
deployFunc.id = "deployed_MocCACoinbaseExpansion"; // id required to prevent re-execution
deployFunc.tags = ["MocCACoinbaseExpansion"];
//# sourceMappingURL=deploy_MocCACoinbaseExpansion.js.map