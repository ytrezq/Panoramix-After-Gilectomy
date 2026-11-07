import { expect } from "chai";
import hre, { deployments, ethers, getNamedAccounts } from "hardhat";
import {
  IGovernor,
  MocQueue,
  MocQueueMock,
  MocQueueMock__factory,
  MocQueue__factory,
  MocUpgradeChangerMock,
} from "../../../../typechain";
import { deployAeropagusGovernor, ERRORS, getNetworkDeployParams, timedDescribe } from "../../../helpers/utils";

timedDescribe("Feature: MocQueue Upgradeability UUPS", () => {
  let mocQueue: MocQueue;
  let mocQueueAsQueueMock: MocQueueMock;
  let mocQueueMockImpl: MocQueueMock;
  let governor: IGovernor;
  let changeContract: MocUpgradeChangerMock;
  let wrongChangeContract: MocUpgradeChangerMock;

  before(async () => {
    const { deployer } = await getNamedAccounts();
    await deployments.fixture();

    const [signer] = await ethers.getSigners();
    const deployedMocQueue = await deployments.getOrNull("MocQueueCARC20Proxy");
    if (!deployedMocQueue) throw new Error("No MocQueue deployed.");
    mocQueue = MocQueue__factory.connect(deployedMocQueue.address, signer);

    // set a real governor
    governor = await deployAeropagusGovernor(deployer);
    await mocQueue.changeGovernor(governor.target.toString());

    const MocQueueMockFactory = await ethers.getContractFactory("MocQueueMock");
    mocQueueMockImpl = await MocQueueMockFactory.deploy();

    const changerFactory = await ethers.getContractFactory("MocUpgradeChangerMock");
    changeContract = await changerFactory.deploy(mocQueue.target.toString(), mocQueueMockImpl.target.toString());

    wrongChangeContract = await changerFactory.deploy(
      (await deployments.get("MocQueueCARC20Proxy")).implementation!,
      mocQueueMockImpl.target.toString(),
    );
  });

  describe("GIVEN a Changer contract is set up to upgrade MocQueue", () => {
    describe("WHEN update the contract calling the implementation", () => {
      it("THEN tx reverts because update only can be called by a proxy", async () => {
        await expect(governor.executeChange(wrongChangeContract.target.toString())).to.be.revertedWith(
          "Function must be called through delegatecall",
        );
      });
    });
    describe("WHEN the governor didn't authorize the upgrade", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async () => {
        await expect(mocQueue.upgradeTo(mocQueueMockImpl.target.toString())).to.be.revertedWithCustomError(
          mocQueue,
          ERRORS.NOT_AUTH_CHANGER,
        );
      });
    });
    describe("WHEN the owner updates the contract through governance", () => {
      before(async function () {
        await governor.executeChange(changeContract.target.toString());
        const [signer] = await ethers.getSigners();
        mocQueueAsQueueMock = MocQueueMock__factory.connect(mocQueue.target.toString(), signer);
      });
      it("THEN the new method and values are returned correctly", async function () {
        const newVariable = await mocQueueAsQueueMock.newVariable();
        expect(newVariable).to.be.equal(42);

        // This method returns the sum of and "old" state variable (protThrld) and the newVariable
        const newAndOldVariable = await mocQueueAsQueueMock.getCustomMockValue();
        const { tcMintExecCost } = getNetworkDeployParams(hre).queueParams.execCostParams;
        expect(newAndOldVariable).to.be.equal(tcMintExecCost + 42n);
      });
    });
  });
});
