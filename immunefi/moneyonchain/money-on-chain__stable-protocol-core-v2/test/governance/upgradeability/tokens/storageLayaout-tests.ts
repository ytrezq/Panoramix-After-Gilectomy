import { expect } from "chai";
import { ethers, upgrades, getNamedAccounts } from "hardhat";
import { MocRC20, MocRC20__factory } from "../../../../typechain";
import { GAS_LIMIT_PATCH, MINTER_ROLE, timedDescribe } from "../../../helpers/utils";

timedDescribe("Feature: Check MocRC20 storage layout compatibility using openzeppelin hardhat upgrade ", () => {
  let mocRC20: MocRC20;
  describe("GIVEN a Moc Collateral Token is deployed", () => {
    before(async () => {
      const { deployer } = await getNamedAccounts();
      const governorMockFactory = await ethers.getContractFactory("GovernorMock");
      const governorMock = await governorMockFactory.deploy();

      const mocTCFactory = await ethers.getContractFactory("MocRC20");

      const mocTCProxy = await upgrades.deployProxy(mocTCFactory, undefined, {
        kind: "uups",
        initializer: false,
      });

      mocRC20 = MocRC20__factory.connect(mocTCProxy.target.toString(), await ethers.getSigner(deployer));
      await mocRC20.initialize("UUPS Test", "UTM", deployer, governorMock.target.toString(), {
        gasLimit: GAS_LIMIT_PATCH,
      });
      await mocRC20.grantRole(MINTER_ROLE, deployer);
      await mocRC20.mint(deployer, 10);
    });
    describe("WHEN it is upgraded to a new implementation", () => {
      it("THEN it succeeds as it is consistent with the previous storage", async () => {
        const mocRC20MockFactory = await ethers.getContractFactory("MocRC20Mock");
        expect(await mocRC20.totalSupply()).to.be.equal(10);
        await upgrades.upgradeProxy(mocRC20.target.toString(), mocRC20MockFactory);
        expect(await mocRC20.totalSupply()).to.be.equal(11);
      });
    });
  });
});
