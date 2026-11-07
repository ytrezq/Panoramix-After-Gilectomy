import { DeployFunction } from "hardhat-deploy/types";
import { deployMultiCollateralGuard } from "../../scripts/utils";

const deployFunc: DeployFunction = deployMultiCollateralGuard("MocMultiCollateralGuardCoinbase");
export default deployFunc;

deployFunc.id = "deployed_MocMultiCollateralGuardCoinbase"; // id required to prevent re-execution
deployFunc.tags = ["MocMultiCollateralGuardCoinbase"];
