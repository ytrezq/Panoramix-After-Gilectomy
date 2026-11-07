import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployQueue } from "../../scripts/utils";

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const deployedMocMultiCollateralGuard = await hre.deployments.getOrNull("MocMultiCollateralGuardCARC20Proxy");
  if (!deployedMocMultiCollateralGuard) throw new Error("No MocMultiCollateralGuard deployed.");

  await deployQueue(hre, "MocQueueCARC20", deployedMocMultiCollateralGuard.address);
  return hre.network.live; // prevents re execution on live networks
};
export default deployFunc;

deployFunc.id = "deployed_MocQueueCARC20"; // id required to prevent re-execution
deployFunc.tags = ["MocQueueCARC20"];
deployFunc.dependencies = ["MocMultiCollateralGuardCARC20"];
