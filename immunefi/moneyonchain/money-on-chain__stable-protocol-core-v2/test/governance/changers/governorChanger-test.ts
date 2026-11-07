import { expect } from "chai";
import { ethers, getNamedAccounts } from "hardhat";
import { fixtureDeployedMocCoinbase } from "../../coinbase/fixture";
import { GovernanceChangerTemplate, GovernorMock, IGovernor, MocCACoinbase } from "../../../typechain";
import { GovernanceChangerTemplate__factory } from "../../../typechain/factories/contracts/governance/changerTemplates/GovernanceChangerTemplate__factory";
import { deployAeropagusGovernor, ERRORS, timedDescribe, tpParams } from "../../helpers/utils";

timedDescribe("Feature: Change MocCore Governor", () => {
  let mocProxy: MocCACoinbase;
  let governor: IGovernor;
  let changeContract: GovernanceChangerTemplate;
  let governorMock: GovernorMock;

  before(async () => {
    const { deployer } = await getNamedAccounts();
    const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams);
    ({ mocImpl: mocProxy } = await fixtureDeploy());

    // set a real governor
    governor = await deployAeropagusGovernor(deployer);
    await mocProxy.changeGovernor(governor.target.toString());

    const governorMockFactory = await ethers.getContractFactory("GovernorMock");
    governorMock = await governorMockFactory.deploy();

    const changerFactory = await ethers.getContractFactory("GovernanceChangerTemplate");
    changeContract = await changerFactory.deploy(mocProxy.target.toString(), governorMock.target.toString());
  });

  describe("GIVEN a Changer contract is set up to change Governor", () => {
    describe("WHEN a unauthorized account executed the changer", () => {
      it("THEN it fails", async function () {
        const [signer] = await ethers.getSigners();
        const governanceChangerTemplate = GovernanceChangerTemplate__factory.connect(
          changeContract.target.toString(),
          signer,
        );
        await expect(governanceChangerTemplate.execute()).to.be.revertedWithCustomError(
          mocProxy,
          ERRORS.NOT_AUTH_CHANGER,
        );
      });
    });
    describe("WHEN a the governor executes the changer contract", () => {
      it("THEN the new governor is assigned", async function () {
        await governor.executeChange(changeContract.target.toString());
        const newGovernor = await mocProxy.governor();
        expect(newGovernor).to.be.equal(governorMock.target.toString());
      });
    });
  });
});
