import hre, { getNamedAccounts, ethers } from "hardhat";
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
  noVendor,
  ERRORS,
  pEth,
} from "../../helpers/utils";
import { ERC20Mock, MocCACoinbase, MocCARC20, MocQueue, MocRC20 } from "../../../typechain";

const redeemTPQueueBehavior = function () {
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let tps: MocRC20[];
  let mocQueue: MocQueue;
  let operId: OperId;
  let alice: Address;
  let bob: Address;
  let execTx: ContractTransactionResponse;
  let prevTPBalance: Balance;
  const TP_0 = 0;
  const {
    queueParams: {
      execCostParams: { tpRedeemExecCost },
    },
    multiCollateralParams: { coinbaseExecFeeRecipient },
  } = getNetworkDeployParams(hre);
  describe("Feature: redeem Pegged Token", function () {
    beforeEach(async function () {
      mocFunctions = this.mocFunctions;
      ({ mocImpl, mocQueue, mocPeggedTokens: tps } = this.mocContracts);
      ({ alice, bob } = await getNamedAccounts());
    });
    describe("GIVEN there are 100 TC and Alice has 20 TP", function () {
      let queueTx: ContractTransactionResponse;
      beforeEach(async function () {
        await mocFunctions.mintTC({ from: bob, qTC: 100 });
        await mocFunctions.mintTP({ from: alice, qTP: 20 });
      });
      describe("WHEN an user tries to execute a redeem TP operation without the queue", function () {
        it("THEN tx reverts only MocQueue can execute operations", async function () {
          const redeemTPParams = {
            tp: tps[0].target.toString(),
            qTP: 1,
            qACmin: 1,
            sender: alice,
            recipient: alice,
            vendor: noVendor,
          };
          await expect(mocImpl.execRedeemTP(redeemTPParams)).to.be.revertedWithCustomError(mocImpl, ERRORS.ONLY_QUEUE);
        });
      });
      describe("WHEN alice registers a redeems 20 TP Operation, expecting at least 21 AC", function () {
        beforeEach(async function () {
          operId = await mocQueue.operIdCount();
          prevTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
          await mocFunctions.redeemTP({ from: alice, qTP: 20, qACmin: 21, execute: false });
        });
        describe("AND execution is evaluated", function () {
          beforeEach(async function () {
            execTx = await mocFunctions.executeQueue();
          });
          it("THEN Operations fails with qAC below min expected, and Operation Error event is emitted", async function () {
            await expect(execTx)
              .to.emit(mocQueue, "OperationError")
              .withArgs(operId, ERROR_SELECTOR.QAC_BELOW_MINIMUM, "qAC below minimum required");
          });
          it("THEN TP is returned", async function () {
            assertPrec(prevTPBalance, await mocFunctions.tpBalanceOf(TP_0, alice));
          });
        });
      });
      describe("AND Pegged Token revaluates", function () {
        beforeEach(async function () {
          await mocFunctions.mintTP({ from: bob, qTP: 20000 });
          await mocFunctions.pokePrice(TP_0, "0.1");
        });
        describe("WHEN Alice registers a redeem Operation for her TPs", function () {
          let alicePrevBalance: Balance;
          beforeEach(async function () {
            operId = await mocQueue.operIdCount();
            prevTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
            alicePrevBalance = await ethersGetBalance(alice);
            await mocFunctions.redeemTP({ from: alice, qTP: 20, execute: false });
          });
          describe("AND execution is evaluated", function () {
            beforeEach(async function () {
              execTx = await mocFunctions.executeQueue();
            });
            it("THEN Operations fails with LowCoverage, and Operation Error event is emitted", async function () {
              await expect(execTx)
                .to.emit(mocQueue, "OperationError")
                .withArgs(operId, ERROR_SELECTOR.LOW_COVERAGE, "Low coverage");
            });
            it("THEN TP is returned", async function () {
              assertPrec(prevTPBalance, await mocFunctions.tpBalanceOf(TP_0, alice));
            });
            it("THEN alice spent the execution fees", async function () {
              assertPrec(await ethersGetBalance(alice), alicePrevBalance - tpRedeemExecCost);
            });
          });
        });
      });

      describe("Feature: TP validation prevents attacker-controlled tokens (CVE fix)", function () {
        let fakeTp: ERC20Mock;

        describe("GIVEN an attacker deploys a fake ERC20 token NOT registered as TP", function () {
          beforeEach(async function () {
            const ERC20MockFactory = await ethers.getContractFactory("ERC20Mock");
            fakeTp = (await ERC20MockFactory.deploy()) as unknown as ERC20Mock;

            const qFakeTP = pEth(100);
            await fakeTp.mint(alice, qFakeTP);
            await fakeTp.connect(await ethers.getSigner(alice)).approve(mocImpl.target.toString(), qFakeTP);
          });

          it("THEN queueing a redeemTP with the unregistered token reverts with InvalidAddress", async function () {
            // _lockTPInPending calls _tpi() which reverts for unregistered tokens,
            // preventing attacker-controlled tokens from ever entering the queue.
            await expect(
              mocFunctions.redeemTP({ tp: fakeTp, from: alice, qTP: 100, execute: false }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.INVALID_ADDRESS);
          });
        });
      });

      describe("WHEN she registers an Operation to redeems 12 TP", function () {
        beforeEach(async function () {
          operId = await mocQueue.operIdCount();
          queueTx = await mocFunctions.redeemTP({ from: alice, qTP: 12, execute: false });
        });
        it("THEN an operation queued event is emitted", async function () {
          await expect(queueTx)
            .to.emit(mocQueue, "OperationQueued")
            .withArgs(mocImpl.target.toString(), operId, OperType.redeemTP);
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
            expect(execFeeRecipientBalanceAfter).to.be.equal(tpRedeemExecCost + execFeeRecipientBalanceBefore);
          });
        });
      });
    });
  });
};

export { redeemTPQueueBehavior };
