import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { Address } from "hardhat-deploy/types";
import { MocMultiCollateralGuard, ReentrancyAttackerMock } from "../../typechain";
import { ERRORS, timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "../rc20/fixture";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";

timedDescribe("Feature: mocMultiCollateralGuard reentrance tests", () => {
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let mocContracts: any;
  let mocFunctions: any;
  let deployer: Address;
  let reentrancyAttacker: ReentrancyAttackerMock;
  let reentracyAttack: (op: string, overrides?: any) => any;

  describe("GIVEN a mocMultiCollateralGuard implementation with queued operations", function () {
    before(async function () {
      ({ deployer } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      mocContracts = await fixtureDeploy();
      mocFunctions = await mocFunctionsRC20(mocContracts);
      await mocFunctions.mintTC({ from: deployer, qTC: 1000, execute: false });
      ({ mocMultiCollateralGuard } = mocContracts);
      const factory = await ethers.getContractFactory("ReentrancyAttackerMock");
      reentrancyAttacker = await factory.deploy();
      await mocMultiCollateralGuard.setCoinbaseExecFeeRecipient(reentrancyAttacker.target);
      reentracyAttack = (op: string) =>
        reentrancyAttacker.forward(mocMultiCollateralGuard.target.toString(), op, false);
    });

    describe("WHEN a reentrance attacker contract reentrant execute", () => {
      it("THEN tx fails because there is a reentrant call", async () => {
        const op = mocMultiCollateralGuard.interface.encodeFunctionData("execute");
        await expect(reentracyAttack(op)).to.be.revertedWith(ERRORS.REENTRACYGUARD);
      });
    });
  });
});
