import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { redeemTCandTPBehavior } from "../behaviors/redeemTCandTP.behavior";
import { redeemTCandTPQueueBehavior } from "../behaviors/queue/redeemTCandTPQueue.behavior";
import {
  Balance,
  ERROR_SELECTOR,
  OperId,
  OperType,
  pEth,
  timedDescribe,
  tpParams,
  noVendor,
  loadFixture,
  ERRORS,
} from "../helpers/utils";
import { MocCACoinbase, MocMultiCollateralGuard, MocQueue, MocRC20, NonPayableMock } from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase redeem TC and TP", function () {
  let mocFunctions: any;
  let mocQueue: MocQueue;
  let deployer: Address;
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    async function setup() {
      ({ deployer } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      mocFunctions = await mocFunctionsCoinbase(mocContracts);
      ({ mocQueue } = mocContracts);
      return { mocContracts, mocFunctions };
    }
    redeemTCandTPBehavior(setup);

    describe("WHEN an user tries to register an operation, sending far more execution fees than expected", function () {
      it("THEN Tx fails with wrong execution fee", async function () {
        await loadFixture(setup);
        const queueTx = mocFunctions.redeemTCandTP({
          from: deployer,
          qTC: 10,
          qTP: 10,
          execute: false,
          netParams: { value: 5e10 },
        });
        await expect(queueTx).to.be.revertedWithCustomError(mocQueue, ERRORS.WRONG_EXEC_FEES);
      });
    });
  });

  describe("GIVEN a MocCoinbase implementation deployed behind MocQueue", function () {
    let mocImpl: MocCACoinbase;
    let mocCollateralToken: MocRC20;
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
        mocCollateralToken,
        mocPeggedTokens: [tp],
      } = this.mocContracts);
    });
    redeemTCandTPQueueBehavior();

    describe("AND a non payable contract", () => {
      let nonPayable: NonPayableMock;
      let operId: OperId;
      beforeEach(async () => {
        const factory = await ethers.getContractFactory("NonPayableMock");
        nonPayable = await factory.deploy();
      });
      describe("WHEN it registers a redeemTCandTP operation", () => {
        beforeEach(async () => {
          // mint TC to non payable contract
          await mocFunctions.mintTC({ from: deployer, to: nonPayable.target.toString(), qTC: 1000 });
          // mint TP to non payable contract
          await mocFunctions.mintTP({ from: deployer, to: nonPayable.target.toString(), qTP: 100 });
          // non payable contract sends TC approval to Moc
          let data = mocCollateralToken.interface.encodeFunctionData("approve", [mocImpl.target.toString(), pEth(1)]);
          await nonPayable.forward(mocCollateralToken.target.toString(), data);
          // non payable contract sends TP approval to Moc
          data = tp.interface.encodeFunctionData("approve", [mocImpl.target.toString(), pEth(100)]);
          await nonPayable.forward(tp.target.toString(), data);

          operId = await mocQueue.operIdCount();
          // non payable contract registers redeemTCandTP operation
          data = mocImpl.interface.encodeFunctionData("redeemTCandTP", [
            tp.target.toString(),
            pEth(1),
            pEth(100),
            0,
            nonPayable.target.toString(),
            noVendor,
          ]);
          await nonPayable.forward(mocImpl.target.toString(), data, {
            value: await mocQueue.execCost(OperType.redeemTCandTP),
          });
        });
        describe("AND execution is evaluated", () => {
          let execTx: ContractTransactionResponse;
          let prevTCBalance: Balance;
          let prevTPBalance: Balance;
          beforeEach(async () => {
            prevTCBalance = await mocFunctions.tcBalanceOf(nonPayable.target.toString());
            prevTPBalance = await mocFunctions.tpBalanceOf(0, nonPayable.target.toString());
            execTx = await mocMultiCollateralGuard.execute();
          });
          it("THEN Operations fails with Unhandled Error as non payable contract cannot receive coinbase", async () => {
            await expect(execTx).to.emit(mocQueue, "UnhandledError").withArgs(operId, ERROR_SELECTOR.TRANSFER_FAILED);
          });
          it("THEN TC is returned", async () => {
            assertPrec(prevTCBalance + pEth(1), await mocFunctions.tcBalanceOf(nonPayable.target.toString()));
          });
          it("THEN TP is returned", async () => {
            assertPrec(prevTPBalance + pEth(100), await mocFunctions.tpBalanceOf(0, nonPayable.target.toString()));
          });
        });
      });
    });
  });
});
