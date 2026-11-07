import { ethers, getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { expect } from "chai";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { MocCACoinbase, MocMultiCollateralGuard, MocQueue, MocRC20, NonPayableMock } from "../../typechain";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { redeemTCBehavior } from "../behaviors/redeemTC.behavior";
import { redeemTCQueueBehavior } from "../behaviors/queue/redeemTCQueue.behavior";
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

timedDescribe("Feature: MocCoinbase redeem TC", function () {
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
    async function setup() {
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsCoinbase(mocContracts);
      return { mocContracts, mocFunctions };
    }
    redeemTCBehavior(setup);
  });

  describe("GIVEN a MocCoinbase implementation deployed behind MocQueue", function () {
    let mocImpl: MocCACoinbase;
    let mocCollateralToken: MocRC20;
    let mocQueue: MocQueue;
    let mocMultiCollateralGuard: MocMultiCollateralGuard;
    let mocFunctions: any;
    let deployer: Address;
    async function setup() {
      ({ deployer } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();
      mocFunctions = await mocFunctionsCoinbase(mocContracts);

      ({ mocImpl, mocQueue, mocCollateralToken, mocMultiCollateralGuard } = mocContracts);
      return { mocContracts, mocFunctions };
    }
    redeemTCQueueBehavior(setup);

    describe("WHEN an user tries to register an operation, sending far more execution fees than expected", function () {
      it("THEN Tx fails with wrong execution fee because is greater than 10x", async function () {
        await loadFixture(setup);
        const queueTx = mocFunctions.redeemTC({
          from: deployer,
          qTC: 10,
          execute: false,
          netParams: { value: 5e10 },
        });
        await expect(queueTx).to.be.revertedWithCustomError(mocQueue, ERRORS.WRONG_EXEC_FEES);
      });
      it("THEN MocMultiCollateralGuard received the overpaid fee because is less than 10x", async function () {
        await loadFixture(setup);
        await mocFunctions.mintTC({
          from: deployer,
          qTC: 100000,
          execute: true,
        });
        const execFee = (await mocQueue.execCost(OperType.redeemTC)) * 2n;
        await mocFunctions.redeemTC({
          from: deployer,
          qTC: 10,
          execute: false,
          netParams: { value: execFee },
        });
        assertPrec(await mocFunctions.acBalanceOf(mocMultiCollateralGuard.target), execFee);
      });
    });

    describe("AND a non payable contract", () => {
      let nonPayable: NonPayableMock;
      let operId: OperId;
      async function nonPayableSetup() {
        await loadFixture(setup);
        const factory = await ethers.getContractFactory("NonPayableMock");
        nonPayable = await factory.deploy();
      }
      describe("WHEN it registers a redeemTC operation", () => {
        async function registerRedeemSetup() {
          await loadFixture(nonPayableSetup);
          // mint TC to non payable contract
          await mocFunctions.mintTC({ from: deployer, to: nonPayable.target.toString(), qTC: 1000 });
          // non payable contract sends TC approval to Moc
          let data = mocCollateralToken.interface.encodeFunctionData("approve", [mocImpl.target.toString(), pEth(1)]);
          await nonPayable.forward(mocCollateralToken.target.toString(), data);

          operId = await mocQueue.operIdCount();
          // non payable contract registers redeemTC operation
          data = mocImpl.interface.encodeFunctionData("redeemTC", [pEth(1), 0, nonPayable.target.toString(), noVendor]);
          await nonPayable.forward(mocImpl.target.toString(), data, {
            value: await mocQueue.execCost(OperType.redeemTC),
          });
        }
        describe("AND execution is evaluated", () => {
          let execTx: ContractTransactionResponse;
          let prevTCBalance: Balance;
          before(async function () {
            await loadFixture(registerRedeemSetup);
            prevTCBalance = await mocFunctions.tcBalanceOf(nonPayable.target.toString());
            execTx = await mocMultiCollateralGuard.execute();
          });
          it("THEN Operations fails with Unhandled Error as non payable contract cannot receive coinbase", async () => {
            await expect(execTx).to.emit(mocQueue, "UnhandledError").withArgs(operId, ERROR_SELECTOR.TRANSFER_FAILED);
          });
          it("THEN TC is returned", async () => {
            assertPrec(prevTCBalance + pEth(1), await mocFunctions.tcBalanceOf(nonPayable.target.toString()));
          });
        });
      });
    });
  });
});
