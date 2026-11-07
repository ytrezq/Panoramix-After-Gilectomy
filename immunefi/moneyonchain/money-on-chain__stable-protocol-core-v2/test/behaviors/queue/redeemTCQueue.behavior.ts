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
  MoCContracts,
  MoCFunctions,
  BaseSetupFunction,
  finalFixturedDescribe,
  ERRORS,
  noVendor,
} from "../../helpers/utils";
import { MocCACoinbase, MocCARC20, MocQueue } from "../../../typechain";

const redeemTCQueueBehavior = function (setup: BaseSetupFunction) {
  let mocFunctions: MoCFunctions;
  let mocContracts: MoCContracts;
  let mocImpl: MocCACoinbase | MocCARC20;
  let mocQueue: MocQueue;
  let operId: OperId;
  let deployer: Address;
  let alice: Address;
  let execTx: ContractTransactionResponse;
  let prevTCBalance: Balance;
  const TP_0 = 0;
  const {
    queueParams: {
      execCostParams: { tcRedeemExecCost },
    },
    multiCollateralParams: { coinbaseExecFeeRecipient },
  } = getNetworkDeployParams(hre);
  describe("Feature: redeem Collateral Token", function () {
    async function baseSetup() {
      ({ mocFunctions, mocContracts } = await loadFixture(setup));
      ({ mocImpl, mocQueue } = mocContracts);
      ({ deployer, alice } = await getNamedAccounts());
    }
    describe("GIVEN Alice has 20 TC", function () {
      async function aliceHasTCSetup() {
        await loadFixture(baseSetup);
        await mocFunctions.mintTC({ from: alice, qTC: 20 });
      }
      describe("WHEN an user tries to execute a redeem TC operation without the queue", function () {
        it("THEN tx reverts only MocQueue can execute operations", async function () {
          await loadFixture(baseSetup);
          const redeemTCParams = {
            qTC: 1,
            qACmin: 1,
            sender: deployer,
            recipient: deployer,
            vendor: noVendor,
          };
          await expect(mocImpl.execRedeemTC(redeemTCParams)).to.be.revertedWithCustomError(mocImpl, ERRORS.ONLY_QUEUE);
        });
      });
      describe("WHEN alice registers a redeems 20 TC Operation, expecting at least 21 AC", function () {
        before(async function () {
          await loadFixture(aliceHasTCSetup);
          operId = await mocQueue.operIdCount();
          prevTCBalance = await mocFunctions.tcBalanceOf(alice);
          await mocFunctions.redeemTC({ from: alice, qTC: 20, qACmin: 21, execute: false });
        });
        describe("AND execution is evaluated", function () {
          before(async function () {
            execTx = await mocFunctions.executeQueue();
          });
          it("THEN Operations fails with qAC below min expected, and Operation Error event is emitted", async function () {
            await expect(execTx)
              .to.emit(mocQueue, "OperationError")
              .withArgs(operId, ERROR_SELECTOR.QAC_BELOW_MINIMUM, "qAC below minimum required");
          });
          it("THEN TC is returned", async function () {
            assertPrec(prevTCBalance, await mocFunctions.tcBalanceOf(alice));
          });
        });
      });

      describe("AND there are 200 TP0", function () {
        async function mintTP0Setup() {
          await loadFixture(aliceHasTCSetup);
          await mocFunctions.mintTP({ from: deployer, qTP: 200 });
        }
        describe("WHEN Alice registers a redeem Operation for her TCs", function () {
          async function registerRedeemSetup() {
            await loadFixture(mintTP0Setup);
            operId = await mocQueue.operIdCount();
            prevTCBalance = await mocFunctions.tcBalanceOf(alice);
            await mocFunctions.redeemTC({ from: alice, qTC: 20, execute: false });
          }
          describe("AND execution is evaluated", function () {
            before(async function () {
              await loadFixture(registerRedeemSetup);
              execTx = await mocFunctions.executeQueue();
            });
            it("THEN Operations fails with Insufficient tc to redeem, and Operation Error event is emitted", async function () {
              await expect(execTx)
                .to.emit(mocQueue, "OperationError")
                .withArgs(operId, ERROR_SELECTOR.INSUFFICIENT_TC_TO_REDEEM, "Insufficient tc to redeem");
            });
            it("THEN TC is returned", async function () {
              assertPrec(prevTCBalance, await mocFunctions.tcBalanceOf(alice));
            });
          });
        });
        describe("AND Pegged Token revaluates", function () {
          async function TPRevaluedSetup() {
            await loadFixture(mintTP0Setup);
            await mocFunctions.pokePrice(TP_0, "35");
          }
          describe("WHEN Alice registers a redeem Operation for her TCs", function () {
            let alicePrevBalance: Balance;
            async function registerRedeemSetup() {
              await loadFixture(TPRevaluedSetup);
              operId = await mocQueue.operIdCount();
              prevTCBalance = await mocFunctions.tcBalanceOf(alice);
              alicePrevBalance = await ethersGetBalance(alice);
              await mocFunctions.redeemTC({ from: alice, qTC: 20, execute: false });
            }
            describe("AND execution is evaluated", function () {
              before(async function () {
                await loadFixture(registerRedeemSetup);
                execTx = await mocFunctions.executeQueue();
              });
              it("THEN Operations fails with LowCoverage, and Operation Error event is emitted", async function () {
                await expect(execTx)
                  .to.emit(mocQueue, "OperationError")
                  .withArgs(operId, ERROR_SELECTOR.LOW_COVERAGE, "Low coverage");
              });
              it("THEN TC is returned", async function () {
                assertPrec(prevTCBalance, await mocFunctions.tcBalanceOf(alice));
              });
              it("THEN alice spent the execution fees", async function () {
                assertPrec(await ethersGetBalance(alice), alicePrevBalance - tcRedeemExecCost);
              });
            });
          });
        });
      });

      describe("WHEN she registers an Operation to redeems 12 TC", function () {
        let queueTx: ContractTransactionResponse;
        let execFeeRecipientBalanceBefore: Balance;
        async function registerRedeemSetup() {
          await loadFixture(aliceHasTCSetup);
          operId = await mocQueue.operIdCount();
          prevTCBalance = await mocFunctions.tcBalanceOf(alice);
          queueTx = await mocFunctions.redeemTC({ from: alice, qTC: 12, execute: false });
        }
        finalFixturedDescribe(registerRedeemSetup, "(Assertions)", function () {
          it("THEN an operation queued event is emitted", async function () {
            await expect(queueTx)
              .to.emit(mocQueue, "OperationQueued")
              .withArgs(mocImpl.target.toString(), operId, OperType.redeemTC);
          });
          it("THEN Alice TC balance decreases by 12, as her funds are locked", async function () {
            assertPrec(prevTCBalance - (await mocFunctions.tcBalanceOf(alice)), 12);
          });
          it("THEN Bucket balance increases by 12, as the funds are now locked there", async function () {
            assertPrec(await mocFunctions.tcBalanceOf(mocImpl.target.toString()), 12);
          });
        });
        describe("WHEN the operation is executed", function () {
          before(async function () {
            await loadFixture(registerRedeemSetup);
            execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
            await mocFunctions.executeQueue();
          });
          it("THEN Alice TC balance doesn't change", async function () {
            assertPrec(prevTCBalance - (await mocFunctions.tcBalanceOf(alice)), 12);
          });
          it("THEN Bucket TC balance is back to zero as tokes were burned", async function () {
            assertPrec(await mocFunctions.tcBalanceOf(mocImpl.target.toString()), 0);
          });
          it("THEN the execFeeRecipient receives the corresponding execution fees", async function () {
            const mocQueueBalance = await ethersGetBalance(mocQueue.target.toString());
            expect(mocQueueBalance).to.be.equal(0);
            const execFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
            expect(execFeeRecipientBalanceAfter).to.be.equal(tcRedeemExecCost + execFeeRecipientBalanceBefore);
          });
        });
      });
    });
  });
};

export { redeemTCQueueBehavior };
