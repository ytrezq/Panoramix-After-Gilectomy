import { getNamedAccounts, ethers } from "hardhat";
import { ContractRunner, ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { expect } from "chai";
import { pEth, time, timedDescribe, tpParams } from "../helpers/utils";
import { GovernorMock, GovernorMock__factory, MocVendors } from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";
import { fixtureDeployedMocRC20 } from "../rc20/fixture";

let mocVendors: MocVendors;
let vendor: Address;
let vendorsGuardian: Address;
let vendorsGuardianSigner: ContractRunner;
let governorMock: GovernorMock;
let tx: ContractTransactionResponse;

timedDescribe("Feature: MocCARC20 vendors", function () {
  describe("GIVEN a MocCARC20 implementation deployed", function () {
    before(async function () {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams);
      ({ mocVendors } = await fixtureDeploy());
      ({ otherUser: vendorsGuardian, vendor } = await getNamedAccounts());
      vendorsGuardianSigner = await ethers.getSigner(vendorsGuardian);

      await mocVendors.setVendorsGuardianAddress(vendorsGuardian);
      const governorAddress = await mocVendors.governor();
      governorMock = GovernorMock__factory.connect(governorAddress, await ethers.getSigner(vendor));
      await governorMock.setIsAuthorized(false);
    });
    describe("WHEN not vendor guardian tries to set a vendor markup", function () {
      it("THEN tx fails because only vendors guardian or vendor itself can", async function () {
        await expect(mocVendors.setVendorMarkup(vendor, pEth(0.05))).to.be.revertedWithCustomError(
          mocVendors,
          "NotVendorsGuardian",
        );
      });
    });
    describe("WHEN vendors guardian sets a vendor markup", function () {
      before(async function () {
        tx = await mocVendors.connect(vendorsGuardianSigner).setVendorMarkup(vendor, pEth(0.05));
      });
      it("THEN VendorMarkupChanged event is emitted", async function () {
        await expect(tx).to.emit(mocVendors, "VendorMarkupChanged").withArgs(vendor, pEth(0.05));
      });
      it("THEN markup is not set immediately", async function () {
        assertPrec(await mocVendors.vendorMarkup(vendor), pEth(0.1));
      });
      it("THEN markup is set after the cooldown has elapsed", async function () {
        await time.increase(await mocVendors.COOLDOWN());
        assertPrec(await mocVendors.vendorMarkup(vendor), pEth(0.05));
      });
    });
    describe("WHEN vendor sets itself a 4% markup", function () {
      before(async function () {
        tx = await mocVendors.connect(await ethers.getSigner(vendor)).setMarkup(pEth(0.04));
      });
      it("THEN VendorMarkupChanged event is emitted", async function () {
        await expect(tx).to.emit(mocVendors, "VendorMarkupChanged").withArgs(vendor, pEth(0.04));
      });
      it("THEN vendors guardian is not authorized anymore", async function () {
        expect(await mocVendors.delegateRevoked(vendor)).to.be.true;
        await expect(
          mocVendors.connect(vendorsGuardianSigner).setVendorMarkup(vendor, pEth(0.04)),
        ).to.be.revertedWithCustomError(mocVendors, "DelegateRevoked");
      });
      it("THEN markup is not set immediately", async function () {
        assertPrec(await mocVendors.vendorMarkup(vendor), pEth(0.05));
      });
      it("THEN markup is set after the cooldown has elapsed", async function () {
        await time.increase(await mocVendors.COOLDOWN());
        assertPrec(await mocVendors.vendorMarkup(vendor), pEth(0.04));
      });
    });
    describe("WHEN vendor tries to set a markup above maxMarkup", function () {
      it("THEN tx fails because markup is too high", async function () {
        const maxMarkup = await mocVendors.maxMarkup();
        await expect(
          mocVendors.connect(await ethers.getSigner(vendor)).setMarkup(maxMarkup + 1n),
        ).to.be.revertedWithCustomError(mocVendors, "MarkupTooHigh");
      });
    });
    describe("WHEN governor sets a vendor markup", function () {
      before(async function () {
        await governorMock.setIsAuthorized(true);
        tx = await mocVendors.setVendorMarkup(vendor, pEth(0.03));
      });
      it("THEN VendorMarkupChanged event is emitted", async function () {
        await expect(tx).to.emit(mocVendors, "VendorMarkupChanged").withArgs(vendor, pEth(0.03));
      });
      it("THEN markup is set immediately", async function () {
        assertPrec(await mocVendors.vendorMarkup(vendor), pEth(0.03));
      });
    });
  });
});
