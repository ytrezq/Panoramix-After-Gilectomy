import hre, { getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/dist/types";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../../helpers/assertHelper";
import {
  Balance,
  getNetworkDeployParams,
  ERROR_SELECTOR,
  ethersGetBalance,
  OperId,
  OperType,
  BaseSetupFunction,
  finalFixturedDescribe,
  ERRORS,
  noVendor,
} from "../../helpers/utils";
import { MocCACoinbase, MocCARC20, MocQueue, MocRC20 } from "../../../typechain";

const swapTCforTPQueueBehavior = function (setup: BaseSetupFunction) {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let tps: MocRC20[];
  let mocQueue: MocQueue;
  let operId: OperId;
  let alice: Address;
  let bob: Address;
  let assertACResult: any;
  let execTx: ContractTransactionResponse;
  let prevTCBalance: Balance;
  let prevACBalance: Balance;
  const TP_0 = 0;
  const {
    queueParams: {
      execCostParams: { swapTCforTPExecCost },
    },
    multiCollateralParams: { coinbaseExecFeeRecipient },
  } = getNetworkDeployParams(hre);
  describe("Feature: swap Collateral Token for Pegged Token", function () {
    async function baseSetup() {
      ({ mocFunctions, mocContracts } = await loadFixture(setup));
      ({ mocImpl, mocQueue, mocPeggedTokens: tps } = mocContracts);
      ({ alice, bob } = await getNamedAccounts());
      assertACResult = mocFunctions.assertACResult(-swapTCforTPExecCost);
    }
    describe("GIVEN Alice has 20 TC", function () {
      let queueTx: ContractTransactionResponse;
      async function aliceHasTCSetup() {
        await loadFixture(baseSetup);
        await mocFunctions.mintTCandTP({ from: bob, qTP: 1000 });
        await mocFunctions.mintTC({ from: alice, qTC: 100 });
      }
      describe("WHEN an user tries to execute a swap TC for TP operation without the queue", function () {
        it("THEN tx reverts only MocQueue can execute operations", async function () {
          await loadFixture(baseSetup);
          const swapTCforTPParams = {
            tp: tps[0].target.toString(),
            qTC: 1,
            qTPmin: 1,
            qACmax: 1,
            sender: alice,
            recipient: alice,
            vendor: noVendor,
          };
          await expect(mocImpl.execSwapTCforTP(swapTCforTPParams)).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.ONLY_QUEUE,
          );
        });
      });
      describe("WHEN she registers an Operation to swap 12 TC paying max 10 AC", function () {
        async function registerSwapTCSetup() {
          await loadFixture(aliceHasTCSetup);
          operId = await mocQueue.operIdCount();
          prevTCBalance = await mocFunctions.tcBalanceOf(alice);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          queueTx = await mocFunctions.swapTCforTP({ from: alice, qTC: 12, qACmax: 10, execute: false });
        }
        finalFixturedDescribe(registerSwapTCSetup, "(Assertions)", function () {
          it("THEN an operation queued event is emitted", async function () {
            await expect(queueTx)
              .to.emit(mocQueue, "OperationQueued")
              .withArgs(mocImpl.target.toString(), operId, OperType.swapTCforTP);
          });
          it("THEN Alice TC balance decreases by 12, as her funds are locked", async function () {
            assertPrec(await mocFunctions.tcBalanceOf(alice), 88);
          });
          it("THEN Bucket balance increases by 12, as the funds are now locked there", async function () {
            assertPrec(await mocFunctions.tcBalanceOf(mocImpl.target.toString()), 12);
          });
          it("THEN AC balance locked is 10 AC", async function () {
            assertPrec(await mocImpl.qACLockedInPending(), 10);
          });
        });
        describe("WHEN the operation is executed", function () {
          let execFeeRecipientBalanceBefore: Balance;
          before(async function () {
            await loadFixture(registerSwapTCSetup);
            execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
            await mocFunctions.executeQueue();
          });
          it("THEN Alice TC balance doesn't change", async function () {
            assertPrec(await mocFunctions.tcBalanceOf(alice), 88);
          });
          it("THEN Bucket TC balance is back to zero as tokes were burned", async function () {
            assertPrec(await mocFunctions.tcBalanceOf(mocImpl.target.toString()), 0);
          });
          it("THEN AC balance locked is 0 AC", async function () {
            assertPrec(await mocImpl.qACLockedInPending(), 0);
          });
          it("THEN the execFeeRecipient receives the corresponding execution fees", async function () {
            const mocQueueBalance = await ethersGetBalance(mocQueue.target.toString());
            expect(mocQueueBalance).to.be.equal(0);
            const execFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
            expect(execFeeRecipientBalanceAfter).to.be.equal(swapTCforTPExecCost + execFeeRecipientBalanceBefore);
          });
        });
        describe("AND Pegged Token has been revaluated leaving the protocol below coverage", function () {
          // this test is to check that tx doesn't fail because underflow doing totalACAvailable - lckAC
          async function revaluedTPSetup() {
            await loadFixture(registerSwapTCSetup);
            await mocFunctions.pokePrice(TP_0, "0.00000001");
          }
          describe("AND execution is evaluated", function () {
            before(async function () {
              await loadFixture(revaluedTPSetup);
              execTx = await mocFunctions.executeQueue();
            });
            it("THEN Operations fails with Low Coverage, and Operation Error event is emitted", async function () {
              await expect(execTx)
                .to.emit(mocQueue, "OperationError")
                .withArgs(operId, ERROR_SELECTOR.LOW_COVERAGE, "Low coverage");
            });
            it("THEN TC and AC are returned", async function () {
              assertPrec(prevTCBalance, await mocFunctions.tcBalanceOf(alice));
              assertACResult(prevACBalance, await mocFunctions.acBalanceOf(alice));
            });
          });
        });
      });
      describe("WHEN she registers an Operation to swap 12 TC with only 0.01 AC", function () {
        async function registerSwaptTCSetup() {
          await loadFixture(aliceHasTCSetup);
          operId = await mocQueue.operIdCount();
          prevTCBalance = await mocFunctions.tcBalanceOf(alice);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          queueTx = await mocFunctions.swapTCforTP({ from: alice, qTC: 12, qACmax: 0.01, execute: false });
        }
        describe("AND execution is evaluated", function () {
          before(async function () {
            await loadFixture(registerSwaptTCSetup);
            execTx = await mocFunctions.executeQueue();
          });
          it("THEN Operations fails with Insufficient qac sent, and Operation Error event is emitted", async function () {
            await expect(execTx)
              .to.emit(mocQueue, "OperationError")
              .withArgs(operId, ERROR_SELECTOR.INSUFFICIENT_QAC_SENT, "Insufficient qac sent");
          });
          it("THEN TC and AC are returned", async function () {
            assertPrec(prevTCBalance, await mocFunctions.tcBalanceOf(alice));
            assertACResult(prevACBalance, await mocFunctions.acBalanceOf(alice));
          });
        });
      });
      describe("WHEN she registers an Operation to swap 1 TC expecting at least 10000 TPs", function () {
        async function swapTCForTPOpSetup() {
          await loadFixture(aliceHasTCSetup);
          operId = await mocQueue.operIdCount();
          prevTCBalance = await mocFunctions.tcBalanceOf(alice);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          queueTx = await mocFunctions.swapTCforTP({ from: alice, qTC: 1, qTPmin: 10000, execute: false });
        }
        describe("AND execution is evaluated", function () {
          before(async function () {
            await loadFixture(swapTCForTPOpSetup);
            execTx = await mocFunctions.executeQueue();
          });
          it("THEN Operations fails with qTP below minimum required, and Operation Error event is emitted", async function () {
            await expect(execTx)
              .to.emit(mocQueue, "OperationError")
              .withArgs(operId, ERROR_SELECTOR.QTP_BELOW_MINIMUM, "qTp below minimum required");
          });
          it("THEN TC and AC are returned", async function () {
            assertPrec(prevTCBalance, await mocFunctions.tcBalanceOf(alice));
            assertACResult(prevACBalance, await mocFunctions.acBalanceOf(alice));
          });
        });
      });
    });
  });
};

export { swapTCforTPQueueBehavior };
