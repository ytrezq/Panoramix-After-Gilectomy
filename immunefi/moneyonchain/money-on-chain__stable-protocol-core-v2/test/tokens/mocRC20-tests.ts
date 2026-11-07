import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { ContractRunner } from "ethers";
import { Address } from "hardhat-deploy/types";
import {
  GovernorMock,
  GovernorMock__factory,
  MocRC20,
  MocRC20Decimals,
  MocRC20Decimals__factory,
} from "../../typechain";
import { BURNER_ROLE, ERRORS, MINTER_ROLE, deployAndInitTC, timedDescribe } from "../helpers/utils";

timedDescribe("Feature: Moc Tokens Role Access restrictions", () => {
  let token: MocRC20;
  let deployer: Address, alice: Address, roleAdmin: Address;
  let aliceSigner: ContractRunner;
  let governorMock: GovernorMock;
  describe("GIVEN there is a MocRC20", () => {
    before(async () => {
      ({ alice, deployer, otherUser: roleAdmin } = await getNamedAccounts());
      const governorMockFactory = await ethers.getContractFactory("GovernorMock");
      const governorMockDeployment = await governorMockFactory.deploy();
      governorMock = GovernorMock__factory.connect(
        governorMockDeployment.target.toString(),
        await ethers.getSigner(deployer),
      );
      // Makes sure that governance does not interfere
      await governorMock.setIsAuthorized(false);
      token = (
        await deployAndInitTC({ adminAddress: roleAdmin, governorAddress: governorMock.target.toString() })
      ).connect(await ethers.getSigner(roleAdmin));
      aliceSigner = await ethers.getSigner(alice);
    });
    describe("WHEN a BURNER Role address invokes mint", () => {
      it("THEN it fails with the corresponding error", async () => {
        await token.revokeRole(MINTER_ROLE, alice);
        await token.grantRole(BURNER_ROLE, alice);
        await expect(token.connect(aliceSigner).mint(alice, 10)).to.be.revertedWith(
          `AccessControl: account ${alice.toLowerCase()} is missing role ${MINTER_ROLE}`,
        );
      });
    });
    describe("WHEN a MINTER Role address invokes burn", () => {
      it("THEN it fails with the corresponding error", async () => {
        await token.revokeRole(BURNER_ROLE, alice);
        await token.grantRole(MINTER_ROLE, alice);
        await expect(token.connect(aliceSigner).burn(alice, 10)).to.be.revertedWith(
          `AccessControl: account ${alice.toLowerCase()} is missing role ${BURNER_ROLE}`,
        );
      });
    });
    describe("WHEN deployer address invokes grantRole", () => {
      it("THEN it fails as it is not the roleAdmin", async () => {
        const deployerSigner = await ethers.getSigner(deployer);
        await expect(token.connect(deployerSigner).grantRole(MINTER_ROLE, deployer)).to.be.revertedWithCustomError(
          token,
          ERRORS.NOT_AUTH_CHANGER,
        );
      });
    });
    it("THEN it has 18 decimals", async () => {
      expect(await token.decimals()).to.be.eq(18);
    });
    describe("WHEN a MocRC20 is deployed with 8 decimals", () => {
      let mocRC20Decimals: MocRC20Decimals;
      before(async () => {
        const mocRC20address = (
          await deployAndInitTC({
            adminAddress: roleAdmin,
            governorAddress: governorMock.target.toString(),
            decimals: 8n,
          })
        ).target.toString();
        mocRC20Decimals = MocRC20Decimals__factory.connect(mocRC20address, await ethers.getSigner(deployer));
      });
      it("THEN it has 8 decimals", async () => {
        expect(await mocRC20Decimals.decimals()).to.be.eq(8);
      });
    });
  });
});
