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
  BaseSetupFunction,
  noVendor,
  ERRORS,
  pEth,
} from "../../helpers/utils";
import { ERC20Mock, MocCACoinbase, MocCARC20, MocQueue, MocRC20 } from "../../../typechain";

const swapTPforTPQueueBehavior = function (setup: BaseSetupFunction) {
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let tps: MocRC20[];
  let mocQueue: MocQueue;
  let operId: OperId;
  let alice: Address;
  let bob: Address;
  let assertACResult: any;
  let execTx: ContractTransactionResponse;
  let prevTPBalance: Balance;
  let prevACBalance: Balance;
  const TP_0 = 0;
  const {
    queueParams: {
      execCostParams: { swapTPforTPExecCost },
    },
    multiCollateralParams: { coinbaseExecFeeRecipient },
  } = getNetworkDeployParams(hre);
  describe("Feature: swap Pegged Token for another Pegged Token", function () {
    async function fixture() {
      let mocContracts;
      ({ mocFunctions, mocContracts } = await loadFixture(setup));
      ({ mocImpl, mocQueue, mocPeggedTokens: tps } = mocContracts);
      ({ alice, bob } = await getNamedAccounts());
      assertACResult = mocFunctions.assertACResult(-swapTPforTPExecCost);
    }
    beforeEach(async function () {
      await loadFixture(fixture);
    });
    describe("GIVEN Alice has 20 TP", function () {
      let queueTx: ContractTransactionResponse;
      beforeEach(async function () {
        await mocFunctions.mintTC({ from: bob, qTC: 3000 });
        await mocFunctions.mintTP({ from: alice, qTP: 20 });
      });
      describe("WHEN an user tries to execute a swap TP for TP operation without the queue", function () {
        it("THEN tx reverts only MocQueue can execute operations", async function () {
          const swapTPforTPParams = {
            tpFrom: tps[0].target.toString(),
            tpTo: tps[0].target.toString(),
            qTP: 1,
            qTPmin: 1,
            qACmax: 1,
            sender: alice,
            recipient: alice,
            vendor: noVendor,
          };
          await expect(mocImpl.execSwapTPforTP(swapTPforTPParams)).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.ONLY_QUEUE,
          );
        });
      });
      describe("Feature: TP validation prevents attacker-controlled tokens (CVE fix)", function () {
        let fakeTp: ERC20Mock;

        beforeEach(async function () {
          const ERC20MockFactory = await ethers.getContractFactory("ERC20Mock");
          fakeTp = (await ERC20MockFactory.deploy()) as unknown as ERC20Mock;
          await fakeTp.mint(alice, pEth(100));
        });

        it("THEN queueing a swapTPforTP with an unregistered input TP reverts before persisting it", async function () {
          const prevOperIdCount = await mocQueue.operIdCount();
          const prevFirstOperId = await mocQueue.firstOperId();

          // _swapTPforTPtoViaVendor calls _lockTPInPending for tpFrom, which rejects unregistered TP tokens.
          await expect(
            mocFunctions.swapTPforTP({ tpFrom: fakeTp, iTo: TP_0, from: alice, qTP: 1, execute: false }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.INVALID_ADDRESS);

          expect(await mocQueue.operIdCount()).to.be.equal(prevOperIdCount);
          expect(await mocQueue.firstOperId()).to.be.equal(prevFirstOperId);
        });
      });
      describe("WHEN she registers an Operation to swap 12 TP0 for TP1", function () {
        beforeEach(async function () {
          operId = await mocQueue.operIdCount();
          queueTx = await mocFunctions.swapTPforTP({ from: alice, qTP: 12, execute: false });
        });
        it("THEN an operation queued event is emitted", async function () {
          await expect(queueTx)
            .to.emit(mocQueue, "OperationQueued")
            .withArgs(mocImpl.target.toString(), operId, OperType.swapTPforTP);
        });
        it("THEN Alice TP balance decreases by 12, as her funds are locked", async function () {
          assertPrec(await mocFunctions.tpBalanceOf(TP_0, alice), 8);
        });
        it("THEN Bucket balance increases by 12, as the funds are now locked there", async function () {
          assertPrec(await mocFunctions.tpBalanceOf(TP_0, mocImpl.target.toString()), 12);
        });
        describe("WHEN the operation is executed", function () {
          let execFeeRecipientBalanceBefore: Balance;
          beforeEach(async function () {
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
            expect(execFeeRecipientBalanceAfter).to.be.equal(swapTPforTPExecCost + execFeeRecipientBalanceBefore);
          });
        });
      });
      describe("WHEN she registers an Operation to swap 12 TP0 for TP1 with only 0.0001 AC", function () {
        beforeEach(async function () {
          operId = await mocQueue.operIdCount();
          prevTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          queueTx = await mocFunctions.swapTPforTP({ from: alice, qTP: 12, qACmax: 0.0001, execute: false });
        });
        describe("AND execution is evaluated", function () {
          beforeEach(async function () {
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
      describe("WHEN she registers an Operation to swap 23500 TP0 expecting at least 526 TP1", function () {
        beforeEach(async function () {
          await mocFunctions.mintTP({ from: alice, qTP: 23480 });
          operId = await mocQueue.operIdCount();
          prevTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          queueTx = await mocFunctions.swapTPforTP({
            from: alice,
            qTP: 23500,
            qTPmin: 526,
            execute: false,
          });
        });
        describe("AND execution is evaluated", function () {
          beforeEach(async function () {
            execTx = await mocFunctions.executeQueue();
          });
          it("THEN Operations fails with qTC below minimum required, and Operation Error event is emitted", async function () {
            await expect(execTx)
              .to.emit(mocQueue, "OperationError")
              .withArgs(operId, ERROR_SELECTOR.QTP_BELOW_MINIMUM, "qTp below minimum required");
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

export { swapTPforTPQueueBehavior };
