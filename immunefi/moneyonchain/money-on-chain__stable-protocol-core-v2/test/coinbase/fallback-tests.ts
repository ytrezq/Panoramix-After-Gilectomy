import { ethers } from "hardhat";
import { expect } from "chai";
import { MocCACoinbase } from "../../typechain";
import { pEth, timedDescribe } from "../helpers/utils";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase fallback", function () {
  let mocImpl: MocCACoinbase;

  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    beforeEach(async function () {
      const fixtureDeploy = fixtureDeployedMocCoinbase(1);
      ({ mocImpl } = await fixtureDeploy());
    });
    describe("WHEN Coinbase is sent to the contract", () => {
      beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        await deployer.sendTransaction({
          to: mocImpl.target.toString(),
          value: pEth(100),
        });
      });
      it("THEN total AC available increase 100 AC", async () => {
        expect(await mocImpl.getTotalACavailable()).to.be.equal(pEth(100));
      });
    });
  });
});
