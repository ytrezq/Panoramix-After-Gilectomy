import { DeployFunction } from "hardhat-deploy/types";
import { deployVendors } from "../../scripts/utils";

const deployFunc: DeployFunction = deployVendors("MocVendorsCACoinbase");
export default deployFunc;

deployFunc.id = "deployed_MocVendorsCACoinbase"; // id required to prevent re-execution
deployFunc.tags = ["MocVendorsCACoinbase"];
