import { expect } from "chai";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { ethers, getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { ContractTransactionResponse } from "ethers";
import { fixtureDeployedMocCoinbase } from "../../coinbase/fixture";
import { GovernorMock, MocCACoinbase, GovernorMock__factory, MocQueue } from "../../../typechain";
import { ERRORS, ERROR_SELECTOR, pEth, timedDescribe } from "../../helpers/utils";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { assertPrec } from "../../helpers/assertHelper";

const fixtureDeploy = fixtureDeployedMocCoinbase(2);

timedDescribe("Feature: Verify pausing mechanism and restrictions", () => {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCACoinbase;
  let mocQueue: MocQueue;
  let governorMock: GovernorMock;
  let pauser: Address;
  let alice: Address;

  const expectPauseRevert = async (result: any) =>
    expect(result).to.be.revertedWithCustomError(mocImpl, ERRORS.NOT_WHEN_PAUSED);
  const expectPauseEvent = async (result: any) =>
    expect(result).to.emit(mocQueue, "UnhandledError").withArgs(anyValue, ERROR_SELECTOR.PAUSED); // operID is not relevant here

  before(async () => {
    mocContracts = await fixtureDeploy();
    ({ mocImpl, mocQueue } = mocContracts);
    mocFunctions = await mocFunctionsCoinbase(mocContracts);

    ({ deployer: pauser, alice } = await getNamedAccounts());
    const governorAddress = await mocImpl.governor();
    governorMock = GovernorMock__factory.connect(governorAddress, await ethers.getSigner(pauser));
    await governorMock.setIsAuthorized(true);
    await mocImpl.setPauser(pauser);
    await mocImpl.makeStoppable();
    await governorMock.setIsAuthorized(false);
    await mocFunctions.mintTC({ from: alice, qTC: 10 });
    await mocFunctions.mintTP({ from: alice, qTP: 3 });
  });

  describe("GIVEN the system is stoppable", () => {
    let pauseTx: ContractTransactionResponse, unPauseTx: ContractTransactionResponse;
    describe(`WHEN the pauser pauses it`, () => {
      before(async () => {
        pauseTx = await mocImpl.pause();
      });
      it("THEN it is paused", async function () {
        expect(await mocImpl.paused()).to.be.true;
      });
      it("THEN a pause event is emitted", async function () {
        await expect(pauseTx).to.emit(mocImpl, "Paused").withArgs(pauser);
      });
      describe(`WHEN the pauser tries to pause it again`, () => {
        it("THEN it fails as is already paused", async function () {
          await expect(mocImpl.pause()).to.be.revertedWithCustomError(mocImpl, ERRORS.NOT_WHEN_PAUSED);
        });
      });
      describe(`WHEN someone else tries to unpause`, () => {
        it("THEN it fails as only pauser can", async function () {
          await expect(mocImpl.connect(await ethers.getSigner(alice)).unpause()).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.ONLY_PAUSER,
          );
        });
      });
      describe(`WHEN a governor authorized user unpaused it`, () => {
        it("THEN it gets unpaused", async function () {
          await governorMock.setIsAuthorized(true);
          unPauseTx = await mocImpl.connect(await ethers.getSigner(alice)).unpause();
          // Pause it again for following tests
          await mocImpl.pause();
          await governorMock.setIsAuthorized(false);
          await expect(unPauseTx).to.emit(mocImpl, "Unpaused").withArgs(alice);
        });
      });
      describe(`WHEN the pauser unpause it`, () => {
        before(async () => {
          unPauseTx = await mocImpl.unpause();
        });
        it("THEN a unpause event is emitted", async function () {
          await expect(unPauseTx).to.emit(mocImpl, "Unpaused").withArgs(pauser);
        });
        describe(`WHEN the pauser tries to unpause it again`, () => {
          it("THEN it fails at is already unpaused", async function () {
            await expect(mocImpl.unpause()).to.be.revertedWithCustomError(mocImpl, ERRORS.ONLY_WHILE_PAUSED);
          });
        });
      });
    });
    describe(`WHEN someone rather than the pauser tries to pause it`, () => {
      it("THEN it fails, as only the pauser can", async function () {
        await expect(mocImpl.connect(await ethers.getSigner(alice)).pause()).to.be.revertedWithCustomError(
          mocImpl,
          ERRORS.ONLY_PAUSER,
        );
      });
    });
  });
  describe("GIVEN the system is unstoppable", () => {
    before(async () => {
      await governorMock.setIsAuthorized(true);
      await mocImpl.makeUnstoppable();
    });
    after(async () => {
      await mocImpl.makeStoppable();
      await governorMock.setIsAuthorized(false);
    });
    describe(`WHEN the Pauser tries to pause`, () => {
      it("THEN it fails, as while unstoppable, even the pauser can't", async function () {
        await expect(mocImpl.pause()).to.be.revertedWithCustomError(mocImpl, ERRORS.UNSTOPPABLE);
      });
    });
  });
  describe("GIVEN the Pauser, pauses the system", () => {
    before(async () => {
      await mocImpl.pause();
    });
    after(async () => {
      await mocImpl.unpause();
    });
    describe("AND the system is unstoppable", () => {
      before(async () => {
        await governorMock.setIsAuthorized(true);
        await mocImpl.makeUnstoppable();
      });
      after(async () => {
        await mocImpl.makeStoppable();
        await governorMock.setIsAuthorized(false);
      });
      describe(`WHEN the Pauser tries to unpause`, () => {
        it("THEN it fails, as while unstoppable, even the pauser can't", async function () {
          await expect(mocImpl.unpause()).to.be.revertedWithCustomError(mocImpl, ERRORS.UNSTOPPABLE);
        });
      });
    });
    describe(`AND liquidation conditions are met`, () => {
      before(async () => {
        await governorMock.setIsAuthorized(true);
        await mocImpl.setLiqEnabled(true);
        await mocContracts.priceProviders[0].poke(pEth(0.1));
      });
      after(async () => {
        await mocContracts.priceProviders[0].poke(pEth(1));
      });
      describe(`WHEN someone tries to liquidate()`, () => {
        it("THEN it fails, as the system is paused", async function () {
          await expectPauseRevert(mocImpl.liquidate());
        });
      });
    });
    describe(`WHEN someone tries to mintTC`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocFunctions.mintTC({ from: alice, qTC: 10 }));
      });
      describe(`AND the system gets unpaused`, () => {
        it("THEN he can mintTC again", async function () {
          await mocImpl.unpause();
          await mocFunctions.mintTC({ from: alice, qTC: 10 });
          await mocImpl.pause();
        });
      });
    });
    describe(`WHEN someone tries to liquidate his TP`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocFunctions.liqRedeemTP({ from: alice }));
      });
    });
    describe(`WHEN someone tries to mintTP`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocFunctions.mintTP({ from: alice, qTP: 3 }));
      });
    });
    describe(`WHEN someone tries to redeemTC`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocFunctions.redeemTC({ from: alice, qTC: 10 }));
      });
    });
    describe(`WHEN someone tries to redeemTP`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocFunctions.redeemTP({ from: alice, qTP: 3 }));
      });
    });
    describe(`WHEN someone tries to swapTPforTP`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocFunctions.swapTPforTP({ iFrom: 0, iTo: 1, from: alice, qTP: 3 }));
      });
    });
    describe(`WHEN someone tries to swapTPforTC`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocFunctions.swapTPforTC({ from: alice, qTP: 3 }));
      });
    });
    describe(`WHEN someone tries to swapTCforTP`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocFunctions.swapTCforTP({ from: alice, qTC: 3 }));
      });
    });
    describe(`WHEN someone tries to redeemTCandTP`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocFunctions.redeemTCandTP({ from: alice, qTC: 10, qTP: 3 }));
      });
    });
    describe(`WHEN someone tries to mintTCandTP`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocFunctions.mintTCandTP({ from: alice, qTP: 3 }));
      });
    });
    describe(`WHEN someone tries to execute settlement`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocImpl.execSettlement());
      });
    });
    describe(`WHEN someone tries to execute tcHoldersInterestPayment`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectPauseRevert(mocImpl.tcHoldersInterestPayment());
      });
    });
  });
  describe("WHEN alice enqueue a mintTC operation", function () {
    before(async function () {
      await mocFunctions.mintTC({ from: alice, qTC: 1, execute: false });
    });
    describe("AND protocol is paused", function () {
      before(async function () {
        await mocImpl.pause();
      });
      after(async function () {
        await mocImpl.unpause();
      });
      describe("WHEN queue is executed", function () {
        it("THEN Operations fails with Unhandled Error", async function () {
          await expectPauseEvent(mocFunctions.executeQueue());
          // tokens are returned
          assertPrec(await mocImpl.qACLockedInPending(), 0);
        });
      });
    });
  });
  describe("WHEN alice enqueue a redeemTC operation", function () {
    before(async function () {
      await mocFunctions.redeemTC({ from: alice, qTC: 10, execute: false });
    });
    describe("AND protocol is paused", function () {
      before(async function () {
        await mocImpl.pause();
      });
      after(async function () {
        await mocImpl.unpause();
      });
      describe("WHEN queue is executed", function () {
        it("THEN Operations fails with Unhandled Error", async function () {
          await expectPauseEvent(mocFunctions.executeQueue());
          // tokens are returned
          assertPrec(await mocFunctions.tcBalanceOf(mocImpl.target.toString()), 0);
        });
      });
    });
  });
  describe("WHEN alice enqueue a mintTP operation", function () {
    before(async function () {
      await mocFunctions.mintTP({ from: alice, qTP: 1, execute: false });
    });
    describe("AND protocol is paused", function () {
      before(async function () {
        await mocImpl.pause();
      });
      after(async function () {
        await mocImpl.unpause();
      });
      describe("WHEN queue is executed", function () {
        it("THEN Operations fails with Unhandled Error", async function () {
          await expectPauseEvent(mocFunctions.executeQueue());
          // tokens are returned
          assertPrec(await mocImpl.qACLockedInPending(), 0);
        });
      });
    });
  });
  describe("WHEN alice enqueue a redeemTP operation", function () {
    before(async function () {
      await mocFunctions.redeemTP({ from: alice, qTP: 3, execute: false });
    });
    describe("AND protocol is paused", function () {
      before(async function () {
        await mocImpl.pause();
      });
      after(async function () {
        await mocImpl.unpause();
      });
      describe("WHEN queue is executed", function () {
        it("THEN Operations fails with Unhandled Error", async function () {
          await expectPauseEvent(mocFunctions.executeQueue());
          // tokens are returned
          assertPrec(await mocFunctions.tpBalanceOf(0, mocImpl.target.toString()), 0);
        });
      });
    });
  });
  describe("WHEN alice enqueue a swapTPforTP operation", function () {
    before(async function () {
      await mocFunctions.swapTPforTP({ iFrom: 0, iTo: 1, from: alice, qTP: 3, execute: false });
    });
    describe("AND protocol is paused", function () {
      before(async function () {
        await mocImpl.pause();
      });
      after(async function () {
        await mocImpl.unpause();
      });
      describe("WHEN queue is executed", function () {
        it("THEN Operations fails with Unhandled Error", async function () {
          await expectPauseEvent(mocFunctions.executeQueue());
          // tokens are returned
          assertPrec(await mocFunctions.tpBalanceOf(0, mocImpl.target.toString()), 0);
        });
      });
    });
  });
  describe("WHEN alice enqueue a swapTPforTC operation", function () {
    before(async function () {
      await mocFunctions.swapTPforTC({ from: alice, qTP: 3, execute: false });
    });
    describe("AND protocol is paused", function () {
      before(async function () {
        await mocImpl.pause();
      });
      after(async function () {
        await mocImpl.unpause();
      });
      describe("WHEN queue is executed", function () {
        it("THEN Operations fails with Unhandled Error", async function () {
          await expectPauseEvent(mocFunctions.executeQueue());
          // tokens are returned
          assertPrec(await mocFunctions.tpBalanceOf(0, mocImpl.target.toString()), 0);
        });
      });
    });
  });
  describe("WHEN alice enqueue a swapTCforTP operation", function () {
    before(async function () {
      await mocFunctions.swapTCforTP({ from: alice, qTC: 10, execute: false });
    });
    describe("AND protocol is paused", function () {
      before(async function () {
        await mocImpl.pause();
      });
      after(async function () {
        await mocImpl.unpause();
      });
      describe("WHEN queue is executed", function () {
        it("THEN Operations fails with Unhandled Error", async function () {
          await expectPauseEvent(mocFunctions.executeQueue());
          // tokens are returned
          assertPrec(await mocFunctions.tcBalanceOf(mocImpl.target.toString()), 0);
        });
      });
    });
  });
  describe("WHEN alice enqueue a redeemTCandTP operation", function () {
    before(async function () {
      await mocFunctions.redeemTCandTP({ from: alice, qTC: 10, qTP: 1, execute: false });
    });
    describe("AND protocol is paused", function () {
      before(async function () {
        await mocImpl.pause();
      });
      after(async function () {
        await mocImpl.unpause();
      });
      describe("WHEN queue is executed", function () {
        it("THEN Operations fails with Unhandled Error", async function () {
          await expectPauseEvent(mocFunctions.executeQueue());
          // tokens are returned
          assertPrec(await mocFunctions.tcBalanceOf(mocImpl.target.toString()), 0);
          assertPrec(await mocFunctions.tpBalanceOf(0, mocImpl.target.toString()), 0);
        });
      });
    });
  });
  describe("WHEN alice enqueue a mintTCandTP operation", function () {
    before(async function () {
      await mocFunctions.mintTCandTP({ from: alice, qTP: 3, execute: false });
    });
    describe("AND protocol is paused", function () {
      before(async function () {
        await mocImpl.pause();
      });
      after(async function () {
        await mocImpl.unpause();
      });
      describe("WHEN queue is executed", function () {
        it("THEN Operations fails with Unhandled Error", async function () {
          await expectPauseEvent(mocFunctions.executeQueue());
          // tokens are returned
          assertPrec(await mocImpl.qACLockedInPending(), 0);
        });
      });
    });
  });
});
