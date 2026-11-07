import { expect } from "chai";
import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { OperId, tpParams } from "../helpers/utils";
import { GovernorMock__factory, MocMultiCollateralGuard, MocQueue } from "../../typechain";
import { fixtureDeployedMocRC20 } from "../rc20/fixture";

describe("Feature: MocMultiCollateralGuard Pausing", function () {
  describe("GIVEN a MocMultiCollateralGuard implementation with queued Operations", function () {
    let mocFunctions: any;
    let pauser: Address;
    let executor: Address;
    let mocQueue: MocQueue;
    let mocMultiCollateralGuard: MocMultiCollateralGuard;
    let alice: Address;
    let operId: OperId;

    before(async function () {
      ({ deployer: pauser, deployer: executor, alice } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();
      mocFunctions = await mocFunctionsRC20(mocContracts);

      ({ mocQueue, mocMultiCollateralGuard } = mocContracts);
      const governorAddress = await mocMultiCollateralGuard.governor();
      const governorMock = GovernorMock__factory.connect(governorAddress, await ethers.getSigner(pauser));
      await governorMock.setIsAuthorized(true);
      await mocMultiCollateralGuard.setPauser(pauser);
      await mocMultiCollateralGuard.makeStoppable();
      operId = await mocQueue.operIdCount();
      await mocFunctions.mintTC({ from: alice, qTC: 10, execute: false });
    });
    describe("WHEN multiCollateralGuard is paused", function () {
      before(async function () {
        await mocMultiCollateralGuard.pause();
      });
      describe("WHEN it get's unpaused", function () {
        before(async function () {
          await mocMultiCollateralGuard.unpause();
        });
        it("THEN a new operation can be queued", async function () {
          const queueTxAlice = await mocFunctions.mintTC({ from: alice, qTC: 10, execute: false });
          await expect(queueTxAlice).to.emit(mocQueue, "OperationQueued");
        });
        describe("AND queue is executed", function () {
          it("THEN both existent and new queued Operations are processed", async function () {
            const execTx = await mocFunctions.executeQueue();
            await expect(execTx).to.emit(mocQueue, "OperationExecuted").withArgs(executor, operId);
            await expect(execTx)
              .to.emit(mocQueue, "OperationExecuted")
              .withArgs(executor, operId + 1n);
          });
        });
      });
    });
  });
});
