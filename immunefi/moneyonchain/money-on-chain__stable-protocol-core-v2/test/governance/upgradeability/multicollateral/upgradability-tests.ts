import { expect } from "chai";
import hre, { deployments, ethers, getNamedAccounts } from "hardhat";
import {
  IGovernor,
  MocMultiCollateralGuard,
  MocMultiCollateralGuard__factory,
  MocMultiCollateralGuardMock,
  MocMultiCollateralGuardMock__factory,
  MocUpgradeChangerMock,
} from "../../../../typechain";
import { deployAeropagusGovernor, ERRORS, getNetworkDeployParams, timedDescribe } from "../../../helpers/utils";

timedDescribe("Feature: MocMultiCollateralGuard Upgradeability UUPS", () => {
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let mocMultiCollateralGuardAsMock: MocMultiCollateralGuardMock;
  let mocMultiCollateralGuardMockImpl: MocMultiCollateralGuardMock;
  let governor: IGovernor;
  let changeContract: MocUpgradeChangerMock;
  let wrongChangeContract: MocUpgradeChangerMock;

  before(async () => {
    const { deployer } = await getNamedAccounts();
    await deployments.fixture();

    const [signer] = await ethers.getSigners();
    const deployedMocMultiCollateralGuard = await deployments.getOrNull("MocMultiCollateralGuardCARC20Proxy");
    if (!deployedMocMultiCollateralGuard) throw new Error("No MocMultiCollateralGuard deployed.");
    mocMultiCollateralGuard = MocMultiCollateralGuard__factory.connect(deployedMocMultiCollateralGuard.address, signer);

    // set a real governor
    governor = await deployAeropagusGovernor(deployer);
    await mocMultiCollateralGuard.changeGovernor(governor.target.toString());

    const MocMultiCollateralGuardMockFactory = await ethers.getContractFactory("MocMultiCollateralGuardMock");
    mocMultiCollateralGuardMockImpl = await MocMultiCollateralGuardMockFactory.deploy();

    const changerFactory = await ethers.getContractFactory("MocUpgradeChangerMock");
    changeContract = await changerFactory.deploy(
      mocMultiCollateralGuard.target.toString(),
      mocMultiCollateralGuardMockImpl.target.toString(),
    );

    wrongChangeContract = await changerFactory.deploy(
      (await deployments.get("MocMultiCollateralGuardCARC20Proxy")).implementation!,
      mocMultiCollateralGuardMockImpl.target.toString(),
    );
  });

  describe("GIVEN a Changer contract is set up to upgrade MocMultiCollateralGuard", () => {
    describe("WHEN update the contract calling the implementation", () => {
      it("THEN tx reverts because update only can be called by a proxy", async () => {
        await expect(governor.executeChange(wrongChangeContract.target.toString())).to.be.revertedWith(
          "Function must be called through delegatecall",
        );
      });
    });
    describe("WHEN the governor didn't authorize the upgrade", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async () => {
        await expect(
          mocMultiCollateralGuard.upgradeTo(mocMultiCollateralGuardMockImpl.target.toString()),
        ).to.be.revertedWithCustomError(mocMultiCollateralGuard, ERRORS.NOT_AUTH_CHANGER);
      });
    });
    describe("WHEN the owner updates the contract through governance", () => {
      before(async function () {
        await governor.executeChange(changeContract.target.toString());
        const [signer] = await ethers.getSigners();
        mocMultiCollateralGuardAsMock = MocMultiCollateralGuardMock__factory.connect(
          mocMultiCollateralGuard.target.toString(),
          signer,
        );
      });
      it("THEN the new method and values are returned correctly", async function () {
        const newVariable = await mocMultiCollateralGuardAsMock.newVariable();
        expect(newVariable).to.be.equal(42);

        // This method returns the sum of and "old" state variable (maxOperPerBatch) and the newVariable
        const newAndOldVariable = await mocMultiCollateralGuardAsMock.getCustomMockValue();
        const maxOperPerBatch = getNetworkDeployParams(hre).multiCollateralParams.maxOperPerBatch;
        expect(newAndOldVariable).to.be.equal(maxOperPerBatch + 42n);
      });
    });
  });
});
