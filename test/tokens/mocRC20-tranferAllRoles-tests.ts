import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { ContractRunner } from "ethers";
import { Address } from "hardhat-deploy/types";
import { GovernorMock__factory, MocRC20 } from "../../typechain";
import {
  BURNER_ROLE,
  DEFAULT_ADMIN_ROLE,
  MINTER_ROLE,
  deployAndInitTC,
  ERRORS,
  timedDescribe,
  deployPeggedToken,
} from "../helpers/utils";

timedDescribe("Feature: Moc Tokens roles can be transferred by transferAllRoles", () => {
  let token: MocRC20;
  let deployer: Address, alice: Address, roleAdmin: Address;
  let aliceSigner: ContractRunner;
  describe("GIVEN deployer (admin) account gives Alice other roles roles", () => {
    before(async () => {
      ({ alice, deployer, otherUser: roleAdmin } = await getNamedAccounts());
      const governorMockFactory = await ethers.getContractFactory("GovernorMock");
      const governorMockDeployment = await governorMockFactory.deploy();
      const governorMock = GovernorMock__factory.connect(
        governorMockDeployment.target.toString(),
        await ethers.getSigner(deployer),
      );
      // Makes sure that governance does not interfere
      await governorMock.setIsAuthorized(false);
      token = await deployAndInitTC({ adminAddress: deployer, governorAddress: governorMock.target.toString() });
      await Promise.all([DEFAULT_ADMIN_ROLE, BURNER_ROLE, MINTER_ROLE].map(role => token.grantRole(role, alice)));
      aliceSigner = await ethers.getSigner(alice);
      // verify she can mint/burn
      await token.connect(aliceSigner).mint(alice, 10);
      await token.connect(aliceSigner).burn(alice, 10);
    });
    describe("WHEN he tries to grantsAllRoles to roleAdmin", () => {
      it("THEN it fails as Alice cannot keep her roles", async () => {
        await expect(token.transferAllRoles(roleAdmin)).to.be.revertedWithCustomError(token, ERRORS.NOT_UNIQUE_ROLE);
      });
    });
    describe("WHEN he tries to grantsAllRoles to roleAdmin without revoking Admin role", () => {
      it("THEN it fails as Alice cannot keep her roles", async () => {
        const rolesToRevoke = [BURNER_ROLE, MINTER_ROLE];
        await Promise.all(rolesToRevoke.map(role => token.revokeRole(role, alice)));
        await expect(token.transferAllRoles(roleAdmin)).to.be.revertedWithCustomError(token, ERRORS.NOT_UNIQUE_ROLE);
        // restore roles for the following tests
        await Promise.all(rolesToRevoke.map(role => token.grantRole(role, alice)));
      });
    });
    describe("WHEN he tries to grantsAllRoles to roleAdmin without revoking Burner role", () => {
      it("THEN it fails as Alice cannot keep her roles", async () => {
        const rolesToRevoke = [DEFAULT_ADMIN_ROLE, MINTER_ROLE];
        await Promise.all(rolesToRevoke.map(role => token.revokeRole(role, alice)));
        await expect(token.transferAllRoles(roleAdmin)).to.be.revertedWithCustomError(token, ERRORS.NOT_UNIQUE_ROLE);
        // restore roles for the following tests
        await Promise.all(rolesToRevoke.map(role => token.grantRole(role, alice)));
      });
    });
    describe("WHEN he tries to grantsAllRoles to roleAdmin without revoking Minter role", () => {
      it("THEN it fails as Alice cannot keep her roles", async () => {
        const rolesToRevoke = [DEFAULT_ADMIN_ROLE, BURNER_ROLE];
        await Promise.all(rolesToRevoke.map(role => token.revokeRole(role, alice)));
        await expect(token.transferAllRoles(roleAdmin)).to.be.revertedWithCustomError(token, ERRORS.NOT_UNIQUE_ROLE);
        // restore roles for the following tests
        await Promise.all(rolesToRevoke.map(role => token.grantRole(role, alice)));
      });
    });
    describe("WHEN he grantsAllRoles to roleAdmin account, after revoking every Alice's Roles", () => {
      before(async () => {
        await Promise.all([DEFAULT_ADMIN_ROLE, BURNER_ROLE, MINTER_ROLE].map(role => token.revokeRole(role, alice)));
        await token.transferAllRoles(roleAdmin);
      });
      it("THEN she cannot mint any more", async () => {
        await expect(token.connect(aliceSigner).mint(alice, 10)).to.be.revertedWith(
          `AccessControl: account ${alice.toLowerCase()} is missing role ${MINTER_ROLE}`,
        );
      });
      it("THEN she cannot burn any more", async () => {
        await expect(token.connect(aliceSigner).burn(alice, 10)).to.be.revertedWith(
          `AccessControl: account ${alice.toLowerCase()} is missing role ${BURNER_ROLE}`,
        );
      });
      it("THEN he no longer has Admin role", async () => {
        await expect(token.grantRole(MINTER_ROLE, alice)).to.be.revertedWithCustomError(token, ERRORS.NOT_AUTH_CHANGER);
      });
      it("THEN roleAdmin account has all roles", async () => {
        expect(
          await Promise.all(
            [DEFAULT_ADMIN_ROLE, BURNER_ROLE, MINTER_ROLE].map(role => token.hasRole(role, roleAdmin)),
          ).then(allHasRole => allHasRole.reduce((accum, hasRole) => accum && hasRole, true)),
        ).to.be.true;
      });
      describe("WHEN roleAdmin tries to grantsAllRoles to itself again", () => {
        it("THEN it fails as roles are not transferred", async () => {
          const roleAdminSigner = await ethers.getSigner(roleAdmin);
          await expect(token.connect(roleAdminSigner).transferAllRoles(roleAdmin)).to.be.revertedWithCustomError(
            token,
            "NotYourself",
          );
        });
      });
    });
    describe("WHEN a not admin tries to grantsAllRoles to roleAdmin", () => {
      it("THEN it fails Alice is not the admin", async () => {
        await expect(token.connect(aliceSigner).transferAllRoles(roleAdmin)).to.be.revertedWith(
          `AccessControl: account ${alice.toLowerCase()} is missing role ${DEFAULT_ADMIN_ROLE}`,
        );
      });
      it("THEN it fails Alice is not the admin", async () => {
        const tpToken = await deployPeggedToken({ adminAddress: deployer, governorAddress: deployer });
        await expect(tpToken.connect(aliceSigner).transferAllRoles(roleAdmin)).to.be.revertedWith(
          `AccessControl: account ${alice.toLowerCase()} is missing role ${DEFAULT_ADMIN_ROLE}`,
        );
      });
    });
  });
});
