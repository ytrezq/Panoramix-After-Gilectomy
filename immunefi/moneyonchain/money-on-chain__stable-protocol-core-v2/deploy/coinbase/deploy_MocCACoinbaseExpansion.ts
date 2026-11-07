import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getNetworkDeployParams } from "../../scripts/utils";

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;
  const gasLimit = getNetworkDeployParams(hre).gasLimit;
  const deployImplResult = await deploy("MocCACoinbaseExpansion", {
    contract: "MocCoreExpansion",
    from: deployer,
    gasLimit,
  });
  console.log(`"MocCACoinbaseExpansion, as MocCoreExpansion implementation deployed at ${deployImplResult.address}`);
  return hre.network.live; // prevents re execution on live networks
};
export default deployFunc;

deployFunc.id = "deployed_MocCACoinbaseExpansion"; // id required to prevent re-execution
deployFunc.tags = ["MocCACoinbaseExpansion"];
