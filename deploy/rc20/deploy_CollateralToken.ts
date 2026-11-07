import { DeployFunction } from "hardhat-deploy/types";
import { deployCollateralToken } from "../../scripts/utils";

const deployFunc: DeployFunction = deployCollateralToken("CollateralTokenCARC20");
export default deployFunc;

deployFunc.id = "deployed_CollateralTokenCARC20"; // id required to prevent re-execution
deployFunc.tags = ["CollateralTokenCARC20"];
