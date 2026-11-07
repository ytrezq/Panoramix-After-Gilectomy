"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const utils_1 = require("../../scripts/utils");
const deployFunc = (0, utils_1.deployVendors)("MocVendorsCACoinbase");
exports.default = deployFunc;
deployFunc.id = "deployed_MocVendorsCACoinbase"; // id required to prevent re-execution
deployFunc.tags = ["MocVendorsCACoinbase"];
//# sourceMappingURL=deploy_mocVendors.js.map