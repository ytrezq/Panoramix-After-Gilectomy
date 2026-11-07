import { DeployFunction } from "hardhat-deploy/types";
import { deployVendors } from "../../scripts/utils";

const deployFunc: DeployFunction = deployVendors("MocVendorsCARC20");
export default deployFunc;

deployFunc.id = "deployed_MocVendorsCARC20"; // id required to prevent re-execution
deployFunc.tags = ["MocVendorsCARC20"];
