import { expect } from "chai";
import { getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { fluxCapacitorBehavior } from "../behaviors/fluxCapacitor.behavior";
import { Balance, ERROR_SELECTOR, pEth, timedDescribe, tpParams } from "../helpers/utils";
import { MocCARC20, MocQueue } from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 Flux capacitor", function () {
  describe("GIVEN a MocCARC20 implementation deployed with mocQueueMock", function () {
    let mocQueue: MocQueue;
    const setup = async () => {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      ({ mocQueue } = mocContracts);
      // on flux capacitor tests all the operations happens in the same block, we need waiting blocks on 0
      await mocQueue.setMinOperWaitingBlk(0);
      return { mocFunctions, mocContracts };
    };
    fluxCapacitorBehavior(setup);
  });

  describe("GIVEN a MocCARC20 implementation deployed behind MocQueue", function () {
    let mocImpl: MocCARC20;
    let mocFunctions: any;
    let mocQueue: MocQueue;
    let operId: bigint;
    let alice: Address;
    let execTx: ContractTransactionResponse;
    let prevACBalance: Balance;
    let prevTPBalance: Balance;
    let prevTCBalance: Balance;
    const TP_0 = 0;
    async function setup() {
      ({ alice } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();
      mocFunctions = await mocFunctionsRC20(mocContracts);
      ({ mocImpl, mocQueue } = mocContracts);
      // add collateral
      await mocFunctions.mintTC({ from: alice, qTC: 100000000 });
      // initialize alice with some TP0
      await mocFunctions.mintTP({ from: alice, qTP: 23500000 });

      await mocContracts.maxAbsoluteOpProvider.poke(pEth(10000));
      await mocContracts.maxOpDiffProvider.poke(pEth(5000));
    }
    describe("WHEN an user registers a mint TP operation, exceeding the max flux capacitor parameter", function () {
      async function mintTPSetup() {
        await loadFixture(setup);
        operId = await mocQueue.operIdCount();
        await mocFunctions.mintTP({ from: alice, qTP: 2350235, qACmax: 100000, execute: false });
      }
      describe("AND execution is evaluated", function () {
        before(async function () {
          await loadFixture(mintTPSetup);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          execTx = await mocFunctions.executeQueue();
        });
        it("THEN Operations fails with Unhandled Error", async function () {
          await expect(execTx)
            .to.emit(mocQueue, "UnhandledError")
            .withArgs(operId, ERROR_SELECTOR.INVALID_FLUX_CAPACITOR_OPERATION);
        });
        it("THEN AC is returned", async function () {
          assertPrec(await mocImpl.qACLockedInPending(), 0);
          assertPrec(prevACBalance + pEth(100000), await mocFunctions.acBalanceOf(alice));
        });
      });
    });
    describe("WHEN an user registers a redeem TP operation, exceeding the max flux capacitor parameter", function () {
      async function redeemTPSetup() {
        await loadFixture(setup);
        operId = await mocQueue.operIdCount();
        await mocFunctions.redeemTP({ from: alice, qTP: 2473931, execute: false });
      }
      describe("AND execution is evaluated", function () {
        before(async function () {
          await loadFixture(redeemTPSetup);
          prevTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
          execTx = await mocFunctions.executeQueue();
        });
        it("THEN Operations fails with Unhandled Error", async function () {
          await expect(execTx)
            .to.emit(mocQueue, "UnhandledError")
            .withArgs(operId, ERROR_SELECTOR.INVALID_FLUX_CAPACITOR_OPERATION);
        });
        it("THEN TP is returned", async function () {
          assertPrec(prevTPBalance + pEth(2473931), await mocFunctions.tpBalanceOf(TP_0, alice));
        });
      });
    });
    describe("WHEN an user registers a swap TC for TP operation, exceeding the max flux capacitor parameter", function () {
      async function registerSwapTCToTPSetup() {
        await loadFixture(setup);
        operId = await mocQueue.operIdCount();
        await mocFunctions.swapTCforTP({ from: alice, qTC: 10001, qACmax: 100000, execute: false });
      }
      describe("AND execution is evaluated", function () {
        before(async function () {
          await loadFixture(registerSwapTCToTPSetup);
          prevTCBalance = await mocFunctions.tcBalanceOf(alice);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          execTx = await mocFunctions.executeQueue();
        });
        it("THEN Operations fails with Unhandled Error", async function () {
          await expect(execTx)
            .to.emit(mocQueue, "UnhandledError")
            .withArgs(operId, ERROR_SELECTOR.INVALID_FLUX_CAPACITOR_OPERATION);
        });
        it("THEN TC and AC are returned", async function () {
          assertPrec(prevTCBalance + pEth(10001), await mocFunctions.tcBalanceOf(alice));
          assertPrec(prevACBalance + pEth(100000), await mocFunctions.acBalanceOf(alice));
        });
      });
    });
    describe("WHEN an user registers a swap TP for TC operation, exceeding the max flux capacitor parameter", function () {
      async function registerSwapTPForTCSetup() {
        await loadFixture(setup);
        operId = await mocQueue.operIdCount();
        await mocFunctions.swapTPforTC({ from: alice, qTP: 2350235, qACmax: 100000, execute: false });
      }
      describe("AND execution is evaluated", function () {
        before(async function () {
          await loadFixture(registerSwapTPForTCSetup);

          prevTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          execTx = await mocFunctions.executeQueue();
        });
        it("THEN Operations fails with Unhandled Error", async function () {
          await expect(execTx)
            .to.emit(mocQueue, "UnhandledError")
            .withArgs(operId, ERROR_SELECTOR.INVALID_FLUX_CAPACITOR_OPERATION);
        });
        it("THEN TP and AC are returned", async function () {
          assertPrec(prevTPBalance + pEth(2350235), await mocFunctions.tpBalanceOf(TP_0, alice));
          assertPrec(prevACBalance + pEth(100000), await mocFunctions.acBalanceOf(alice));
        });
      });
    });
    describe("WHEN an user registers a redeem TC and TP operation, exceeding the max flux capacitor parameter", function () {
      async function registerRedeemTCAndTPSetup() {
        await loadFixture(setup);
        operId = await mocQueue.operIdCount();
        await mocFunctions.redeemTCandTP({ from: alice, qTC: 10000001, qTP: 2350235, execute: false });
      }
      describe("AND execution is evaluated", function () {
        before(async function () {
          await loadFixture(registerRedeemTCAndTPSetup);
          prevTCBalance = await mocFunctions.tcBalanceOf(alice);
          prevTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
          execTx = await mocFunctions.executeQueue();
        });
        it("THEN Operations fails with Unhandled Error", async function () {
          await expect(execTx)
            .to.emit(mocQueue, "UnhandledError")
            .withArgs(operId, ERROR_SELECTOR.INVALID_FLUX_CAPACITOR_OPERATION);
        });
        it("THEN TC and Tps are returned", async function () {
          assertPrec(prevTCBalance + pEth(10000001), await mocFunctions.tcBalanceOf(alice));
          assertPrec(prevTPBalance + pEth(2350235), await mocFunctions.tpBalanceOf(TP_0, alice));
        });
      });
    });
    describe("WHEN an user registers a mint TC and TP operation, exceeding the max flux capacitor parameter", function () {
      async function registerMintTCAndTPSetup() {
        await loadFixture(setup);
        operId = await mocQueue.operIdCount();
        await mocFunctions.mintTCandTP({ from: alice, qTP: 2350235, qACmax: 100000, execute: false });
      }
      describe("AND execution is evaluated", function () {
        before(async function () {
          await loadFixture(registerMintTCAndTPSetup);
          prevACBalance = await mocFunctions.acBalanceOf(alice);
          execTx = await mocFunctions.executeQueue();
        });
        it("THEN Operations fails with Unhandled Error", async function () {
          await expect(execTx)
            .to.emit(mocQueue, "UnhandledError")
            .withArgs(operId, ERROR_SELECTOR.INVALID_FLUX_CAPACITOR_OPERATION);
        });
        it("THEN AC is returned", async function () {
          assertPrec(await mocImpl.qACLockedInPending(), 0);
          assertPrec(prevACBalance + pEth(100000), await mocFunctions.acBalanceOf(alice));
        });
      });
    });
  });
});
