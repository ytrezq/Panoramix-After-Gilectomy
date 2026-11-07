import { expect } from "chai";
import hre, { deployments, ethers } from "hardhat";
import {
  MocCARC20,
  MocCoreExpansion,
  MocCARC20__factory,
  MocRC20,
  MocVendors,
  ERC20Mock,
  MocQueue,
  MocMultiCollateralGuard,
} from "../../typechain";
import { ERRORS, mocInitialize, timedDescribe, getNetworkDeployParams, getGovernorAddresses } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "../rc20/fixture";
import { fixtureDeployedMocCoinbase } from "../coinbase/fixture";

timedDescribe("Feature: MocCARC20 initialization", function () {
  let mocProxy: MocCARC20;
  let collateralAsset: ERC20Mock;
  let mocCollateralToken: MocRC20;
  let mocPeggedTokens: MocRC20[];
  let mocInit: any;
  let mocCoreExpansion: MocCoreExpansion;
  let mocVendors: MocVendors;
  let mocQueue: MocQueue;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  const { queueParams, vendorsParams, mocAddresses } = getNetworkDeployParams(hre);
  before(async () => {
    ({
      mocImpl: mocProxy,
      mocCoreExpansion,
      mocCollateralToken,
      collateralAsset,
      mocVendors,
      mocQueue,
      mocPeggedTokens,
      mocMultiCollateralGuard,
    } = await fixtureDeployedMocRC20(1)());

    mocAddresses.governorAddress = (await getGovernorAddresses(hre)).governorAddress;

    mocInit = mocInitialize(
      mocProxy,
      mocCollateralToken.target.toString(),
      mocCoreExpansion.target.toString(),
      mocVendors.target.toString(),
      mocQueue.target.toString(),
      { acTokenAddress: collateralAsset.target.toString() },
    );
  });
  describe("GIVEN a MocCARC20 implementation deployed", () => {
    describe("WHEN initialize mocProxy again", async () => {
      it("THEN tx fails because contract is already initialized", async () => {
        await expect(mocInit()).to.be.revertedWith(ERRORS.CONTRACT_INITIALIZED);
      });
    });
    describe("WHEN initialize the moc implementation", async () => {
      let mocImplementation: MocCARC20;
      it("THEN tx fails because contract is already initialized", async () => {
        const [signer] = await ethers.getSigners();
        mocImplementation = MocCARC20__factory.connect(
          (await deployments.get("MocCARC20Proxy")).implementation!,
          signer,
        );
        await expect(
          mocInitialize(
            mocImplementation,
            mocCollateralToken.target.toString(),
            mocCoreExpansion.target.toString(),
            mocVendors.target.toString(),
            mocQueue.target.toString(),
            { acTokenAddress: collateralAsset.target.toString() },
          )(),
        ).to.be.revertedWith(ERRORS.CONTRACT_INITIALIZED);
      });
    });
    describe("WHEN initialize mocVendorsProxy again", async () => {
      it("THEN tx fails because contract is already initialized", async () => {
        await expect(
          mocVendors.initialize(
            mocAddresses.vendorsGuardianAddress,
            mocAddresses.governorAddress,
            mocAddresses.pauserAddress,
            vendorsParams.maxMarkup,
          ),
        ).to.be.revertedWith(ERRORS.CONTRACT_INITIALIZED);
      });
    });
    describe("WHEN initialize mocQueueProxy again", async () => {
      it("THEN tx fails because contract is already initialized", async () => {
        await expect(
          mocQueue.initialize(
            mocAddresses.governorAddress,
            mocAddresses.pauserAddress,
            mocMultiCollateralGuard.target.toString(),
            queueParams.minOperWaitingBlk,
            queueParams.maxOperWaitingBlk,
            queueParams.execCostParams,
          ),
        ).to.be.revertedWith(ERRORS.CONTRACT_INITIALIZED);
      });
    });
    describe("WHEN initialize mocTC again", async () => {
      it("THEN tx fails because contract is already initialized", async () => {
        await expect(
          mocCollateralToken.initialize("TC", "TC", mocAddresses.governorAddress, mocAddresses.governorAddress),
        ).to.be.revertedWith(ERRORS.CONTRACT_INITIALIZED);
      });
    });
    describe("WHEN initialize mocRC20 again", async () => {
      it("THEN tx fails because contract is already initialized", async () => {
        await expect(
          mocPeggedTokens[0].initialize("TP", "TP", mocAddresses.governorAddress, mocAddresses.governorAddress),
        ).to.be.revertedWith(ERRORS.CONTRACT_INITIALIZED);
      });
    });
  });

  describe("GIVEN a MocCACoinbase implementation deployed", () => {
    describe("WHEN initialize mocProxy again", async () => {
      it("THEN tx fails because contract is already initialized", async () => {
        const { mocImpl } = await fixtureDeployedMocCoinbase(0)();
        const mocInit = mocInitialize(
          mocImpl,
          mocCollateralToken.target.toString(),
          mocCoreExpansion.target.toString(),
          mocVendors.target.toString(),
          mocQueue.target.toString(),
          { transferMaxGas: 0n },
        );
        await expect(mocInit()).to.be.revertedWith(ERRORS.CONTRACT_INITIALIZED);
      });
    });
  });
});
