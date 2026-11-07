import { expect } from "chai";
import { deployments, ethers, getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { GovernorMock, GovernorMock__factory, MocQueue } from "../../../typechain";
import { ERRORS, deployMocQueue, timedDescribe } from "../../helpers/utils";

const fixtureDeploy = async (
  mocMultiCollateralGuardAddress: Address,
): Promise<{
  mocQueue: MocQueue;
  governorMock: GovernorMock;
}> => {
  await deployments.fixture();
  const mocQueue = await deployMocQueue({
    contractName: "MocQueue",
    mocMultiCollateralGuardAddress, // mocMultiCollateralGuard not relevant for this tests
  });
  const governorAddress = await mocQueue.governor();
  const [signer] = await ethers.getSigners();
  return {
    mocQueue,
    governorMock: GovernorMock__factory.connect(governorAddress, signer),
  };
};

timedDescribe("Feature: Verify all MocQueue config settings are protected by governance", () => {
  let governorMock: GovernorMock;
  let mocQueue: MocQueue;
  let otherUser: Address;
  before(async () => {
    let deployer: Address;
    ({ deployer, otherUser } = await getNamedAccounts());
    const mocMultiCollateralGuardAddress = deployer;
    ({ mocQueue, governorMock } = await fixtureDeploy(mocMultiCollateralGuardAddress));
  });

  describe("GIVEN the Governor has authorized the change", () => {
    before(async () => {
      await governorMock.setIsAuthorized(true);
    });
    describe(`WHEN setMinOperWaitingBlk is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocQueue.setMinOperWaitingBlk(1);
        expect(await mocQueue.minOperWaitingBlk()).to.be.equal(1);
      });
    });
    describe(`WHEN setMaxOperWaitingBlk is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocQueue.setMaxOperWaitingBlk(101);
        expect(await mocQueue.maxOperWaitingBlk()).to.be.equal(101);
      });
    });
    describe(`WHEN register bucket is invoked`, () => {
      before(async () => {
        await mocQueue.registerBucket(governorMock.target.toString());
      });
      it("THEN the new value is assigned", async function () {
        expect(await mocQueue.mocOperations()).to.be.equal(governorMock.target.toString());
      });
      describe(`AND register bucket is invoked again`, () => {
        it("THEN it fails with bucket already registered error", async function () {
          const tx = mocQueue.registerBucket(governorMock.target.toString());
          await expect(tx).to.be.revertedWithCustomError(mocQueue, ERRORS.BUCKET_ALREADY_REGISTERED);
        });
      });
    });
    describe(`WHEN setMocMultiCollateralGuard is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocQueue.setMocMultiCollateralGuard(otherUser);
        expect(await mocQueue.mocMultiCollateralGuard()).to.be.equal(otherUser);
      });
    });
    describe(`WHEN initOperId is invoked`, () => {
      it("THEN the new values are assigned", async function () {
        await mocQueue.initOperId(43, 42);
        expect(await mocQueue.operIdCount()).to.be.equal(43);
        expect(await mocQueue.firstOperId()).to.be.equal(42);
      });
    });
  });
  describe("GIVEN the Governor has not authorized the change", () => {
    let expectRevertNotAuthorized: (it: any) => any;
    before(async () => {
      await governorMock.setIsAuthorized(false);
      expectRevertNotAuthorized = it => expect(it).to.be.revertedWithCustomError(mocQueue, ERRORS.NOT_AUTH_CHANGER);
    });
    describe("WHEN minOperWaitingBlk is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocQueue.setMinOperWaitingBlk(42));
      });
    });
    describe("WHEN maxOperWaitingBlk is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocQueue.setMaxOperWaitingBlk(42));
      });
    });
    describe("WHEN registerBucket is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocQueue.registerBucket(governorMock.target.toString()));
      });
    });
    describe("WHEN setMocMultiCollateralGuard is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocQueue.setMocMultiCollateralGuard(otherUser));
      });
    });
    describe("WHEN initOperId is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocQueue.initOperId(42, 42));
      });
    });
  });
});
