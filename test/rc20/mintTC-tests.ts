import { expect } from "chai";
import { getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { ContractTransactionResponse } from "ethers";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mintTCBehavior } from "../behaviors/mintTC.behavior";
import { mintTCQueueBehavior } from "../behaviors/queue/mintTCQueue.behavior";
import { Balance, CONSTANTS, ERROR_SELECTOR, FailType, OperId, pEth, timedDescribe, tpParams } from "../helpers/utils";
import { ERC20Mock, MocCARC20, MocMultiCollateralGuard, MocQueue } from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 mint TC", function () {
  let mocFunctions: any;
  let collateralAsset: ERC20Mock;
  let deployer: Address;

  describe("GIVEN a MocCARC20 implementation deployed with mocQueueMock", function () {
    beforeEach(async function () {
      ({ deployer } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueMock");
      this.mocContracts = await fixtureDeploy();
      mocFunctions = await mocFunctionsRC20(this.mocContracts);
      this.mocFunctions = mocFunctions;
      ({ collateralAsset } = this.mocContracts);
    });

    mintTCBehavior();

    describe("WHEN an user sends almost max uint256 amount of Asset to mint TC", function () {
      it("THEN tx reverts with panic code 0x11 overflow", async function () {
        const qACmax = CONSTANTS.MAX_BALANCE;
        const qTC = CONSTANTS.MAX_BALANCE;
        await expect(
          mocFunctions.mintTC({ from: deployer, qTC, qACmax, applyPrecision: false }),
        ).to.be.revertedWithPanic("0x11");
      });
    });
    describe("WHEN alice tries to mint 10 TC", () => {
      describe("AND Collateral Asset transfer fails with false", () => {
        beforeEach(async () => {
          await collateralAsset.forceTransferToFail(FailType.failWithFalse);
        });
        it("THEN tx reverts because transfer failed", async () => {
          await expect(mocFunctions.mintTC({ from: deployer, qTC: 100 })).to.be.revertedWith(
            "SafeERC20: ERC20 operation did not succeed",
          );
        });
      });
      describe("AND Collateral Asset transfer fails with revert", () => {
        beforeEach(async () => {
          await collateralAsset.forceTransferToFail(FailType.failWithRevert);
        });
        it("THEN tx reverts because transfer failed", async () => {
          await expect(mocFunctions.mintTC({ from: deployer, qTC: 100 })).to.be.revertedWith(
            "SafeERC20: low-level call failed",
          );
        });
      });
    });
  });
  describe("GIVEN a MocCARC20 implementation deployed behind MocQueue", function () {
    let mocImpl: MocCARC20;
    let mocQueue: MocQueue;
    let mocMultiCollateralGuard: MocMultiCollateralGuard;
    beforeEach(async function () {
      ({ deployer } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      this.mocContracts = await fixtureDeploy();
      this.mocFunctions = await mocFunctionsRC20(this.mocContracts);
      mocFunctions = this.mocFunctions;
      ({ mocImpl, mocQueue, mocMultiCollateralGuard, collateralAsset } = this.mocContracts);
    });
    mintTCQueueBehavior();

    describe("WHEN an user registers a mintTC operation that will fail", () => {
      let operId: OperId;
      const qAC = 1;
      beforeEach(async () => {
        operId = await mocQueue.operIdCount();
        await mocFunctions.mintTC({ from: deployer, qTC: 10, qACmax: qAC, execute: false });
      });
      describe("AND AC token is locked and execution is evaluated", () => {
        let execTx: ContractTransactionResponse;
        let prevACBalance: Balance;
        beforeEach(async () => {
          prevACBalance = await mocFunctions.assetBalanceOf(deployer);
          await collateralAsset.forceTransferToFail(FailType.failWithRevert);
          execTx = await mocMultiCollateralGuard.execute();
        });
        it("THEN Operations fails with InsufficientQacSent, and Operation Error event is emitted", async function () {
          await expect(execTx)
            .to.emit(mocQueue, "OperationError")
            .withArgs(operId, ERROR_SELECTOR.INSUFFICIENT_QAC_SENT, "Insufficient qac sent");
        });
        it("THEN ACUnlockFailed event is emitted", async function () {
          await expect(execTx).to.emit(mocQueue, "ACUnlockFailed").withArgs(operId, deployer, pEth(qAC));
        });
        it("THEN AC is locked on mocCore and tracked on mocQueue", async () => {
          assertPrec(prevACBalance, await mocFunctions.assetBalanceOf(deployer));
          assertPrec(await mocQueue.senderLockedFunds(deployer), pEth(qAC));
          assertPrec(await mocQueue.totalLockedFunds(), pEth(qAC));
          assertPrec(await mocImpl.qACLockedInPending(), pEth(qAC));
        });
      });
    });
  });
});
