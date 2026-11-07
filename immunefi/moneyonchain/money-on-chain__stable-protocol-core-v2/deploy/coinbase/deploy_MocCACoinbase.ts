import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import {
  CONSTANTS,
  addPeggedTokens,
  deployUUPSArtifact,
  getGovernorAddresses,
  getNetworkDeployParams,
  waitForTxConfirmation,
  addMissingPriceProviders,
} from "../../scripts/utils";

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deployer, pauser } = await getNamedAccounts();
  const { coreParams, settlementParams, feeParams, tpParams, mocAddresses, liquidationParams, gasLimit } =
    getNetworkDeployParams(hre);
  const [signer] = await ethers.getSigners();

  const deployedMocExpansionContract = await deployments.getOrNull("MocCACoinbaseExpansion");
  if (!deployedMocExpansionContract) throw new Error("No MocCACoinbaseExpansion deployed.");

  const deployedTCContract = await deployments.getOrNull("CollateralTokenCoinbaseProxy");
  if (!deployedTCContract) throw new Error("No CollateralTokenCoinbaseProxy deployed.");
  const CollateralToken = await ethers.getContractAt("MocRC20", deployedTCContract.address, signer);

  const deployedMocVendors = await deployments.getOrNull("MocVendorsCACoinbaseProxy");
  if (!deployedMocVendors) throw new Error("No MocVendors deployed.");

  const deployedMocQueue = await deployments.getOrNull("MocQueueCoinbaseProxy");
  if (!deployedMocQueue) throw new Error("No MocQueue deployed.");

  const deployedMocMultiCollateralGuard = await deployments.getOrNull("MocMultiCollateralGuardCoinbaseProxy");
  if (!deployedMocMultiCollateralGuard) throw new Error("No MocMultiCollateralGuard deployed.");

  let {
    pauserAddress,
    feeTokenAddress,
    feeTokenPriceProviderAddress,
    mocFeeFlowAddress,
    mocAppreciationBeneficiaryAddress,
    tcInterestCollectorAddress,
    maxAbsoluteOpProviderAddress,
    maxOpDiffProviderAddress,
  } = mocAddresses;

  const { governorAddress, interimGovernor } = await getGovernorAddresses(hre);

  // for tests we deploy a FeeToken mock and its price provider
  if (hre.network.tags.testing) {
    const rc20MockFactory = await ethers.getContractFactory("ERC20Mock");
    feeTokenAddress = (await rc20MockFactory.deploy()).target.toString();

    const priceProviderMockFactory = await ethers.getContractFactory("PriceProviderMock");
    feeTokenPriceProviderAddress = (await priceProviderMockFactory.deploy(ethers.parseEther("1"))).target.toString();

    const DataProviderMockFactory = await ethers.getContractFactory("DataProviderMock");
    maxAbsoluteOpProviderAddress = (await DataProviderMockFactory.deploy(CONSTANTS.MAX_UINT256)).target.toString();
    maxOpDiffProviderAddress = (await DataProviderMockFactory.deploy(CONSTANTS.MAX_UINT256)).target.toString();
    // While testing, we use pauser account
    pauserAddress = pauser;
  }

  const mocCACoinbase = await deployUUPSArtifact({
    hre,
    contract: "MocCACoinbase",
    initializeArgs: [
      {
        initializeCoreParams: {
          initializeBaseBucketParams: {
            mocQueueAddress: deployedMocQueue.address,
            feeTokenAddress,
            feeTokenPriceProviderAddress,
            tcTokenAddress: CollateralToken.target.toString(),
            mocFeeFlowAddress,
            mocAppreciationBeneficiaryAddress,
            protThrld: coreParams.protThrld,
            liqThrld: coreParams.liqThrld,
            operationsFeeParams: {
              feeRetainer: feeParams.feeRetainer,
              tcMintFee: feeParams.tcMintFee,
              tcRedeemFee: feeParams.tcRedeemFee,
              swapTPforTPFee: feeParams.swapTPforTPFee,
              swapTPforTCFee: feeParams.swapTPforTCFee,
              swapTCforTPFee: feeParams.swapTCforTPFee,
              redeemTCandTPFee: feeParams.redeemTCandTPFee,
              mintTCandTPFee: feeParams.mintTCandTPFee,
              feeTokenPct: feeParams.feeTokenPct,
            },
            successFee: coreParams.successFee,
            appreciationFactor: coreParams.appreciationFactor,
            settlementTimeSpan: settlementParams.settlementTimeSpan,
            tcInterestCollectorAddress,
            tcInterestRate: coreParams.tcInterestRate,
            tcInterestPaymentTimeSpan: coreParams.tcInterestPaymentTimeSpan,
            maxAbsoluteOpProviderAddress,
            maxOpDiffProviderAddress,
            decayTimeSpan: coreParams.decayTimeSpan,
            allowDifferentRecipient: coreParams.allowDifferentRecipient,
          },
          governorAddress: tpParams ? interimGovernor : governorAddress, // use interimGovernor to add TPs
          pauserAddress,
          mocCoreExpansion: deployedMocExpansionContract.address,
          emaCalculationTimeSpan: coreParams.emaCalculationTimeSpan,
          mocVendors: deployedMocVendors.address,
        },
        transferMaxGas: coreParams.transferMaxGas,
      },
    ],
  });

  console.log("Delegating CT roles to Moc");
  // Assign TC Roles, and renounce deployer ADMIN
  await waitForTxConfirmation(CollateralToken.transferAllRoles(mocCACoinbase.address));

  console.log("initialization completed!");

  // Governor is mocked, and we can:
  // - add pegged tokens
  // - register the bucket on the queue
  // - register the bucket on the multicollateralGuard
  const mocCore = await ethers.getContractAt("MocCACoinbase", mocCACoinbase.address, signer);
  if (tpParams) {
    await addMissingPriceProviders({ hre, tpParams: tpParams.tpParams, gasLimit });
    await addPeggedTokens(hre, governorAddress, mocCore, tpParams);
    console.log(`[ATTENTION] Changing governor for MocCore. Governor address: ${governorAddress}`);
    await waitForTxConfirmation(mocCore.changeGovernor(governorAddress));
  }

  const mocQueue = await ethers.getContractAt("MocQueue", deployedMocQueue.address, signer);
  console.log(`Registering mocCoinbase bucket as enqueuer: ${mocCACoinbase.address}`);
  await mocQueue.registerBucket(mocCACoinbase.address);

  const mocMultiCollateralGuard = await ethers.getContractAt(
    "MocMultiCollateralGuard",
    deployedMocMultiCollateralGuard.address,
    signer,
  );

  let acCoinbasePriceProviderAddress = liquidationParams.acCoinbasePriceProviderAddress;
  // for tests we deploy a AC coinbase and max AC to swap mocked providers
  if (hre.network.tags.testing) {
    const deploy = async (artifact: string, contract: string, args?: any[]) => {
      const deployedArtifact = await deployments.deploy(artifact, {
        contract,
        from: deployer,
        gasLimit,
        args,
      });
      console.log(`[ONLY TESTING] ${artifact} deployed to: ${deployedArtifact.address}`);
      return deployedArtifact.address;
    };
    acCoinbasePriceProviderAddress = await deploy("ACCoinbasePriceProviderMock", "PriceProviderMock", [
      ethers.parseEther("1"),
    ]);
  }

  await waitForTxConfirmation(
    mocMultiCollateralGuard.addBucket(
      mocCACoinbase.address,
      {
        acCoinbasePriceProvider: acCoinbasePriceProviderAddress,
        rebalanceExecFeeRecipient: await ethers.Wallet.createRandom(),
        rtcThrld: liquidationParams.rtcThrld,
        microLiquidationThrld: liquidationParams.microLiquidationThrld,
        penaltyRate: liquidationParams.penaltyRate,
      },
      [], // mocSwappers array, empty because it's the first bucket
    ),
  );

  console.log(
    `[ATTENTION] Changing governor for MocQueue and MocMultiCollateralGuard. Governor address: ${governorAddress}`,
  );
  await waitForTxConfirmation(mocQueue.changeGovernor(governorAddress));
  await waitForTxConfirmation(mocMultiCollateralGuard.changeGovernor(governorAddress));

  return hre.network.live; // prevents re execution on live networks
};
export default deployFunc;

deployFunc.id = "deployed_MocCACoinbase"; // id required to prevent re-execution
deployFunc.tags = ["MocCACoinbase"];
deployFunc.dependencies = [
  "CollateralTokenCoinbase",
  "MocVendorsCACoinbase",
  "MocCACoinbaseExpansion",
  "MocQueueCoinbase",
];
