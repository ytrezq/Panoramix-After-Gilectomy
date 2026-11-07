import { expect } from "chai";
import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { ERRORS, timedDescribe, tpParams } from "../../helpers/utils";
import { GovernorMock__factory, MocCARC20, MocMultiCollateralGuard } from "../../../typechain";
import { fixtureDeployedMocRC20 } from "../../rc20/fixture";

timedDescribe("Feature: MocMultiCollateralGuard Pausing", function () {
  describe("GIVEN a MocMultiCollateralGuard implementation", function () {
    let pauser: Address;
    let mocImpl: MocCARC20;
    let mocMultiCollateralGuard: MocMultiCollateralGuard;

    const expectPauseRevert = async (result: any) =>
      expect(result).to.be.revertedWithCustomError(mocMultiCollateralGuard, ERRORS.NOT_WHEN_PAUSED);

    before(async function () {
      ({ deployer: pauser } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();

      ({ mocImpl, mocMultiCollateralGuard } = mocContracts);
      const governorAddress = await mocMultiCollateralGuard.governor();
      const governorMock = GovernorMock__factory.connect(governorAddress, await ethers.getSigner(pauser));
      await governorMock.setIsAuthorized(true);
      await mocMultiCollateralGuard.setPauser(pauser);
      await mocMultiCollateralGuard.makeStoppable();
    });
    describe("WHEN mocMultiCollateralGuard is paused", function () {
      before(async function () {
        await mocMultiCollateralGuard.pause();
      });
      it("THEN it fails when a user tries to execute operations", async function () {
        await expectPauseRevert(mocMultiCollateralGuard.execute());
      });
      it("THEN it fails when a user tries to execute operations on a liquidated bucket", async function () {
        await expectPauseRevert(mocMultiCollateralGuard.executeLiquidatedBucket(mocImpl.target));
      });
      it("THEN it fails when a user tries to execute a micro liquidation", async function () {
        await expectPauseRevert(mocMultiCollateralGuard.execMicroLiquidation(mocImpl.target));
      });
      it("THEN it fails when a user tries to execute a liquidation", async function () {
        await expectPauseRevert(mocMultiCollateralGuard.execLiquidation(mocImpl.target));
      });
    });
  });
});
