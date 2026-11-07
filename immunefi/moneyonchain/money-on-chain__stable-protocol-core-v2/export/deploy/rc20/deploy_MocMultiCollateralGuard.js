"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const utils_1 = require("../../scripts/utils");
const deployFunc = (0, utils_1.deployMultiCollateralGuard)("MocMultiCollateralGuardCARC20");
exports.default = deployFunc;
deployFunc.id = "deployed_MocMultiCollateralGuardCARC20"; // id required to prevent re-execution
deployFunc.tags = ["MocMultiCollateralGuardCARC20"];
//# sourceMappingURL=deploy_MocMultiCollateralGuard.js.map