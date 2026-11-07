import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { fixtureDeployedMulticollateral } from "../../multicollateral/fixture";
import {
  AddBucketChangerTemplate,
  IGovernor,
  MocCARC20,
  MocMultiCollateralGuard,
  MocQueue,
  MocRC20,
} from "../../../typechain";
import {
  ERRORS,
  pEth,
  tpParams,
  deployAeropagusGovernor,
  deployBucket,
  deployAndAddPeggedTokens,
  CONSTANTS,
} from "../../helpers/utils";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";

const deployChanger = async (
  mocMultiCollateralGuard: MocMultiCollateralGuard,
  newBucketAddress: Address,
): Promise<AddBucketChangerTemplate> => {
  const baseBucket = await mocMultiCollateralGuard.buckets(0);
  const mocSwapper = await mocMultiCollateralGuard.mocSwappers(baseBucket, await mocMultiCollateralGuard.buckets(1));
  // use same liquidation params for all the buckets
  const liqParams = {
    acCoinbasePriceProvider: await mocMultiCollateralGuard.acCoinbasePriceProvider(baseBucket),
    rebalanceExecFeeRecipient: await mocMultiCollateralGuard.rebalanceExecFeeRecipient(baseBucket),
    rtcThrld: await mocMultiCollateralGuard.rtcThrld(baseBucket),
    microLiquidationThrld: await mocMultiCollateralGuard.microLiquidationThrld(baseBucket),
    penaltyRate: await mocMultiCollateralGuard.penaltyRate(baseBucket),
  };
  const mocSwappers = Array(Number(await mocMultiCollateralGuard.getBucketAmount())).fill(mocSwapper);
  const changerFactory = await ethers.getContractFactory("AddBucketChangerTemplate");
  return changerFactory.deploy(mocMultiCollateralGuard.target.toString(), newBucketAddress, liqParams, mocSwappers);
};

describe("Feature: Governance protected RC20 Bucket addition", () => {
  async function fixture() {
    return fixtureDeployedMulticollateral(tpParams.length, tpParams);
  }
  let mocContracts: any;
  let buckets = new Array<any>(3);
  let mocFunctions = new Array<any>(3);
  let mocPeggedTokens: MocRC20[];
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let governorMockAddress: Address;
  let governor: IGovernor;
  let deployer: Address;
  let pauser: Address;
  let alice: Address;
  before(async () => {
    ({ deployer, alice, pauser } = await getNamedAccounts());
    mocContracts = await loadFixture(fixture);
    mocFunctions[0] = await mocFunctionsRC20({ ...mocContracts.mocBucketContracts[0], ...mocContracts });
    mocFunctions[1] = await mocFunctionsCoinbase({ ...mocContracts.mocBucketContracts[1], ...mocContracts });

    ({ mocMultiCollateralGuard, mocBucketContracts: buckets, mocPeggedTokens } = mocContracts);
    governorMockAddress = await mocMultiCollateralGuard.governor();
    // set a real governor
    governor = await deployAeropagusGovernor(deployer);

    await Promise.all(
      [...buckets.map(it => it.mocImpl), ...mocPeggedTokens, mocMultiCollateralGuard].map(it =>
        it.changeGovernor(governor.target.toString()),
      ),
    );
    // Operate on the protocol to have some balances on it
    await Promise.all(mocFunctions.map(fncs => fncs.mintTC({ from: alice, qTC: 10, execute: false })));
    await Promise.all(mocFunctions.map(fncs => fncs.mintTP({ from: alice, qTP: 10, execute: false })));
    await mocFunctions[0].executeQueue();
  });
  describe("AND a new valid bucket is ready to be added", () => {
    let changeContract: any;
    let newBucketQueue: MocQueue;
    before(async () => {
      const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
      if (!deployedMocExpansionContract) throw new Error("No MocCARC20Expansion deployed.");
      const {
        mocCARC20: newBucket,
        acToken,
        tcToken,
        mocQueue,
      } = await deployBucket({
        governorAddress: governorMockAddress, //Deploy with mock, to be able to add TPs
        mocCoreExpansionAddress: deployedMocExpansionContract.address,
        mocMultiCollateralGuardAddress: mocMultiCollateralGuard.target.toString(),
        mocVendorsAddress: mocContracts.mocVendors.target.toString(),
        feeTokenAddress: mocContracts.feeToken.target.toString(),
        feeTokenPriceProviderAddress: mocContracts.feeTokenPriceProvider.target.toString(),
      });
      newBucketQueue = mocQueue;
      await newBucketQueue.connect(await ethers.getSigner(pauser)).pause();
      // Role assignment is done on the Changer, as we are not using mocked Governor
      const assignRoles = false;
      await deployAndAddPeggedTokens(newBucket, tpParams.length, tpParams, mocPeggedTokens, assignRoles);
      // Re-assign correct governor
      await newBucket.changeGovernor(governor.target.toString());
      await newBucketQueue.changeGovernor(governor.target.toString());

      changeContract = await deployChanger(mocMultiCollateralGuard, newBucket.target.toString());
      buckets[2] = newBucket;
      mocFunctions[2] = await mocFunctionsRC20({
        mocImpl: newBucket,
        mocCollateralToken: tcToken,
        collateralAsset: acToken,
        mocPeggedTokens,
        mocMultiCollateralGuard,
        priceProviders: mocContracts.priceProviders,
      });
    });
    it("THEN trying to queue on the bucket fails as it is paused", async function () {
      await expect(mocFunctions[2].mintTC({ from: alice, qTC: 10, execute: false })).to.be.revertedWithCustomError(
        newBucketQueue,
        ERRORS.NOT_WHEN_PAUSED,
      );
    });
    describe("WHEN the governor executes the changer", () => {
      let execTx: ContractTransactionResponse;
      let prevBucketAmount: bigint;
      let mocSwapper: Address;
      before(async () => {
        prevBucketAmount = await mocMultiCollateralGuard.getBucketAmount();
        execTx = await governor.executeChange(changeContract.target.toString());
        mocSwapper = await mocMultiCollateralGuard.mocSwappers(
          await mocMultiCollateralGuard.buckets(0),
          await mocMultiCollateralGuard.buckets(1),
        );
      });
      it("THEN the new bucket is added", async function () {
        const newBucketAddress = buckets[2].target.toString();
        const liqParams = {
          acCoinbasePriceProvider: await mocMultiCollateralGuard.acCoinbasePriceProvider(newBucketAddress),
          rebalanceExecFeeRecipient: await mocMultiCollateralGuard.rebalanceExecFeeRecipient(newBucketAddress),
          rtcThrld: await mocMultiCollateralGuard.rtcThrld(newBucketAddress),
          microLiquidationThrld: await mocMultiCollateralGuard.microLiquidationThrld(newBucketAddress),
          penaltyRate: await mocMultiCollateralGuard.penaltyRate(newBucketAddress),
        };
        const mocSwappers = Array(2).fill(mocSwapper);
        await expect(execTx)
          .to.emit(mocMultiCollateralGuard, "BucketChange")
          .withArgs(prevBucketAmount, newBucketAddress, Object.values(liqParams), mocSwappers);
      });
      it("THEN all buckets relations have the MocSwapper set", async function () {
        const bucketAmounts = await mocMultiCollateralGuard.getBucketAmount();
        for (let i = 0; i < bucketAmounts; i++) {
          for (let j = 0; j < bucketAmounts; j++) {
            if (i != j) {
              expect(
                await mocMultiCollateralGuard.mocSwappers(
                  await mocMultiCollateralGuard.buckets(i),
                  await mocMultiCollateralGuard.buckets(j),
                ),
              ).to.be.equal(mocSwapper);
            }
          }
        }
      });
      it("THEN getBucketAmount is increased", async function () {
        expect(prevBucketAmount + 1n).to.be.equal(await mocMultiCollateralGuard.getBucketAmount());
      });
      it("THEN alice can Operate on the bucket normally", async function () {
        const prevTPBalance = await mocFunctions[0].tpBalanceOf(0, alice);
        await Promise.all(mocFunctions.map(fncs => fncs.mintTC({ from: alice, qTC: 3, execute: false })));
        await Promise.all(mocFunctions.map(fncs => fncs.mintTP({ from: alice, qTP: 2, execute: false })));
        await mocFunctions[0].executeQueue();
        expect(await mocFunctions[2].tcBalanceOf(alice)).to.be.equal(pEth(3));
        // 3 Buckets x 2 TPs = +6
        expect(await mocFunctions[0].tpBalanceOf(0, alice)).to.be.equal(prevTPBalance + pEth(6));
      });
    });
  });
  describe("WHEN a changer for a duplicated bucket is settled up", () => {
    let extraChanger: any;
    let newBucketQueue: MocQueue;
    before(async () => {
      const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
      if (!deployedMocExpansionContract) throw new Error("No MocCARC20Expansion deployed.");
      const { mocCARC20: newBucket, mocQueue } = await deployBucket({
        governorAddress: governorMockAddress, //Deploy with mock, to be able to add TPs
        mocCoreExpansionAddress: deployedMocExpansionContract.address,
        mocMultiCollateralGuardAddress: mocMultiCollateralGuard.target.toString(),
        mocVendorsAddress: mocContracts.mocVendors.target.toString(),
        feeTokenAddress: mocContracts.feeToken.target.toString(),
        feeTokenPriceProviderAddress: mocContracts.feeTokenPriceProvider.target.toString(),
      });
      newBucketQueue = mocQueue;
      await newBucketQueue.connect(await ethers.getSigner(pauser)).pause();
      // Role assignment is done on the Changer, as we are not using mocked Governor
      const assignRoles = false;
      await deployAndAddPeggedTokens(newBucket, tpParams.length, tpParams, mocPeggedTokens, assignRoles);
      // Re-assign correct governor
      await newBucket.changeGovernor(governor.target.toString());
      await newBucketQueue.changeGovernor(governor.target.toString());

      const changeContract = await deployChanger(mocMultiCollateralGuard, newBucket.target.toString());
      // Add bucket one time
      await governor.executeChange(changeContract.target.toString());

      await newBucketQueue.connect(await ethers.getSigner(pauser)).pause();
      extraChanger = await deployChanger(mocMultiCollateralGuard, newBucket.target.toString());
    });
    describe("WHEN the same bucket want to be added again", () => {
      describe("WHEN the governor tries to executes the changer", () => {
        it("THEN it fails with bucket already exists error", async function () {
          await expect(governor.executeChange(extraChanger.target.toString())).to.be.revertedWithCustomError(
            mocMultiCollateralGuard,
            ERRORS.BUCKET_ALREADY_EXISTS,
          );
        });
      });
    });
  });
  describe("AND a bucket with a TP not present on new bucket is ready to be added", () => {
    let newBucket: MocCARC20;
    let newBucketQueue: MocQueue;
    before(async () => {
      const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
      if (!deployedMocExpansionContract) throw new Error("No MocCARC20Expansion deployed.");

      const { mocCARC20, mocQueue } = await deployBucket({
        governorAddress: governorMockAddress, //Deploy with mock, to be able to add TPs
        mocMultiCollateralGuardAddress: mocMultiCollateralGuard.target.toString(),
        mocCoreExpansionAddress: deployedMocExpansionContract.address,
        mocVendorsAddress: mocContracts.mocVendors.target.toString(),
        feeTokenAddress: mocContracts.feeToken.target.toString(),
        feeTokenPriceProviderAddress: mocContracts.feeTokenPriceProvider.target.toString(),
      });
      newBucket = mocCARC20;
      newBucketQueue = mocQueue;
      await mocQueue.connect(await ethers.getSigner(pauser)).pause();

      // Role assignment is done on the Changer, as we are not using mocked Governor
      const assignRoles = false;
      // add 1 TP more to the new bucket
      await deployAndAddPeggedTokens(newBucket, tpParams.length + 1, tpParams, undefined, assignRoles);
      // Re-assign correct governor
      await newBucket.changeGovernor(governor.target.toString());
      await newBucketQueue.changeGovernor(governor.target.toString());
    });
    describe("WHEN trying to deploy the changer", () => {
      it("THEN it fails with tp amount unequal length", async function () {
        const changeContract = await ethers.getContractFactory("AddBucketChangerTemplate");
        await expect(deployChanger(mocMultiCollateralGuard, newBucket.target.toString())).to.be.revertedWithCustomError(
          changeContract,
          ERRORS.TP_AMOUNT_UNEQUAL_LENGTH,
        );
      });
    });
  });
  describe("AND a bucket with a TP not present on base bucket is ready to be added", () => {
    let newBucket: MocCARC20;
    let newBucketQueue: MocQueue;
    before(async () => {
      const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
      if (!deployedMocExpansionContract) throw new Error("No MocCARC20Expansion deployed.");

      const { mocCARC20, mocQueue } = await deployBucket({
        governorAddress: governorMockAddress, //Deploy with mock, to be able to add TPs
        mocMultiCollateralGuardAddress: mocMultiCollateralGuard.target.toString(),
        mocCoreExpansionAddress: deployedMocExpansionContract.address,
        mocVendorsAddress: mocContracts.mocVendors.target.toString(),
        feeTokenAddress: mocContracts.feeToken.target.toString(),
        feeTokenPriceProviderAddress: mocContracts.feeTokenPriceProvider.target.toString(),
      });
      newBucket = mocCARC20;
      newBucketQueue = mocQueue;
      await mocQueue.connect(await ethers.getSigner(pauser)).pause();

      // Role assignment is done on the Changer, as we are not using mocked Governor
      const assignRoles = false;
      // add same amount but different TP tokens to the new bucket
      await deployAndAddPeggedTokens(newBucket, tpParams.length, tpParams, undefined, assignRoles);
      // Re-assign correct governor
      await newBucket.changeGovernor(governor.target.toString());
      await newBucketQueue.changeGovernor(governor.target.toString());
    });
    describe("WHEN trying to deploy the changer", () => {
      it("THEN it fails with tp amount unequal length", async function () {
        const changeContract = await ethers.getContractFactory("AddBucketChangerTemplate");
        await expect(deployChanger(mocMultiCollateralGuard, newBucket.target.toString())).to.be.revertedWithCustomError(
          changeContract,
          ERRORS.TP_NOT_IN_BASE_BUCKET,
        );
      });
    });
  });
  describe("AND a bucket with a TP not present on base bucket is ready to be added", () => {
    let newBucket: MocCARC20;
    let newBucketQueue: MocQueue;
    before(async () => {
      const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
      if (!deployedMocExpansionContract) throw new Error("No MocCARC20Expansion deployed.");

      const { mocCARC20, mocQueue } = await deployBucket({
        governorAddress: governorMockAddress, //Deploy with mock, to be able to add TPs
        mocMultiCollateralGuardAddress: mocMultiCollateralGuard.target.toString(),
        mocCoreExpansionAddress: deployedMocExpansionContract.address,
        mocVendorsAddress: mocContracts.mocVendors.target.toString(),
        feeTokenAddress: mocContracts.feeToken.target.toString(),
        feeTokenPriceProviderAddress: mocContracts.feeTokenPriceProvider.target.toString(),
      });
      newBucket = mocCARC20;
      newBucketQueue = mocQueue;
      await mocQueue.connect(await ethers.getSigner(pauser)).pause();

      // Role assignment is done on the Changer, as we are not using mocked Governor
      const assignRoles = false;
      // add same amount but different TP tokens to the new bucket
      await deployAndAddPeggedTokens(newBucket, tpParams.length, tpParams, undefined, assignRoles);
      // Re-assign correct governor
      await newBucket.changeGovernor(governor.target.toString());
      await newBucketQueue.changeGovernor(governor.target.toString());
    });
    describe("WHEN trying to deploy the changer", () => {
      it("THEN it fails with tp not in base bucket error", async function () {
        const changeContract = await ethers.getContractFactory("AddBucketChangerTemplate");
        await expect(deployChanger(mocMultiCollateralGuard, newBucket.target.toString())).to.be.revertedWithCustomError(
          changeContract,
          ERRORS.TP_NOT_IN_BASE_BUCKET,
        );
      });
    });
  });
  describe("AND a bucket with a different governor is ready to be added", () => {
    let newBucket: MocCARC20;
    let newBucketQueue: MocQueue;
    before(async () => {
      const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
      if (!deployedMocExpansionContract) throw new Error("No MocCARC20Expansion deployed.");

      const { mocCARC20, mocQueue } = await deployBucket({
        governorAddress: governorMockAddress, //Deploy with mock, to be able to add TPs
        mocMultiCollateralGuardAddress: mocMultiCollateralGuard.target.toString(),
        mocCoreExpansionAddress: deployedMocExpansionContract.address,
        mocVendorsAddress: mocContracts.mocVendors.target.toString(),
        feeTokenAddress: mocContracts.feeToken.target.toString(),
        feeTokenPriceProviderAddress: mocContracts.feeTokenPriceProvider.target.toString(),
      });
      newBucket = mocCARC20;
      newBucketQueue = mocQueue;
      // Role assignment is done on the Changer, as we are not using mocked Governor
      const assignRoles = false;
      await deployAndAddPeggedTokens(newBucket, tpParams.length, tpParams, mocPeggedTokens, assignRoles);
      // Re-assign correct governor only on the queue
      await newBucketQueue.changeGovernor(governor.target.toString());
    });
    describe("WHEN trying to deploy the changer", () => {
      it("THEN it fails with Incompatible Buckets error", async function () {
        const changeContract = await ethers.getContractFactory("AddBucketChangerTemplate");
        await expect(deployChanger(mocMultiCollateralGuard, newBucket.target.toString())).to.be.revertedWithCustomError(
          changeContract,
          ERRORS.INCOMPATIBLE_BUCKET,
        );
      });
    });
  });
  describe("AND a bucket with a different governor on its queue is ready to be added", () => {
    let newBucket: MocCARC20;
    before(async () => {
      const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
      if (!deployedMocExpansionContract) throw new Error("No MocCARC20Expansion deployed.");

      const { mocCARC20 } = await deployBucket({
        governorAddress: governorMockAddress, //Deploy with mock, to be able to add TPs
        mocMultiCollateralGuardAddress: mocMultiCollateralGuard.target.toString(),
        mocCoreExpansionAddress: deployedMocExpansionContract.address,
        mocVendorsAddress: mocContracts.mocVendors.target.toString(),
        feeTokenAddress: mocContracts.feeToken.target.toString(),
        feeTokenPriceProviderAddress: mocContracts.feeTokenPriceProvider.target.toString(),
      });
      newBucket = mocCARC20;
      // Role assignment is done on the Changer, as we are not using mocked Governor
      const assignRoles = false;
      await deployAndAddPeggedTokens(newBucket, tpParams.length, tpParams, mocPeggedTokens, assignRoles);
      // Re-assign correct governor only on the bucket
      await newBucket.changeGovernor(governor.target.toString());
    });
    describe("WHEN trying to deploy the changer", () => {
      it("THEN it fails with Incompatible Buckets error", async function () {
        const changeContract = await ethers.getContractFactory("AddBucketChangerTemplate");
        await expect(deployChanger(mocMultiCollateralGuard, newBucket.target.toString())).to.be.revertedWithCustomError(
          changeContract,
          ERRORS.INCOMPATIBLE_BUCKET,
        );
      });
    });
  });
  describe("AND a not empty bucket is ready to be added", () => {
    let newBucket: MocCARC20;
    let newBucketQueue: MocQueue;
    before(async () => {
      const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
      if (!deployedMocExpansionContract) throw new Error("No MocCARC20Expansion deployed.");

      const { mocCARC20, mocQueue } = await deployBucket({
        governorAddress: governorMockAddress, //Deploy with mock, to be able to add TPs
        mocMultiCollateralGuardAddress: mocMultiCollateralGuard.target.toString(),
        mocCoreExpansionAddress: deployedMocExpansionContract.address,
        mocVendorsAddress: mocContracts.mocVendors.target.toString(),
        feeTokenAddress: mocContracts.feeToken.target.toString(),
        feeTokenPriceProviderAddress: mocContracts.feeTokenPriceProvider.target.toString(),
      });
      newBucket = mocCARC20;
      newBucketQueue = mocQueue;
      // Role assignment is done on the Changer, as we are not using mocked Governor
      const assignRoles = false;
      await deployAndAddPeggedTokens(newBucket, tpParams.length, tpParams, mocPeggedTokens, assignRoles);
      // Re-assign correct governor
      await newBucket.changeGovernor(governor.target.toString());
      await newBucketQueue.changeGovernor(governor.target.toString());
      // put an operation on the queue
      await mocFunctions[2].mintTC({ from: alice, qTC: 10, execute: false });
    });
    describe("WHEN trying to deploy the changer", () => {
      it("THEN it fails with Incompatible Buckets error", async function () {
        const changeContract = await ethers.getContractFactory("AddBucketChangerTemplate");
        await expect(deployChanger(mocMultiCollateralGuard, newBucket.target.toString())).to.be.revertedWithCustomError(
          changeContract,
          ERRORS.INCOMPATIBLE_BUCKET,
        );
      });
    });
  });
  describe("AND a bucket with an invalid parameter value is ready to be added", () => {
    let newBucket: MocCARC20;
    before(async () => {
      const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
      if (!deployedMocExpansionContract) throw new Error("No MocCARC20Expansion deployed.");
      const { mocCARC20 } = await deployBucket({
        governorAddress: governorMockAddress, //Deploy with mock, to be able to change parameters
        mocMultiCollateralGuardAddress: mocMultiCollateralGuard.target.toString(),
        mocCoreExpansionAddress: deployedMocExpansionContract.address,
        mocVendorsAddress: mocContracts.mocVendors.target.toString(),
        feeTokenAddress: mocContracts.feeToken.target.toString(),
        feeTokenPriceProviderAddress: mocContracts.feeTokenPriceProvider.target.toString(),
      });
      newBucket = mocCARC20;
      await newBucket.setCoverageThresholds(CONSTANTS.ONE, await newBucket.liqThrld());
    });
    describe("WHEN trying to deploy the changer", () => {
      it("THEN it fails with Invalid value error", async function () {
        const changeContract = await ethers.getContractFactory("AddBucketChangerTemplate");
        await expect(deployChanger(mocMultiCollateralGuard, newBucket.target.toString())).to.be.revertedWithCustomError(
          changeContract,
          ERRORS.INVALID_VALUE,
        );
      });
    });
  });
});
