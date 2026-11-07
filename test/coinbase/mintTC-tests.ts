import { ethers, getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { expect } from "chai";
import { Address } from "hardhat-deploy/types";
import { MocCACoinbase, MocMultiCollateralGuard, MocQueue, NonPayableMock } from "../../typechain";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { mintTCBehavior } from "../behaviors/mintTC.behavior";
import { mintTCBehavior as mintTCNoSuccessFeeBehavior } from "../behaviors/mintTC-noSuccessFee.behavior";
import { mintTCQueueBehavior } from "../behaviors/queue/mintTCQueue.behavior";
import {
  Balance,
  ERROR_SELECTOR,
  OperId,
  OperType,
  noVendor,
  pEth,
  timedDescribe,
  tpParams,
  ERRORS,
} from "../helpers/utils";
import { assertPrec } from "../helpers/assertHelper";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase mint TC", function () {
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    beforeEach(async function () {
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
      this.mocContracts = await fixtureDeploy();
      this.mocFunctions = await mocFunctionsCoinbase(this.mocContracts);
    });
    describe("AND success fee is enabled", function () {
      mintTCBehavior();
    });
    describe("AND successFee and appreciationFactor are disabled", function () {
      beforeEach(async function () {
        await this.mocContracts.mocImpl.setSuccessFeeParams(
          0n,
          0n,
          await this.mocContracts.mocImpl.mocAppreciationBeneficiaryAddress(),
        );
      });
      mintTCNoSuccessFeeBehavior();
    });
  });

  describe("GIVEN a MocCoinbase implementation deployed behind MocQueue", function () {
    let mocImpl: MocCACoinbase;
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
      ({ mocImpl, mocQueue, mocMultiCollateralGuard } = this.mocContracts);
    });
    mintTCQueueBehavior();

    describe("WHEN an user tries to register an operation, sending less execution fees than expected", function () {
      let queueTx: ContractTransactionResponse;
      beforeEach(async function () {
        queueTx = mocFunctions.mintTC({
          from: deployer,
          qTC: 10n,
          qACmax: 1n,
          execute: false,
          applyPrecision: false,
          execFee: 0n,
        });
      });
      it("THEN Tx fails with wrong execution fee", async function () {
        await expect(queueTx).to.be.revertedWithCustomError(mocQueue, ERRORS.WRONG_EXEC_FEES);
      });
    });

    describe("AND a non payable contract", () => {
      let nonPayable: NonPayableMock;
      let operId: OperId;
      const qACSent = pEth(100);
      beforeEach(async () => {
        const factory = await ethers.getContractFactory("NonPayableMock");
        nonPayable = await factory.deploy();
      });
      describe("WHEN it registers a mintTC operation with exceeded amount of coinbase", () => {
        beforeEach(async () => {
          operId = await mocQueue.operIdCount();
          // non payable contract registers mintTC operation
          const data = mocImpl.interface.encodeFunctionData("mintTC", [pEth(1), deployer, noVendor]);
          await nonPayable.forward(mocImpl.target.toString(), data, {
            value: (await mocQueue.execCost(OperType.mintTC)) + qACSent,
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
