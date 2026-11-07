import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { deployCARC20 } from "../../scripts/utils";

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  await deployCARC20(hre, "MocCARC20", "CollateralTokenCARC20");

  return hre.network.live; // prevents re execution on live networks
};
export default deployFunc;

deployFunc.id = "deployed_MocCARC20"; // id required to prevent re-execution
deployFunc.tags = ["MocCARC20"];
deployFunc.dependencies = ["CollateralTokenCARC20", "MocVendorsCARC20", "MocCARC20Expansion", "MocQueueCARC20"];
