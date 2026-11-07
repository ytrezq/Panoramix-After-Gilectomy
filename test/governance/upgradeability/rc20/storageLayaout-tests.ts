import { ethers, upgrades } from "hardhat";
import { fixtureDeployedMocRC20 } from "../../../rc20/fixture";
import { timedDescribe, tpParams } from "../../../helpers/utils";
import { MocCARC20 } from "../../../../typechain";

timedDescribe("Feature: Check MocCARC20 storage layout compatibility using openzeppelin hardhat upgrade ", () => {
  let mocProxy: MocCARC20;
  describe("GIVEN a MocCARC20 Proxy is deployed", () => {
    before(async () => {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams);
      ({ mocImpl: mocProxy } = await fixtureDeploy());
    });
    describe("WHEN it is upgraded to a new implementation", () => {
      it("THEN it succeeds as it is consistent with the previous storage", async () => {
        const mocRC20Factory = await ethers.getContractFactory("MocCARC20");
        const mocRC20MockFactory = await ethers.getContractFactory("MocCARC20Mock");
        // forces the import of an existing proxy to be used with this plugin
        await upgrades.forceImport(mocProxy.target.toString(), mocRC20Factory);
        await upgrades.upgradeProxy(mocProxy.target.toString(), mocRC20MockFactory);
      });
    });
    describe("WHEN check storage layout compatibility between MocCore and MocCoreExpansion", () => {
      // this test will fail if new storage variables are declare in MocCore.sol or MocCoreExtension.sol
      it("THEN it succeeds as there is not storage collision", async () => {
        const mocRC20Factory = await ethers.getContractFactory("MocCARC20");
        const mocCoreExpansionFactory = await ethers.getContractFactory("MocCoreExpansion");
        await upgrades.validateUpgrade(mocCoreExpansionFactory, mocRC20Factory, {
          // we allow delegatecall to use MocCoreExpansion
          unsafeAllow: ["delegatecall"],
        });
      });
    });
  });
});
