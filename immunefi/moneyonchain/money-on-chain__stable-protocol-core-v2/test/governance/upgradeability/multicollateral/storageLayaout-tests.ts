import { ethers, upgrades, deployments } from "hardhat";
import { MocMultiCollateralGuard, MocMultiCollateralGuard__factory } from "../../../../typechain";
import { timedDescribe } from "../../../helpers/utils";

timedDescribe(
  "Feature: Check MocMultiCollateralGuard storage layout compatibility using openzeppelin hardhat upgrade ",
  () => {
    let mocMultiCollateralGuard: MocMultiCollateralGuard;
    let mocMultiCollateralGuardFactory: any;
    let mocMultiCollateralMockFactory: any;
    describe("GIVEN a MocMultiCollateralGuard Proxy is deployed", () => {
      before(async () => {
        await deployments.fixture();
        const [signer] = await ethers.getSigners();
        const deployedMocMultiCollateralGuard = await deployments.getOrNull("MocMultiCollateralGuardCARC20Proxy");
        if (!deployedMocMultiCollateralGuard) throw new Error("No MocMultiCollateralGuardProxy deployed.");
        mocMultiCollateralGuard = MocMultiCollateralGuard__factory.connect(
          deployedMocMultiCollateralGuard.address,
          signer,
        );
        mocMultiCollateralGuardFactory = await ethers.getContractFactory("MocMultiCollateralGuard");
        mocMultiCollateralMockFactory = await ethers.getContractFactory("MocMultiCollateralGuardMock");
      });
      describe("WHEN it is upgraded to a new implementation", () => {
        it("THEN it succeeds as it is consistent with the previous storage", async () => {
          // forces the import of an existing proxy to be used with this plugin
          await upgrades.forceImport(mocMultiCollateralGuard.target.toString(), mocMultiCollateralGuardFactory);
          await upgrades.upgradeProxy(mocMultiCollateralGuard.target.toString(), mocMultiCollateralMockFactory);
        });
      });
      describe("WHEN check storage layout compatibility between MocMultiCollateralGuard and MocMultiCollateralGuardMock", () => {
        it("THEN it succeeds as there is not storage collision", async () => {
          await upgrades.validateUpgrade(mocMultiCollateralGuardFactory, mocMultiCollateralMockFactory);
        });
      });
    });
  },
);
