import hre, { ethers, getNamedAccounts } from "hardhat";
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
  finalFixturedDescribe,
  BaseSetupFunction,
  ERRORS,
  noVendor,
  pEth,
} from "../../helpers/utils";
import { ERC20Mock, MocCACoinbase, MocCARC20, MocQueue, MocRC20 } from "../../../typechain";

const swapTPforTCQueueBehavior = function (setup: BaseSetupFunction) {
  let mocFunctions: any;
  let mocContracts: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let tps: MocRC20[];
  let mocQueue: MocQueue;
  let operId: OperId;
  let alice: Address;
  let assertACResult: any;
  let execTx: ContractTransactionResponse;
  let prevTPBalance: Balance;
  let prevACBalance: Balance;
  const TP_0 = 0;
  const {
    queueParams: {
      execCostParams: { swapTPforTCExecCost },
    },
    multiCollateralParams: { coinbaseExecFeeRecipient },
  } = getNetworkDeployParams(hre);
  describe("Feature: swap Pegged Token for Collateral Token", function () {
    async function baseSetup() {
      ({ mocFunctions, mocContracts } = await loadFixture(setup));
      ({ mocImpl, mocQueue, mocPeggedTokens: tps } = mocContracts);
      ({ alice } = await getNamedAccounts());
      assertACResult = mocFunctions.assertACResult(-swapTPforTCExecCost);
    }
    describe("GIVEN Alice has 20 TP", function () {
      let queueTx: ContractTransactionResponse;
      async function aliceHasTPSetup() {
        await loadFixture(baseSetup);
        await mocFunctions.mintTC({ from: alice, qTC: 100 });
        await mocFunctions.mintTP({ from: alice, qTP: 20 });
      }
      describe("WHEN an user tries to execute a swap TP for TC operation without the queue", function () {
        it("THEN tx reverts only MocQueue can execute operations", async function () {
          await loadFixture(baseSetup);
          const swapTPforTCParams = {
            tp: tps[0].target.toString(),
            qTP: 1,
            qTCmin: 1,
            qACmax: 1,
            sender: alice,
            recipient: alice,
            vendor: noVendor,
          };
          await expect(mocImpl.execSwapTPforTC(swapTPforTCParams)).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.ONLY_QUEUE,
          );
        });
      });
      describe("Feature: TP validation prevents attacker-controlled tokens (CVE fix)", function () {
        let fakeTp: ERC20Mock;

        async function fakeTPSetup() {
          await loadFixture(aliceHasTPSetup);
          const ERC20MockFactory = await ethers.getContractFactory("ERC20Mock");
          fakeTp = (await ERC20MockFactory.deploy()) as unknown as ERC20Mock;
          await fakeTp.mint(alice, pEth(100));
        }

        it("THEN queueing a swapTPforTC with an unregistered TP reverts before persisting it", async function () {
          await loadFixture(fakeTPSetup);
          const prevOperIdCount = await mocQueue.operIdCount();
          const prevFirstOperId = await mocQueue.firstOperId();

          // _swapTPforTCtoViaVendor calls _lockTPInPending, which rejects unregistered TP tokens.
          await expect(
            mocFunctions.swapTPforTC({ tp: fakeTp, from: alice, qTP: 1, execute: false }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.INVALID_ADDRESS);

          expect(await mocQueue.operIdCount()).to.be.equal(prevOperIdCount);
          expect(await mocQueue.firstOperId()).to.be.equal(prevFirstOperId);
        });
      });
      describe("WHEN she registers an Operation to swap 12 TP for TC paying max 10 AC", function () {
        async function operationToSwapRegisteredSetup() {
          await loadFixture(aliceHasTPSetup);
          operId = await mocQueue.operIdCount();
          prevTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          queueTx = await mocFunctions.swapTPforTC({ from: alice, qTP: 12, qACmax: 10, execute: false });
        }
        finalFixturedDescribe(operationToSwapRegisteredSetup, "(Assertions)", function () {
          it("THEN an operation queued event is emitted", async function () {
            await expect(queueTx)
              .to.emit(mocQueue, "OperationQueued")
              .withArgs(mocImpl.target.toString(), operId, OperType.swapTPforTC);
          });
          it("THEN Alice TP balance decreases by 12, as her funds are locked", async function () {
            assertPrec(await mocFunctions.tpBalanceOf(TP_0, alice), 8);
          });
          it("THEN Bucket balance increases by 12, as the funds are now locked there", async function () {
            assertPrec(await mocFunctions.tpBalanceOf(TP_0, mocImpl.target.toString()), 12);
          });
        });
        describe("WHEN the operation is executed", function () {
          let execFeeRecipientBalanceBefore: Balance;
          before(async function () {
            await loadFixture(operationToSwapRegisteredSetup);
            execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
            await mocFunctions.executeQueue();
          });
          it("THEN Alice TP balance doesn't change", async function () {
            assertPrec(await mocFunctions.tpBalanceOf(TP_0, alice), 8);
          });
          it("THEN Bucket TP balance is back to zero as tokes were burned", async function () {
            assertPrec(await mocFunctions.tpBalanceOf(TP_0, mocImpl.target.toString()), 0);
          });
          it("THEN the execFeeRecipient receives the corresponding execution fees", async function () {
            const mocQueueBalance = await ethersGetBalance(mocQueue.target.toString());
            expect(mocQueueBalance).to.be.equal(0);
            const execFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
            expect(execFeeRecipientBalanceAfter).to.be.equal(swapTPforTCExecCost + execFeeRecipientBalanceBefore);
          });
        });
        describe("AND Pegged Token has been revaluated leaving the protocol below coverage", function () {
          // this test is to check that tx doesn't fail because underflow doing totalACAvailable - lckAC
          async function TPRevaluedSetup() {
            await loadFixture(operationToSwapRegisteredSetup);
            await mocFunctions.pokePrice(TP_0, "0.00000001");
          }
          describe("AND execution is evaluated", function () {
            before(async function () {
              await loadFixture(TPRevaluedSetup);
              execTx = await mocFunctions.executeQueue();
            });
            it("THEN Operations fails with Low Coverage, and Operation Error event is emitted", async function () {
              await expect(execTx)
                .to.emit(mocQueue, "OperationError")
                .withArgs(operId, ERROR_SELECTOR.LOW_COVERAGE, "Low coverage");
            });
            it("THEN TP and AC are returned", async function () {
              assertPrec(prevTPBalance, await mocFunctions.tpBalanceOf(TP_0, alice));
              assertACResult(prevACBalance, await mocFunctions.acBalanceOf(alice));
            });
          });
        });
      });
      describe("WHEN she registers an Operation to swap 12 TP with only 0.0001 AC", function () {
        async function operationToSwapRegisteredSetup() {
          await loadFixture(aliceHasTPSetup);
          operId = await mocQueue.operIdCount();
          prevTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          queueTx = await mocFunctions.swapTPforTC({ from: alice, qTP: 12, qACmax: 0.0001, execute: false });
        }
        describe("AND execution is evaluated", function () {
          before(async function () {
            await loadFixture(operationToSwapRegisteredSetup);
            execTx = await mocFunctions.executeQueue();
          });
          it("THEN Operations fails with Insufficient qac sent, and Operation Error event is emitted", async function () {
            await expect(execTx)
              .to.emit(mocQueue, "OperationError")
              .withArgs(operId, ERROR_SELECTOR.INSUFFICIENT_QAC_SENT, "Insufficient qac sent");
          });
          it("THEN TP and AC are returned", async function () {
            assertPrec(prevTPBalance, await mocFunctions.tpBalanceOf(TP_0, alice));
            assertACResult(prevACBalance, await mocFunctions.acBalanceOf(alice));
          });
        });
      });
      describe("WHEN she registers an Operation to swap 1 TP expecting at least 10000 TCs", function () {
        async function operationToSwapRegisteredSetup() {
          await loadFixture(aliceHasTPSetup);
          operId = await mocQueue.operIdCount();
          prevTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          queueTx = await mocFunctions.swapTPforTC({ from: alice, qTP: 1, qTCmin: 10000, execute: false });
        }
        describe("AND execution is evaluated", function () {
          before(async function () {
            await loadFixture(operationToSwapRegisteredSetup);
            execTx = await mocFunctions.executeQueue();
          });
          it("THEN Operations fails with qTC below minimum required, and Operation Error event is emitted", async function () {
            await expect(execTx)
              .to.emit(mocQueue, "OperationError")
              .withArgs(operId, ERROR_SELECTOR.QTC_BELOW_MINIMUM, "qTc below minimum required");
          });
          it("THEN TP and AC are returned", async function () {
            assertPrec(prevTPBalance, await mocFunctions.tpBalanceOf(TP_0, alice));
            assertACResult(prevACBalance, await mocFunctions.acBalanceOf(alice));
          });
        });
      });
    });
  });
};

export { swapTPforTCQueueBehavior };
