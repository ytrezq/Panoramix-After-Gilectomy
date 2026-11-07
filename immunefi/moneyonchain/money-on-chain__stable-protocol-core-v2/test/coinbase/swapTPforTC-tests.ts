import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { swapTPforTCBehavior } from "../behaviors/swapTPforTC.behavior";
import { swapTPforTCQueueBehavior } from "../behaviors/queue/swapTPforTCQueue.behavior";
import { Balance, ERROR_SELECTOR, OperId, OperType, pEth, timedDescribe, tpParams, noVendor } from "../helpers/utils";
import { MocCACoinbase, MocMultiCollateralGuard, MocQueue, MocRC20, NonPayableMock } from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase swap TP for TC", function () {
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsCoinbase(mocContracts);
      return { mocContracts, mocFunctions };
    }
    swapTPforTCBehavior(setup);
  });

  describe("GIVEN a MocCoinbase implementation deployed behind MocQueue", function () {
    let mocImpl: MocCACoinbase;
    let tp: MocRC20;
    let mocQueue: MocQueue;
    let mocMultiCollateralGuard: MocMultiCollateralGuard;
    let mocFunctions: any;
    let deployer: Address;
    async function setup() {
      ({ deployer } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueBasefeeMock");

      const mocContracts = await fixtureDeploy();
      mocFunctions = await mocFunctionsCoinbase(mocContracts);

      ({
        mocImpl,
        mocQueue,
        mocMultiCollateralGuard,
        mocPeggedTokens: [tp],
      } = mocContracts);
      return { mocContracts, mocFunctions };
    }
    swapTPforTCQueueBehavior(setup);
    describe("AND a non payable contract", () => {
      let nonPayable: NonPayableMock;
      let operId: OperId;
      const qACSent = pEth(100);
      beforeEach(async () => {
        await loadFixture(setup);
        const factory = await ethers.getContractFactory("NonPayableMock");
        nonPayable = await factory.deploy();
      });
      describe("WHEN it registers a swapTPforTC operation with exceeded amount of coinbase", () => {
        beforeEach(async () => {
          // mint TC to non payable contract
          await mocFunctions.mintTC({ from: deployer, to: nonPayable.target.toString(), qTC: 1000 });
          // mint TP to non payable contract
          await mocFunctions.mintTP({ from: deployer, to: nonPayable.target.toString(), qTP: 100 });
          // non payable contract sends TP approval to Moc
          let data = tp.interface.encodeFunctionData("approve", [mocImpl.target.toString(), pEth(1)]);
          await nonPayable.forward(tp.target.toString(), data);

          operId = await mocQueue.operIdCount();
          // non payable contract registers swapTPforTC operation
          data = mocImpl.interface.encodeFunctionData("swapTPforTC", [
            tp.target.toString(),
            pEth(1),
            0,
            deployer,
            noVendor,
          ]);
          await nonPayable.forward(mocImpl.target.toString(), data, {
            value: (await mocQueue.execCost(OperType.swapTPforTC)) + qACSent,
          });
        });
        describe("AND execution is evaluated", () => {
          let execTx: ContractTransactionResponse;
          let prevTPBalance: Balance;
          let prevACBalance: Balance;
          beforeEach(async () => {
            prevTPBalance = await mocFunctions.tpBalanceOf(0, nonPayable.target.toString());
            prevACBalance = await mocFunctions.assetBalanceOf(deployer);
            execTx = await mocMultiCollateralGuard.execute();
          });
          it("THEN Operations fails with Unhandled Error as non payable contract cannot receive the surplus AC", async () => {
            await expect(execTx).to.emit(mocQueue, "UnhandledError").withArgs(operId, ERROR_SELECTOR.TRANSFER_FAILED);
          });
          it("THEN TP is returned", async () => {
            assertPrec(prevTPBalance + pEth(1), await mocFunctions.tpBalanceOf(0, nonPayable.target.toString()));
          });
          it("THEN ACUnlockFailed event is emitted", async function () {
            await expect(execTx).to.emit(mocQueue, "ACUnlockFailed").withArgs(operId, nonPayable, qACSent);
          });
          it("THEN AC is locked on mocCore and tracked on mocQueue", async () => {
            assertPrec(prevACBalance, await mocFunctions.assetBalanceOf(deployer));
            assertPrec(await mocQueue.senderLockedFunds(nonPayable), qACSent);
            assertPrec(await mocQueue.totalLockedFunds(), qACSent);
            assertPrec(await mocImpl.qACLockedInPending(), qACSent);
          });
        });
      });
    });
  });
});
