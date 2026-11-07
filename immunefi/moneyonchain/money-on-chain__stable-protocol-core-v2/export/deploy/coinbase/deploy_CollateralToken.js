"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const utils_1 = require("../../scripts/utils");
const deployFunc = (0, utils_1.deployCollateralToken)("CollateralTokenCoinbase");
exports.default = deployFunc;
deployFunc.id = "deployed_CollateralTokenCoinbase"; // id required to prevent re-execution
deployFunc.tags = ["CollateralTokenCoinbase"];
//# sourceMappingURL=deploy_CollateralToken.js.map