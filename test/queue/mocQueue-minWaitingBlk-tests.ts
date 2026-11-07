import { expect } from "chai";
import { getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { OperId, mineUpTo, timedDescribe, tpParams } from "../helpers/utils";
import { MocQueue } from "../../typechain";
import { fixtureDeployedMocRC20 } from "../rc20/fixture";

timedDescribe("Feature: MocQueue Operation min waiting Blk", function () {
  let mocFunctions: any;
  let deployer: Address;
  let executor: Address;

  describe("GIVEN a MocQueue with min waiting set to 10 blocks", function () {
    let mocQueue: MocQueue;
    let operId: OperId;
    let alice: Address;
    let bob: Address;
    beforeEach(async function () {
      ({ deployer, alice, bob } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();

      ({ mocQueue } = mocContracts);
      mocFunctions = await mocFunctionsRC20(mocContracts);
      await mocQueue.setMaxOperWaitingBlk(11);
      await mocQueue.setMinOperWaitingBlk(10);
    });
    describe("WHEN both Alice and Bob register a valid operation", function () {
      let execTx: ContractTransactionResponse;
      let aliceBlock: number;
      let bobBlock: number;
      beforeEach(async function () {
        executor = deployer;
        operId = await mocQueue.operIdCount();
        const aliceTx = await mocFunctions.mintTC({ from: alice, qTC: 10, qACmax: 100, execute: false });
        aliceBlock = aliceTx.blockNumber;
        const bobTx = await mocFunctions.mintTC({ from: bob, qTC: 10, qACmax: 100, execute: false });
        bobBlock = bobTx.blockNumber;
      });
      describe("AND queue is executed", function () {
        beforeEach(async function () {
          execTx = await mocFunctions.executeQueue();
        });
        it("THEN no operation is executed", async function () {
          await expect(execTx).not.to.emit(mocQueue, "OperationExecuted");
        });
        describe("AND queue is executed after a block", function () {
          beforeEach(async function () {
            await mineUpTo(aliceBlock + 10);
            execTx = await mocFunctions.executeQueue();
          });
          it("THEN only Alice operation is executed", async function () {
            await expect(execTx).to.emit(mocQueue, "OperationExecuted").withArgs(executor, operId);
          });
          describe("AND queue is executed after another block", function () {
            beforeEach(async function () {
              await mineUpTo(bobBlock + 10);
              execTx = await mocFunctions.executeQueue();
            });
            it("THEN Bob's operation is executed", async function () {
              await expect(execTx)
                .to.emit(mocQueue, "OperationExecuted")
                .withArgs(executor, operId + 1n);
            });
          });
        });
      });
    });
  });
});
