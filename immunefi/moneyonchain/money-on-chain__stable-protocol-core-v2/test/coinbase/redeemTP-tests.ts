import { ethers, getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { expect } from "chai";
import { Address } from "hardhat-deploy/types";
import { MocCACoinbase, MocMultiCollateralGuard, MocQueue, MocRC20, NonPayableMock } from "../../typechain";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { redeemTPBehavior } from "../behaviors/redeemTP.behavior";
import { redeemTPQueueBehavior } from "../behaviors/queue/redeemTPQueue.behavior";
import {
  Balance,
  ERROR_SELECTOR,
  OperId,
  OperType,
  pEth,
  timedDescribe,
  tpParams,
  noVendor,
  ERRORS,
} from "../helpers/utils";
import { assertPrec } from "../helpers/assertHelper";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase redeem TP", function () {
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsCoinbase(mocContracts);
      return { mocContracts, mocFunctions };
    }
    redeemTPBehavior(setup);
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
    redeemTPQueueBehavior();

    describe("WHEN an user tries to register an operation, sending far more execution fees than expected", function () {
      it("THEN Tx fails with wrong execution fee", async function () {
        const queueTx = mocFunctions.redeemTP({
          from: deployer,
          qTP: 10,
          execute: false,
          netParams: { value: 5e10 },
        });
        await expect(queueTx).to.be.revertedWithCustomError(mocQueue, ERRORS.WRONG_EXEC_FEES);
      });
    });

    describe("AND a non payable contract", () => {
      let nonPayable: NonPayableMock;
      let operId: OperId;
      beforeEach(async () => {
        const factory = await ethers.getContractFactory("NonPayableMock");
        nonPayable = await factory.deploy();
      });
      describe("WHEN it registers a redeemTP operation", () => {
        beforeEach(async () => {
          // mint TC to non payable contract
          await mocFunctions.mintTC({ from: deployer, to: nonPayable.target.toString(), qTC: 1000 });
          // mint TP to non payable contract
          await mocFunctions.mintTP({ from: deployer, to: nonPayable.target.toString(), qTP: 100 });
          // non payable contract sends TP approval to Moc
          let data = tp.interface.encodeFunctionData("approve", [mocImpl.target.toString(), pEth(10)]);
          await nonPayable.forward(tp.target.toString(), data);

          operId = await mocQueue.operIdCount();
          // non payable contract registers redeemTP operation
          data = mocImpl.interface.encodeFunctionData("redeemTP", [
            tp.target.toString(),
            pEth(1),
            0,
            nonPayable.target.toString(),
            noVendor,
          ]);
          await nonPayable.forward(mocImpl.target.toString(), data, {
            value: await mocQueue.execCost(OperType.redeemTP),
          });
        });
        describe("AND execution is evaluated", () => {
          let execTx: ContractTransactionResponse;
          let prevTPBalance: Balance;
          beforeEach(async () => {
            prevTPBalance = await mocFunctions.tpBalanceOf(0, nonPayable.target.toString());
            execTx = await mocMultiCollateralGuard.execute();
          });
          it("THEN Operations fails with Unhandled Error", async () => {
            await expect(execTx).to.emit(mocQueue, "UnhandledError").withArgs(operId, ERROR_SELECTOR.TRANSFER_FAILED);
          });
          it("THEN TP is returned", async () => {
            assertPrec(prevTPBalance + pEth(1), await mocFunctions.tpBalanceOf(0, nonPayable.target.toString()));
          });
        });
      });
    });
  });
});
