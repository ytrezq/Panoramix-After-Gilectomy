import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { redeemTPBehavior } from "../behaviors/redeemTP.behavior";
import { redeemTPQueueBehavior } from "../behaviors/queue/redeemTPQueue.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 redeem TP", function () {
  describe("GIVEN a MocCARC20 implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocContracts, mocFunctions };
    }
    redeemTPBehavior(setup);
  });
  describe("GIVEN a MocCARC20 implementation deployed behind MocQueue", function () {
    beforeEach(async function () {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      this.mocContracts = await fixtureDeploy();
      this.mocFunctions = await mocFunctionsRC20(this.mocContracts);
    });
    redeemTPQueueBehavior();
  });
});
