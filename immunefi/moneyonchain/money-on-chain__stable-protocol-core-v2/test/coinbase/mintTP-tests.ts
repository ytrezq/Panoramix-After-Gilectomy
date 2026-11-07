import { ethers, getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { expect } from "chai";
import { Address } from "hardhat-deploy/types";
import { MocCACoinbase, MocMultiCollateralGuard, MocQueue, MocRC20, NonPayableMock } from "../../typechain";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { mintTPBehavior } from "../behaviors/mintTP.behavior";
import { mintTPQueueBehavior } from "../behaviors/queue/mintTPQueue.behavior";
import { assertPrec } from "../helpers/assertHelper";
import { Balance, ERROR_SELECTOR, OperId, OperType, pEth, timedDescribe, tpParams, noVendor } from "../helpers/utils";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase mint TP", function () {
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsCoinbase(mocContracts);
      return { mocContracts, mocFunctions };
    }
    mintTPBehavior(setup);
  });

  describe("GIVEN a MocCoinbase implementation deployed behind MocQueue", function () {
    let mocImpl: MocCACoinbase;
    let tp: MocRC20;
    let mocQueue: MocQueue;
    let mocMultiCollateralGuard: MocMultiCollateralGuard;
    let mocFunctions: any;
    let deployer: Address;
    beforeEach(async function () {
      ({ deployer } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueBasefeeMock");
      this.mocContracts = await fixtureDeploy();
      this.mocFunctions = await mocFunctionsCoinbase(this.mocContracts);
      mocFunctions = this.mocFunctions;
      ({
        mocImpl,
        mocQueue,
        mocMultiCollateralGuard,
        mocPeggedTokens: [tp],
      } = this.mocContracts);
    });
    mintTPQueueBehavior();

    describe("AND a non payable contract", () => {
      let nonPayable: NonPayableMock;
      let operId: OperId;
      const qACSent = pEth(100);
      beforeEach(async () => {
        const factory = await ethers.getContractFactory("NonPayableMock");
        nonPayable = await factory.deploy();
      });
      describe("WHEN it registers a mintTP operation but there is not collateral in the protocol", () => {
        beforeEach(async () => {
          operId = await mocQueue.operIdCount();
          // non payable contract registers mintTP operation
          const data = mocImpl.interface.encodeFunctionData("mintTP", [
            tp.target.toString(),
            pEth(1),
            deployer,
            noVendor,
          ]);
          await nonPayable.forward(mocImpl.target.toString(), data, {
            value: (await mocQueue.execCost(OperType.mintTP)) + qACSent,
          });
        });
        describe("AND execution is evaluated", () => {
          let execTx: ContractTransactionResponse;
          let prevACBalance: Balance;
          beforeEach(async () => {
            prevACBalance = await mocFunctions.assetBalanceOf(deployer);
            execTx = await mocMultiCollateralGuard.execute();
          });
          it("THEN Operations fails as there is not enough TP to mint, and Operation Error event is emitted", async function () {
            await expect(execTx)
              .to.emit(mocQueue, "OperationError")
              .withArgs(operId, ERROR_SELECTOR.INSUFFICIENT_TP_TO_MINT, "Insufficient tp to mint");
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
      describe("WHEN it registers a mintTP operation with exceeded amount of coinbase", () => {
        beforeEach(async () => {
          // mint TC to add collateral
          await mocFunctions.mintTC({ from: deployer, qTC: 1000 });

          operId = await mocQueue.operIdCount();
          // non payable contract registers mintTP operation
          const data = mocImpl.interface.encodeFunctionData("mintTP", [
            tp.target.toString(),
            pEth(1),
            deployer,
            noVendor,
          ]);
          await nonPayable.forward(mocImpl.target.toString(), data, {
            value: (await mocQueue.execCost(OperType.mintTP)) + qACSent,
          });
        });
        describe("AND execution is evaluated", () => {
          let execTx: ContractTransactionResponse;
          let prevACBalance: Balance;
          beforeEach(async () => {
            prevACBalance = await mocFunctions.assetBalanceOf(deployer);
            execTx = await mocMultiCollateralGuard.execute();
          });
          it("THEN Operations fails with Unhandled Error as non payable contract cannot receive the surplus AC", async () => {
            await expect(execTx).to.emit(mocQueue, "UnhandledError").withArgs(operId, ERROR_SELECTOR.TRANSFER_FAILED);
          });
          it("THEN ACUnlockFailed event is emitted", async function () {
            await expect(execTx).to.emit(mocQueue, "ACUnlockFailed").withArgs(operId, nonPayable, qACSent);
          });
          it("THEN AC cannot be returned", async () => {
            assertPrec(prevACBalance, await mocFunctions.assetBalanceOf(deployer));
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
