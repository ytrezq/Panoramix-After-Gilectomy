import { expect } from "chai";
import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { ERRORS, timedDescribe, tpParams } from "../../helpers/utils";
import { GovernorMock__factory, MocQueue } from "../../../typechain";
import { fixtureDeployedMocRC20 } from "../../rc20/fixture";

timedDescribe("Feature: MocQueue Pausing", function () {
  describe("GIVEN a MocQueue implementation with queued Operations", function () {
    let mocFunctions: any;
    let pauser: Address;
    let mocQueue: MocQueue;
    let alice: Address;

    const expectPauseRevert = async (result: any) =>
      expect(result).to.be.revertedWithCustomError(mocQueue, ERRORS.NOT_WHEN_PAUSED);

    before(async function () {
      ({ deployer: pauser, alice } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();
      mocFunctions = await mocFunctionsRC20(mocContracts);

      ({ mocQueue } = mocContracts);
      const governorAddress = await mocQueue.governor();
      const governorMock = GovernorMock__factory.connect(governorAddress, await ethers.getSigner(pauser));
      await governorMock.setIsAuthorized(true);
      await mocQueue.setPauser(pauser);
      await mocQueue.makeStoppable();
      await mocFunctions.mintTC({ from: alice, qTC: 10, execute: false });
    });
    describe("WHEN queue is paused", function () {
      before(async function () {
        await mocQueue.pause();
      });
      it("THEN it fails when a user tries to register a mint TC Operation", async function () {
        await expectPauseRevert(mocFunctions.mintTC({ from: alice, qTC: 10, execute: false }));
      });
      it("THEN it fails when a user tries to register a redeem TC Operation", async function () {
        await expectPauseRevert(mocFunctions.redeemTC({ from: alice, qTC: 10, execute: false }));
      });
      it("THEN it fails when a user tries to register a mint TP Operation", async function () {
        await expectPauseRevert(mocFunctions.mintTP({ from: alice, qTP: 10, execute: false }));
      });
      it("THEN it fails when a user tries to register a redeem TP Operation", async function () {
        await expectPauseRevert(mocFunctions.redeemTP({ from: alice, qTP: 10, execute: false }));
      });
      it("THEN it fails when a user tries to register a MintTCandTP Operation", async function () {
        await expectPauseRevert(mocFunctions.mintTCandTP({ from: alice, qTP: 10, execute: false }));
      });
      it("THEN it fails when a user tries to register a redeemTCandTP Operation", async function () {
        await expectPauseRevert(mocFunctions.redeemTCandTP({ from: alice, qTC: 1, qTP: 1, execute: false }));
      });
      it("THEN it fails when a user tries to register a swapTCforTP Operation", async function () {
        await expectPauseRevert(mocFunctions.swapTCforTP({ from: alice, qTC: 10, execute: false }));
      });
      it("THEN it fails when a user tries to register a swapTPforTC Operation", async function () {
        await expectPauseRevert(mocFunctions.swapTPforTC({ from: alice, qTP: 10, execute: false }));
      });
      it("THEN it fails when a user tries to register a swapTPforTP Operation", async function () {
        await expectPauseRevert(mocFunctions.swapTPforTP({ from: alice, qTP: 1, qTPmin: 1, execute: false }));
      });
    });
  });
});
