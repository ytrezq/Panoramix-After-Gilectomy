import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { GovernorMock, GovernorMock__factory, MocVendors, MocVendors__factory } from "../../../typechain";
import { ERRORS, timedDescribe } from "../../helpers/utils";

const fixtureDeploy = async (): Promise<{
  mocVendors: MocVendors;
}> => {
  await deployments.fixture();
  const [signer] = await ethers.getSigners();

  const deployedMocVendors = await deployments.getOrNull("MocVendorsCARC20Proxy");
  if (!deployedMocVendors) throw new Error("No MocVendors deployed.");
  const mocVendors: MocVendors = MocVendors__factory.connect(deployedMocVendors.address, signer);

  return {
    mocVendors,
  };
};

timedDescribe("Feature: Verify all MocVendors config settings are protected by governance", () => {
  let governorMock: GovernorMock;
  let mocVendors: MocVendors;
  let mockAddress: Address;

  before(async () => {
    ({ mocVendors } = await fixtureDeploy());
    const governorAddress = await mocVendors.governor();
    const [signer] = await ethers.getSigners();
    governorMock = GovernorMock__factory.connect(governorAddress, signer);
    mockAddress = governorAddress;
  });

  describe("GIVEN the Governor has authorized the change", () => {
    before(async () => {
      await governorMock.setIsAuthorized(true);
    });
    describe(`WHEN setVendorsGuardianAddress is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocVendors.setVendorsGuardianAddress(mockAddress);
        expect(await mocVendors.vendorsGuardianAddress()).to.be.equal(mockAddress);
      });
    });
    describe("WHEN setMaxMarkup is invoked", () => {
      it("THEN the new value is assigned", async function () {
        const newMaxMarkup = 123;
        await mocVendors.setMaxMarkup(newMaxMarkup);
        expect(await mocVendors.maxMarkup()).to.be.equal(newMaxMarkup);
      });
    });
  });
  describe("GIVEN the Governor has not authorized the change", () => {
    let expectRevertNotAuthorized: (it: any) => any;
    before(async () => {
      await governorMock.setIsAuthorized(false);

      expectRevertNotAuthorized = it => expect(it).to.be.revertedWithCustomError(mocVendors, ERRORS.NOT_AUTH_CHANGER);
    });
    describe("WHEN setVendorsGuardianAddress is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocVendors.setVendorsGuardianAddress(mockAddress));
      });
    });
    describe("WHEN setMaxMarkup is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocVendors.setMaxMarkup(123));
      });
    });
  });
});
