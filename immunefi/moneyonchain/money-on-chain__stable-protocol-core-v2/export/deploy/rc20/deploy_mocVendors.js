"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const utils_1 = require("../../scripts/utils");
const deployFunc = (0, utils_1.deployVendors)("MocVendorsCARC20");
exports.default = deployFunc;
deployFunc.id = "deployed_MocVendorsCARC20"; // id required to prevent re-execution
deployFunc.tags = ["MocVendorsCARC20"];
//# sourceMappingURL=deploy_mocVendors.js.map