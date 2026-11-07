import hre, { getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/dist/types";
import { expect } from "chai";
import { assertPrec } from "../../helpers/assertHelper";
import {
  Balance,
  getNetworkDeployParams,
  ERROR_SELECTOR,
  ethersGetBalance,
  OperId,
  OperType,
  ERRORS,
  noVendor,
} from "../../helpers/utils";
import { MocCACoinbase, MocCARC20, MocQueue, MocRC20 } from "../../../typechain";

const mintTPQueueBehavior = function () {
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let tps: MocRC20[];
  let mocQueue: MocQueue;
  let operId: OperId;
  let deployer: Address;
  let alice: Address;
  let assertACResult: any;
  let execTx: ContractTransactionResponse;
  let prevACBalance: Balance;
  const TP_0 = 0;
  const {
    queueParams: {
      execCostParams: { tpMintExecCost },
    },
    multiCollateralParams: { coinbaseExecFeeRecipient },
  } = getNetworkDeployParams(hre);
  describe("Feature: mint Pegged Token", function () {
    beforeEach(async function () {
      mocFunctions = this.mocFunctions;
      ({ mocImpl, mocQueue, mocPeggedTokens: tps } = this.mocContracts);
      ({ deployer, alice } = await getNamedAccounts());
      assertACResult = mocFunctions.assertACResult(-tpMintExecCost);
    });
    describe("WHEN an user tries to execute a mint TP operation without the queue", function () {
      it("THEN tx reverts only MocQueue can execute operations", async function () {
        const mintTPParams = {
          tp: tps[0].target.toString(),
          qTP: 1,
          qACmax: 1,
          sender: deployer,
          recipient: deployer,
          vendor: noVendor,
        };
        await expect(mocImpl.execMintTP(mintTPParams)).to.be.revertedWithCustomError(mocImpl, ERRORS.ONLY_QUEUE);
      });
    });
    describe("WHEN alice sends 100 Asset to mint 100 TP but there is not collateral in the protocol", function () {
      beforeEach(async function () {
        operId = await mocQueue.operIdCount();
        prevACBalance = await mocFunctions.acBalanceOf(alice);
        execTx = await mocFunctions.mintTP({ from: alice, qTP: 100, qACmax: 100 });
      });
      it("THEN Operations fails as there is not enough TP to mint, and Operation Error event is emitted", async function () {
        await expect(execTx)
          .to.emit(mocQueue, "OperationError")
          .withArgs(operId, ERROR_SELECTOR.INSUFFICIENT_TP_TO_MINT, "Insufficient tp to mint");
      });
      it("THEN AC is returned", async function () {
        assertPrec(await mocImpl.qACLockedInPending(), 0);
        assertACResult(prevACBalance, await mocFunctions.acBalanceOf(alice));
      });
    });
    describe("WHEN an user sends 100 AC to put a mint 10 TP operation in the queue", function () {
      let queueTx: ContractTransactionResponse;
      beforeEach(async function () {
        // add collateral to be able to mint TP
        await mocFunctions.mintTC({ from: deployer, qTC: 100 });
        await mocFunctions.mintTP({ from: alice, qTP: 100 });
        operId = await mocQueue.operIdCount();
        // Register a mintTP operation without executing it
        prevACBalance = await mocFunctions.acBalanceOf(alice);
        queueTx = await mocFunctions.mintTP({ from: alice, qTP: 10, qACmax: 100, execute: false });
      });
      it("THEN AC balance locked is 100 AC", async function () {
        assertPrec(await mocImpl.qACLockedInPending(), 100);
      });
      it("THEN an operation queued event is emitted", async function () {
        await expect(queueTx)
          .to.emit(mocQueue, "OperationQueued")
          .withArgs(mocImpl.target.toString(), operId, OperType.mintTP);
      });
      describe("AND operation is executed", function () {
        let execFeeRecipientBalanceBefore: Balance;
        beforeEach(async function () {
          execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
          await mocFunctions.executeQueue();
        });
        it("THEN AC balance locked is 0 AC", async function () {
          assertPrec(await mocImpl.qACLockedInPending(), 0);
        });
        it("THEN the execFeeRecipient receives the corresponding execution fees", async function () {
          const mocQueueBalance = await ethersGetBalance(mocQueue.target.toString());
          expect(mocQueueBalance).to.be.equal(0);
          const execFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
          expect(execFeeRecipientBalanceAfter).to.be.equal(tpMintExecCost + execFeeRecipientBalanceBefore);
        });
      });
      describe("AND Collateral Asset relation with Pegged Token price falls leaving the system below coverage", function () {
        beforeEach(async function () {
          await mocFunctions.pokePrice(TP_0, "0.01");
        });
        describe("AND execution is evaluated", function () {
          beforeEach(async function () {
            execTx = await mocFunctions.executeQueue();
          });
          it("THEN Operations fails with Low coverage, and Operation Error event is emitted", async function () {
            await expect(execTx)
              .to.emit(mocQueue, "OperationError")
              .withArgs(operId, ERROR_SELECTOR.LOW_COVERAGE, "Low coverage");
          });
          it("THEN AC is returned", async function () {
            assertPrec(await mocImpl.qACLockedInPending(), 0);
            assertACResult(prevACBalance, await mocFunctions.acBalanceOf(alice));
          });
        });
      });
    });
    describe("WHEN an user registers a mint 10 TP operation, sending only 0.01 AC", function () {
      beforeEach(async function () {
        // add collateral to be able to mint TP
        await mocFunctions.mintTC({ from: deployer, qTC: 100 });
        operId = await mocQueue.operIdCount();
        prevACBalance = await mocFunctions.acBalanceOf(alice);
        await mocFunctions.mintTP({ from: alice, qTP: 10, qACmax: 0.01, execute: false });
      });
      describe("AND execution is evaluated", function () {
        beforeEach(async function () {
          execTx = await mocFunctions.executeQueue();
        });
        it("THEN Operations fails with InsufficientQacSent, and Operation Error event is emitted", async function () {
          await expect(execTx)
            .to.emit(mocQueue, "OperationError")
            .withArgs(operId, ERROR_SELECTOR.INSUFFICIENT_QAC_SENT, "Insufficient qac sent");
        });
        it("THEN AC is returned", async function () {
          assertPrec(await mocImpl.qACLockedInPending(), 0);
          assertACResult(prevACBalance, await mocFunctions.acBalanceOf(alice));
        });
      });
    });
  });
};

export { mintTPQueueBehavior };
