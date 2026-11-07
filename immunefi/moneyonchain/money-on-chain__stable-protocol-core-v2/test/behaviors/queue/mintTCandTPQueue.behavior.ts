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
  MoCContracts,
  MoCFunctions,
  finalFixturedDescribe,
  ERRORS,
  noVendor,
} from "../../helpers/utils";
import { MocCACoinbase, MocCARC20, MocQueue, MocRC20 } from "../../../typechain";

const mintTCandTPQueueBehavior = function (setup: BaseSetupFunction) {
  let mocFunctions: MoCFunctions;
  let mocContracts: MoCContracts;
  let mocImpl: MocCACoinbase | MocCARC20;
  let mocQueue: MocQueue;
  let tps: MocRC20[];
  let operId: OperId;
  let deployer: Address;
  let alice: Address;
  let bob: Address;
  let assertACResult: any;
  let execTx: ContractTransactionResponse;
  let prevACBalance: Balance;
  const TP_0 = 0;
  const {
    queueParams: {
      execCostParams: { mintTCandTPExecCost },
    },
    multiCollateralParams: { coinbaseExecFeeRecipient },
  } = getNetworkDeployParams(hre);
  describe("Feature: joint Mint TC and TP operation", function () {
    async function mintTCAndTPOperationSetup() {
      ({ mocFunctions, mocContracts } = await loadFixture(setup));
      ({ mocImpl, mocQueue, mocPeggedTokens: tps } = mocContracts);
      ({ alice, bob, deployer } = await getNamedAccounts());
      assertACResult = mocFunctions.assertACResult(-mintTCandTPExecCost);
    }
    describe("WHEN an user tries to execute a mint TC and TP operation without the queue", function () {
      it("THEN tx reverts as only MocQueue can execute operations", async function () {
        await loadFixture(mintTCAndTPOperationSetup);
        const mintTCandTPParams = {
          tp: tps[TP_0].target.toString(),
          qTP: 1,
          qACmax: 1,
          sender: deployer,
          recipient: deployer,
          vendor: noVendor,
        };
        await expect(mocImpl.execMintTCandTP(mintTCandTPParams)).to.be.revertedWithCustomError(
          mocImpl,
          ERRORS.ONLY_QUEUE,
        );
      });
    });
    describe("WHEN Alice registers a mint 10 TC and 100 TP operation, sending only 1 AC", function () {
      async function registerMintSetup() {
        await loadFixture(mintTCAndTPOperationSetup);
        operId = await mocQueue.operIdCount();
        prevACBalance = await mocFunctions.acBalanceOf(alice);
        await mocFunctions.mintTCandTP({ from: alice, qTC: 10, qTP: 100, qACmax: 1, execute: false });
      }
      describe("AND execution is evaluated", function () {
        before(async function () {
          await loadFixture(registerMintSetup);
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

    describe("WHEN Alice registers a mint 10 TC and 100 TP operation, sending 100 AC", function () {
      let queueTx: ContractTransactionResponse;
      async function registerMintSetup() {
        await loadFixture(mintTCAndTPOperationSetup);
        operId = await mocQueue.operIdCount();
        queueTx = await mocFunctions.mintTCandTP({ from: alice, qTC: 10, qTP: 100, qACmax: 100, execute: false });
      }
      finalFixturedDescribe(registerMintSetup, "(Assertions)", function () {
        it("THEN nACcb is 0 AC", async function () {
          assertPrec(await mocImpl.nACcb(), 0);
        });
        it("THEN AC balance locked is 100 AC", async function () {
          assertPrec(await mocImpl.qACLockedInPending(), 100);
        });
        it("THEN an operation queued event is emitted", async function () {
          await expect(queueTx)
            .to.emit(mocQueue, "OperationQueued")
            .withArgs(mocImpl.target.toString(), operId, OperType.mintTCandTP);
        });
      });
      describe("AND queue execution is evaluated", function () {
        let execFeeRecipientBalanceBefore: Balance;
        before(async function () {
          await loadFixture(registerMintSetup);
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
          expect(execFeeRecipientBalanceAfter).to.be.equal(mintTCandTPExecCost + execFeeRecipientBalanceBefore);
        });
      });
    });
    describe("AND there are 10 TC and 100 TP on the protocol", function () {
      async function loadedProtocolSetup() {
        await loadFixture(mintTCAndTPOperationSetup);
        await mocFunctions.mintTCandTP({ from: bob, qTC: 10, qTP: 100, qACmax: 100 });
      }
      describe("WHEN Alice registers a mint 10 TC and 100 TP operation, sending 100 AC", function () {
        async function registerMintSetup() {
          await loadFixture(loadedProtocolSetup);
          operId = await mocQueue.operIdCount();
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          await mocFunctions.mintTCandTP({ from: alice, qTC: 10, qTP: 100, qACmax: 100, execute: false });
        }
        describe("AND Collateral Asset relation with Pegged Token price falls leaving the system below coverage", function () {
          async function priceChangesSetup() {
            await loadFixture(registerMintSetup);
            await mocFunctions.pokePrice(TP_0, "0.01");
          }
          describe("AND execution is evaluated", function () {
            before(async function () {
              await loadFixture(priceChangesSetup);
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
    });
  });
};

export { mintTCandTPQueueBehavior };
