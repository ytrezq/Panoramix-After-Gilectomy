import { DeployFunction } from "hardhat-deploy/types";
import { deployCollateralToken } from "../../scripts/utils";

const deployFunc: DeployFunction = deployCollateralToken("CollateralTokenCoinbase");
export default deployFunc;

deployFunc.id = "deployed_CollateralTokenCoinbase"; // id required to prevent re-execution
deployFunc.tags = ["CollateralTokenCoinbase"];
