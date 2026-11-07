"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const utils_1 = require("../../scripts/utils");
const deployFunc = (0, utils_1.deployMultiCollateralGuard)("MocMultiCollateralGuardCoinbase");
exports.default = deployFunc;
deployFunc.id = "deployed_MocMultiCollateralGuardCoinbase"; // id required to prevent re-execution
deployFunc.tags = ["MocMultiCollateralGuardCoinbase"];
//# sourceMappingURL=deploy_MocMultiCollateralGuard.js.map