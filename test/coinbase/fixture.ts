import { deployments, getNamedAccounts } from "hardhat";
import memoizee from "memoizee";
import {
  ERC20Mock,
  ERC20Mock__factory,
  MocCACoinbase,
  MocCACoinbase__factory,
  MocRC20,
  MocRC20__factory,
  MocVendors,
  MocVendors__factory,
  PriceProviderMock,
  PriceProviderMock__factory,
  DataProviderMock,
  DataProviderMock__factory,
  MocQueue,
  MocQueue__factory,
  MocMultiCollateralGuard,
  MocMultiCollateralGuard__factory,
} from "../../typechain";
import { deployAndAddPeggedTokens, pEth, deployMocQueue, time } from "../helpers/utils";

export type MoCCoinbaseContracts = {
  mocImpl: MocCACoinbase;
  mocCollateralToken: MocRC20;
  mocPeggedTokens: MocRC20[];
  priceProviders: PriceProviderMock[];
  feeToken: ERC20Mock;
  feeTokenPriceProvider: PriceProviderMock;
  mocQueue: MocQueue;
  mocMultiCollateralGuard: MocMultiCollateralGuard;
  maxAbsoluteOpProvider: DataProviderMock;
  maxOpDiffProvider: DataProviderMock;
};
export const fixtureDeployedMocCoinbase = memoizee(
  (
    amountPegTokens: number,
    tpParams?: any,
    queueContract?: "MocQueue" | "MocQueueMock" | "MocQueueBasefeeMock",
  ): (() => Promise<MoCCoinbaseContracts>) => {
    return deployments.createFixture(async ({ ethers }) => {
      await deployments.fixture();
      const [signer] = await ethers.getSigners();

      const deployedMocContract = await deployments.getOrNull("MocCACoinbaseProxy");
      if (!deployedMocContract) throw new Error("No MocCACoinbase deployed.");
      const mocImpl: MocCACoinbase = MocCACoinbase__factory.connect(deployedMocContract.address, signer);

      const deployedTCContract = await deployments.getOrNull("CollateralTokenCoinbaseProxy");
      if (!deployedTCContract) throw new Error("No CollateralTokenCoinbaseProxy deployed.");
      const mocCollateralToken: MocRC20 = MocRC20__factory.connect(deployedTCContract.address, signer);

      const { mocPeggedTokens, priceProviders } = await deployAndAddPeggedTokens(mocImpl, amountPegTokens, tpParams);

      const feeToken = ERC20Mock__factory.connect(await mocImpl.feeToken(), signer);
      const feeTokenPriceProvider = PriceProviderMock__factory.connect(await mocImpl.feeTokenPriceProvider(), signer);

      const maxAbsoluteOpProvider = DataProviderMock__factory.connect(await mocImpl.maxAbsoluteOpProvider(), signer);
      const maxOpDiffProvider = DataProviderMock__factory.connect(await mocImpl.maxOpDiffProvider(), signer);

      const deployedMocVendors = await deployments.getOrNull("MocVendorsCACoinbaseProxy");
      if (!deployedMocVendors) throw new Error("No MocVendors deployed.");
      const mocVendors: MocVendors = MocVendors__factory.connect(deployedMocVendors.address, signer);

      const deployedMocMultiCollateralGuard = await deployments.getOrNull("MocMultiCollateralGuardCoinbaseProxy");
      if (!deployedMocMultiCollateralGuard) throw new Error("No MocMultiCollateralGuard deployed.");
      const mocMultiCollateralGuard: MocMultiCollateralGuard = MocMultiCollateralGuard__factory.connect(
        deployedMocMultiCollateralGuard.address,
        signer,
      );

      // initialize vendor with 10% markup
      const { vendor } = await getNamedAccounts();

      let mocQueue: MocQueue;
      // MocQueueBasefeeMock is the default Queue for testing environments
      if (queueContract && queueContract != "MocQueueBasefeeMock") {
        mocQueue = await deployMocQueue({
          contractName: queueContract,
          mocMultiCollateralGuardAddress: deployedMocMultiCollateralGuard.address,
        });
        await Promise.all([
          mocImpl.setMocQueue(mocQueue.target.toString()),
          mocQueue.registerBucket(mocImpl.target.toString()),
        ]);
      } else {
        mocQueue = MocQueue__factory.connect(await mocImpl.mocQueue(), signer);
      }

      // initialize vendor with 10% markup
      await mocVendors.setVendorMarkup(vendor, pEth(0.1));
      await time.increase(await mocVendors.COOLDOWN());

      return {
        mocImpl,
        mocCollateralToken,
        mocPeggedTokens,
        priceProviders,
        feeToken,
        feeTokenPriceProvider,
        mocQueue,
        mocMultiCollateralGuard,
        maxAbsoluteOpProvider,
        maxOpDiffProvider,
      };
    });
  },
);
