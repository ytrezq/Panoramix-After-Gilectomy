import { expect } from "chai";
import { deployments, ethers, getNamedAccounts } from "hardhat";
import {
  IGovernor,
  MocCACoinbase,
  MocMultiCollateralGuard,
  MocQueue,
  MocRC20,
  MocRC20Mock,
  MocRC20Mock__factory,
  MocUpgradeChangerMock,
} from "../../../../typechain";
import { fixtureDeployedMocCoinbase } from "../../../coinbase/fixture";
import { deployAeropagusGovernor, ERRORS, timedDescribe, tpParams, noVendor } from "../../../helpers/utils";

timedDescribe("Feature: MocRC20 Upgradeability UUPS", () => {
  let mocTCProxy: MocRC20;
  let mocImpl: MocCACoinbase;
  let mocQueue: MocQueue;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let mocTCProxyAsTCMock: MocRC20Mock;
  let mocRC20MockImpl: MocRC20Mock;
  let governor: IGovernor;
  let changeContract: MocUpgradeChangerMock;
  let wrongChangeContract: MocUpgradeChangerMock;

  before(async () => {
    const { deployer } = await getNamedAccounts();
    const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
    ({ mocCollateralToken: mocTCProxy, mocImpl, mocQueue, mocMultiCollateralGuard } = await fixtureDeploy());

    // set a real governor
    governor = await deployAeropagusGovernor(deployer);
    await mocTCProxy.changeGovernor(governor.target.toString());

    const mocRC20MockFactory = await ethers.getContractFactory("MocRC20Mock");
    mocRC20MockImpl = await mocRC20MockFactory.deploy();

    const changerFactory = await ethers.getContractFactory("MocUpgradeChangerMock");
    changeContract = await changerFactory.deploy(mocTCProxy.target.toString(), mocRC20MockImpl.target.toString());

    wrongChangeContract = await changerFactory.deploy(
      (await deployments.get("CollateralTokenCARC20Proxy")).implementation!,
      mocRC20MockImpl.target.toString(),
    );

    // mint 10 TC
    const execFee = await mocQueue.execCost(1); // mintTC execution fee
    await mocImpl.mintTC(10, deployer, noVendor, { value: execFee + 100n });
    await mocMultiCollateralGuard.execute();
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
        await expect(mocTCProxy.upgradeTo(mocRC20MockImpl.target.toString())).to.be.revertedWithCustomError(
          mocTCProxy,
          ERRORS.NOT_AUTH_CHANGER,
        );
      });
    });
    describe("WHEN the owner updates the contract through governance", () => {
      before(async function () {
        await governor.executeChange(changeContract.target.toString());
        const [signer] = await ethers.getSigners();
        mocTCProxyAsTCMock = MocRC20Mock__factory.connect(mocTCProxy.target.toString(), signer);
      });
      it("THEN the new method and values are returned correctly", async function () {
        const newVariable = await mocTCProxyAsTCMock.newVariable();
        expect(newVariable).to.be.equal(42);

        // This method returns the sum of and "old" state variable (totalSupply) and the newVariable
        const newAndOldVariable = await mocTCProxyAsTCMock.totalSupply();
        expect(newAndOldVariable).to.be.equal(53);
      });
    });
  });
});
