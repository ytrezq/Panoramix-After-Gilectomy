import { expect } from "chai";
import { getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { ContractTransactionResponse } from "ethers";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mintTPBehavior } from "../behaviors/mintTP.behavior";
import { mintTPQueueBehavior } from "../behaviors/queue/mintTPQueue.behavior";
import { Balance, ERROR_SELECTOR, FailType, OperId, pEth, timedDescribe, tpParams } from "../helpers/utils";
import { ERC20Mock, MocCARC20, MocMultiCollateralGuard, MocQueue } from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 mint TP", function () {
  describe("GIVEN a MocCARC20 implementation deployed", function () {
    const setup = async function () {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocContracts, mocFunctions };
    };
    mintTPBehavior(setup);
  });

  describe("GIVEN a MocCARC20 implementation deployed behind MocQueue", function () {
    let deployer: Address;
    let mocImpl: MocCARC20;
    let collateralAsset: ERC20Mock;
    let mocQueue: MocQueue;
    let mocMultiCollateralGuard: MocMultiCollateralGuard;
    let mocFunctions: any;
    beforeEach(async function () {
      ({ deployer } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      this.mocContracts = await fixtureDeploy();
      this.mocFunctions = await mocFunctionsRC20(this.mocContracts);
      mocFunctions = this.mocFunctions;
      ({ mocImpl, mocQueue, mocMultiCollateralGuard, collateralAsset } = this.mocContracts);
    });
    mintTPQueueBehavior();

    describe("WHEN an user registers a mintTP operation that will fail", () => {
      let operId: OperId;
      const qAC = 1;
      beforeEach(async () => {
        operId = await mocQueue.operIdCount();
        await mocFunctions.mintTP({ from: deployer, qTP: 10, qACmax: qAC, execute: false });
      });
      describe("AND AC token is locked and execution is evaluated", () => {
        let execTx: ContractTransactionResponse;
        let prevACBalance: Balance;
        beforeEach(async () => {
          prevACBalance = await mocFunctions.assetBalanceOf(deployer);
          await collateralAsset.forceTransferToFail(FailType.failWithRevert);
          execTx = await mocMultiCollateralGuard.execute();
        });
        it("THEN Operations fails with InsufficientQTPtoMint, and Operation Error event is emitted", async function () {
          await expect(execTx)
            .to.emit(mocQueue, "OperationError")
            .withArgs(operId, ERROR_SELECTOR.INSUFFICIENT_TP_TO_MINT, "Insufficient tp to mint");
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
