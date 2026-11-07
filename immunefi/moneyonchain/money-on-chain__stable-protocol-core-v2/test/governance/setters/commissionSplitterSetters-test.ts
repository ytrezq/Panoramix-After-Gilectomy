import { expect } from "chai";
import { ethers, getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { CommissionSplitterRC20, GovernorMock } from "../../../typechain";
import { ERRORS, deployCommissionSplitter, pEth } from "../../helpers/utils";

describe("Feature: Verify all CommissionSplitter config settings are protected by governance", () => {
  let governorMock: GovernorMock;
  let commissionSplitter: CommissionSplitterRC20;
  let alice: Address, bob: Address, deployer: Address;

  before(async () => {
    ({ alice, bob, deployer } = await getNamedAccounts());

    const governorMockFactory = await ethers.getContractFactory("GovernorMock");
    governorMock = await governorMockFactory.deploy();

    const initParams = {
      acToken: deployer, // Not relevant for this tests
      governorAddress: governorMock.target.toString(),
      feeToken: deployer, // Not relevant for this tests
      acTokenAddressRecipient1: alice,
      acTokenAddressRecipient2: bob,
      acTokenPctToRecipient1: pEth(1) / 10n,
      feeTokenAddressRecipient1: alice,
      feeTokenAddressRecipient2: bob,
      feeTokenPctToRecipient1: pEth(2) / 10n,
    };
    commissionSplitter = (await deployCommissionSplitter(initParams)) as CommissionSplitterRC20;
  });

  describe("GIVEN the Governor has authorized the change", () => {
    before(async () => {
      await governorMock.setIsAuthorized(true);
    });
    describe(`WHEN setAcToken is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await commissionSplitter.setAcToken(alice);
        expect(await commissionSplitter.acToken()).to.be.equal(alice);
      });
    });
    describe(`WHEN setFeeToken is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await commissionSplitter.setFeeToken(bob);
        expect(await commissionSplitter.feeToken()).to.be.equal(bob);
      });
    });
    describe(`WHEN setAcTokenAddressRecipient1 is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await commissionSplitter.setAcTokenAddressRecipient1(deployer);
        expect(await commissionSplitter.acTokenAddressRecipient1()).to.be.equal(deployer);
      });
    });
    describe(`WHEN setAcTokenAddressRecipient2 is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await commissionSplitter.setAcTokenAddressRecipient2(deployer);
        expect(await commissionSplitter.acTokenAddressRecipient2()).to.be.equal(deployer);
      });
    });
    describe(`WHEN setAcTokenPctToRecipient1 is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await commissionSplitter.setAcTokenPctToRecipient1(43);
        expect(await commissionSplitter.acTokenPctToRecipient1()).to.be.equal(43);
      });
    });
    describe(`WHEN setFeeTokenAddressRecipient1 is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await commissionSplitter.setFeeTokenAddressRecipient1(deployer);
        expect(await commissionSplitter.feeTokenAddressRecipient1()).to.be.equal(deployer);
      });
    });
    describe(`WHEN setFeeTokenAddressRecipient2 is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await commissionSplitter.setFeeTokenAddressRecipient2(deployer);
        expect(await commissionSplitter.feeTokenAddressRecipient2()).to.be.equal(deployer);
      });
    });
    describe(`WHEN setFeeTokenPctToRecipient1 is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await commissionSplitter.setFeeTokenPctToRecipient1(42);
        expect(await commissionSplitter.feeTokenPctToRecipient1()).to.be.equal(42);
      });
    });
    describe("GIVEN the Governor has not authorized the change", () => {
      let expectRevertNotAuthorized: (it: any) => any;
      before(async () => {
        await governorMock.setIsAuthorized(false);
        expectRevertNotAuthorized = it =>
          expect(it).to.be.revertedWithCustomError(commissionSplitter, ERRORS.NOT_AUTH_CHANGER);
      });
      describe(`WHEN setAcToken is invoked`, () => {
        it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
          await expectRevertNotAuthorized(commissionSplitter.setAcToken(alice));
        });
      });
      describe(`WHEN setFeeToken is invoked`, () => {
        it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
          await expectRevertNotAuthorized(commissionSplitter.setFeeToken(bob));
        });
      });
      describe(`WHEN setAcTokenAddressRecipient1 is invoked`, () => {
        it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
          await expectRevertNotAuthorized(commissionSplitter.setAcTokenAddressRecipient1(deployer));
        });
      });
      describe(`WHEN setAcTokenAddressRecipient2 is invoked`, () => {
        it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
          await expectRevertNotAuthorized(commissionSplitter.setAcTokenAddressRecipient2(deployer));
        });
      });
      describe(`WHEN setAcTokenPctToRecipient1 is invoked`, () => {
        it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
          await expectRevertNotAuthorized(commissionSplitter.setAcTokenPctToRecipient1(42));
        });
      });
      describe(`WHEN setFeeTokenAddressRecipient1 is invoked`, () => {
        it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
          await expectRevertNotAuthorized(commissionSplitter.setFeeTokenAddressRecipient1(alice));
        });
      });
      describe(`WHEN setFeeTokenAddressRecipient2 is invoked`, () => {
        it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
          await expectRevertNotAuthorized(commissionSplitter.setFeeTokenAddressRecipient2(bob));
        });
      });
      describe(`WHEN setFeeTokenPctToRecipient1 is invoked`, () => {
        it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
          await expectRevertNotAuthorized(commissionSplitter.setFeeTokenPctToRecipient1(42));
        });
      });
    });
  });
});
