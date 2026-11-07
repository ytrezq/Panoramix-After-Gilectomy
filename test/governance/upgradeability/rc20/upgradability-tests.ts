import { expect } from "chai";
import { deployments, ethers, getNamedAccounts } from "hardhat";
import {
  IGovernor,
  MocCARC20,
  MocCARC20Mock,
  MocCARC20Mock__factory,
  MocUpgradeChangerMock,
} from "../../../../typechain";
import { fixtureDeployedMocRC20 } from "../../../rc20/fixture";
import { deployAeropagusGovernor, ERRORS, timedDescribe, tpParams } from "../../../helpers/utils";

timedDescribe("Feature: MocCARC20 Upgradeability UUPS", () => {
  let mocProxy: MocCARC20;
  let mocProxyAsRC20Mock: MocCARC20Mock;
  let mocRC20MockImpl: MocCARC20Mock;
  let governor: IGovernor;
  let changeContract: MocUpgradeChangerMock;
  let wrongChangeContract: MocUpgradeChangerMock;

  before(async () => {
    const { deployer } = await getNamedAccounts();
    const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams);
    ({ mocImpl: mocProxy } = await fixtureDeploy());

    // set a real governor
    governor = await deployAeropagusGovernor(deployer);
    await mocProxy.changeGovernor(governor.target.toString());

    const mocRC20MockFactory = await ethers.getContractFactory("MocCARC20Mock");
    mocRC20MockImpl = await mocRC20MockFactory.deploy();

    const changerFactory = await ethers.getContractFactory("MocUpgradeChangerMock");
    changeContract = await changerFactory.deploy(mocProxy.target.toString(), mocRC20MockImpl.target.toString());

    wrongChangeContract = await changerFactory.deploy(
      (await deployments.get("MocCARC20Proxy")).implementation!,
      mocRC20MockImpl.target.toString(),
    );
  });

  describe("GIVEN a Changer contract is set up to upgrade MocRC20", () => {
    describe("WHEN update the contract calling the implementation", () => {
      it("THEN tx reverts because update only can be called by a proxy", async () => {
        await expect(governor.executeChange(wrongChangeContract.target.toString())).to.be.revertedWith(
          "Function must be called through delegatecall",
        );
      });
    });
    describe("WHEN the governor didn't authorize the upgrade", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async () => {
        await expect(mocProxy.upgradeTo(mocRC20MockImpl.target.toString())).to.be.revertedWithCustomError(
          mocProxy,
          ERRORS.NOT_AUTH_CHANGER,
        );
      });
    });
    describe("WHEN the owner updates the contract through governance", () => {
      before(async function () {
        await governor.executeChange(changeContract.target.toString());
        const [signer] = await ethers.getSigners();
        mocProxyAsRC20Mock = MocCARC20Mock__factory.connect(mocProxy.target.toString(), signer);
      });
      it("THEN the new method and values are returned correctly", async function () {
        const newVariable = await mocProxyAsRC20Mock.newVariable();
        expect(newVariable).to.be.equal(42);

        // This method returns the sum of and "old" state variable (protThrld) and the newVariable
        const newAndOldVariable = await mocProxyAsRC20Mock.getCustomMockValue();
        expect(newAndOldVariable).to.be.equal(44);
      });
    });
  });
});
