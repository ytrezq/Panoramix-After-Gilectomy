import { expect } from "chai";
import { ethers, network, getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { fixtureDeployedMocRC20 } from "../../rc20/fixture";
import { MocCACoinbase } from "../../../typechain";
import { ERRORS } from "../../helpers/utils";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";

const fixtureDeploy = fixtureDeployedMocRC20(2);

describe("Feature: Allow Different Recipient", () => {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCACoinbase;
  let common: { from: Address; to: Address; execute: boolean };

  const expectRecipientRevert = async (result: any) =>
    expect(result).to.be.revertedWithCustomError(mocImpl, ERRORS.RECIPIENT_MUST_BE_SENDER);

  before(async () => {
    mocContracts = await fixtureDeploy();
    ({ mocImpl } = mocContracts);
    mocFunctions = await mocFunctionsRC20(mocContracts);
    const { alice, bob } = await getNamedAccounts();
    await mocFunctions.mintTC({ from: alice, qTC: 10 });
    await mocFunctions.mintTP({ from: alice, qTP: 3 });

    // disable flexible recipient for these tests
    await network.provider.send("hardhat_setStorageAt", [
      mocImpl.target.toString(),
      ethers.toQuantity(331), // Slot allowDifferentRecipient
      ethers.ZeroHash, // false
    ]);

    common = { from: alice, to: bob, execute: false };
  });

  describe("GIVEN the system does not allow different recipient", () => {
    describe(`WHEN someone tries to mintTC using recipient`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectRecipientRevert(mocFunctions.mintTC({ ...common, qTC: 10 }));
      });
    });
    describe(`WHEN someone tries to liquidate his TP using recipient`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectRecipientRevert(mocFunctions.liqRedeemTP({ ...common }));
      });
    });
    describe(`WHEN someone tries to mintTP using recipient`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectRecipientRevert(mocFunctions.mintTP({ ...common, qTP: 3 }));
      });
    });
    describe(`WHEN someone tries to redeemTC using recipient`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectRecipientRevert(mocFunctions.redeemTC({ ...common, qTC: 10 }));
      });
    });
    describe(`WHEN someone tries to redeemTP using recipient`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectRecipientRevert(mocFunctions.redeemTP({ ...common, qTP: 3 }));
      });
    });
    describe(`WHEN someone tries to swapTPforTP using recipient`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectRecipientRevert(mocFunctions.swapTPforTP({ iFrom: 0, iTo: 1, ...common, qTP: 3 }));
      });
    });
    describe(`WHEN someone tries to swapTPforTC using recipient`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectRecipientRevert(mocFunctions.swapTPforTC({ ...common, qTP: 3 }));
      });
    });
    describe(`WHEN someone tries to swapTCforTP using recipient`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectRecipientRevert(mocFunctions.swapTCforTP({ ...common, qTC: 3 }));
      });
    });
    describe(`WHEN someone tries to redeemTCandTP using recipient`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectRecipientRevert(mocFunctions.redeemTCandTP({ ...common, qTC: 10, qTP: 3 }));
      });
    });
    describe(`WHEN someone tries to mintTCandTP using recipient`, () => {
      it("THEN it fails, as the system is paused", async function () {
        await expectRecipientRevert(mocFunctions.mintTCandTP({ ...common, qTP: 3 }));
      });
    });
  });
});
