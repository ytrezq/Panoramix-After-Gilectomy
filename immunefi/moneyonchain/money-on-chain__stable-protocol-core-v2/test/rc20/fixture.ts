import { deployments, getNamedAccounts } from "hardhat";
import memoizee from "memoizee";
import {
  ERC20Mock,
  ERC20Mock__factory,
  MocCARC20,
  MocCARC20__factory,
  MocQueue,
  MocQueue__factory,
  MocRC20,
  MocRC20__factory,
  MocVendors,
  MocVendors__factory,
  PriceProviderMock,
  PriceProviderMock__factory,
  DataProviderMock,
  DataProviderMock__factory,
  MocCoreExpansion,
  MocCoreExpansion__factory,
  MocMultiCollateralGuard,
  MocMultiCollateralGuard__factory,
} from "../../typechain";
import { deployAndAddPeggedTokens, pEth, deployMocQueue, time } from "../helpers/utils";

export type MoCRC20Contracts = {
  mocImpl: MocCARC20;
  mocCollateralToken: MocRC20;
  mocPeggedTokens: MocRC20[];
  priceProviders: PriceProviderMock[];
  collateralAsset: ERC20Mock;
  mocCoreExpansion: MocCoreExpansion;
  mocVendors: MocVendors;
  feeToken: ERC20Mock;
  feeTokenPriceProvider: PriceProviderMock;
  mocQueue: MocQueue;
  mocMultiCollateralGuard: MocMultiCollateralGuard;
  maxAbsoluteOpProvider: DataProviderMock;
  maxOpDiffProvider: DataProviderMock;
};

export const fixtureDeployedMocRC20 = memoizee(
  (
    amountPegTokens: number,
    tpParams?: any,
    queueContract?: "MocQueue" | "MocQueueMock" | "MocQueueBasefeeMock",
  ): (() => Promise<MoCRC20Contracts>) => {
    return deployments.createFixture(async ({ ethers }) => {
      await deployments.fixture();
      const [signer] = await ethers.getSigners();

      const deployedMocContract = await deployments.getOrNull("MocCARC20Proxy");
      if (!deployedMocContract) throw new Error("No MocCARC20Proxy deployed.");
      const mocImpl: MocCARC20 = MocCARC20__factory.connect(deployedMocContract.address, signer);

      const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
      if (!deployedMocExpansionContract) throw new Error("No MocCARC20Expansion deployed.");
      const mocCoreExpansion: MocCoreExpansion = MocCoreExpansion__factory.connect(
        deployedMocExpansionContract.address,
        signer,
      );

      const deployedMocMultiCollateralGuard = await deployments.getOrNull("MocMultiCollateralGuardCARC20Proxy");
      if (!deployedMocMultiCollateralGuard) throw new Error("No MocMultiCollateralGuard deployed.");
      const mocMultiCollateralGuard: MocMultiCollateralGuard = MocMultiCollateralGuard__factory.connect(
        deployedMocMultiCollateralGuard.address,
        signer,
      );
      const mocVendors: MocVendors = MocVendors__factory.connect(await mocImpl.mocVendors(), signer);
      const mocCollateralToken: MocRC20 = MocRC20__factory.connect(await mocImpl.tcToken(), signer);
      const collateralAsset: ERC20Mock = ERC20Mock__factory.connect(await mocImpl.acToken(), signer);
      let mocQueue: MocQueue;

      const { alice, bob, charlie, vendor } = await getNamedAccounts();

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

      // Fill users accounts with balance so that they can operate
      await Promise.all([alice, bob, charlie].map(address => collateralAsset.mint(address, pEth(1000000000000))));

      // initialize vendor with 10% markup
      await mocVendors.setVendorMarkup(vendor, pEth(0.1));
      await time.increase(await mocVendors.COOLDOWN());

      const { mocPeggedTokens, priceProviders } = await deployAndAddPeggedTokens(mocImpl, amountPegTokens, tpParams);

      const feeToken = ERC20Mock__factory.connect(await mocImpl.feeToken(), signer);
      const feeTokenPriceProvider = PriceProviderMock__factory.connect(await mocImpl.feeTokenPriceProvider(), signer);
      const maxAbsoluteOpProvider = DataProviderMock__factory.connect(await mocImpl.maxAbsoluteOpProvider(), signer);
      const maxOpDiffProvider = DataProviderMock__factory.connect(await mocImpl.maxOpDiffProvider(), signer);

      return {
        mocImpl,
        mocCollateralToken,
        mocPeggedTokens,
        priceProviders,
        collateralAsset,
        mocCoreExpansion,
        mocVendors,
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
