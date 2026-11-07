import { ethers } from "hardhat";
import { expect } from "chai";
import { MocCARC20 } from "../../typechain";
import { pEth, timedDescribe } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 rejects coinbase transfers", function () {
  let mocImpl: MocCARC20;

  describe("GIVEN a MocCARC20 implementation deployed", function () {
    beforeEach(async function () {
      ({ mocImpl } = await fixtureDeployedMocRC20(0)());
    });
    describe("WHEN coinbase is sent to the contract", () => {
      it("THEN it fails", async () => {
        const [deployer] = await ethers.getSigners();
        await expect(
          deployer.sendTransaction({
            to: mocImpl.target.toString(),
            value: pEth(100),
          }),
        ).to.be.reverted;
      });
    });
  });
});
