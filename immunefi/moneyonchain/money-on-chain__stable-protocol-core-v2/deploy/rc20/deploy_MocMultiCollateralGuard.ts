import { DeployFunction } from "hardhat-deploy/types";
import { deployMultiCollateralGuard } from "../../scripts/utils";

const deployFunc: DeployFunction = deployMultiCollateralGuard("MocMultiCollateralGuardCARC20");
export default deployFunc;

deployFunc.id = "deployed_MocMultiCollateralGuardCARC20"; // id required to prevent re-execution
deployFunc.tags = ["MocMultiCollateralGuardCARC20"];
