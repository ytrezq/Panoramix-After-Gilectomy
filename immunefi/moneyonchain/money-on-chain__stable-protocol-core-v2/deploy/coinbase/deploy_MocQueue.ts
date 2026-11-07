import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployQueue } from "../../scripts/utils";

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const deployedMocMultiCollateralGuard = await hre.deployments.getOrNull("MocMultiCollateralGuardCoinbaseProxy");
  if (!deployedMocMultiCollateralGuard) throw new Error("No MocMultiCollateralGuard deployed.");

  await deployQueue(hre, "MocQueueCoinbase", deployedMocMultiCollateralGuard.address);
  return hre.network.live; // prevents re execution on live networks
};
export default deployFunc;

deployFunc.id = "deployed_MocQueueCoinbase"; // id required to prevent re-execution
deployFunc.tags = ["MocQueueCoinbase"];
deployFunc.dependencies = ["MocMultiCollateralGuardCoinbase"];
