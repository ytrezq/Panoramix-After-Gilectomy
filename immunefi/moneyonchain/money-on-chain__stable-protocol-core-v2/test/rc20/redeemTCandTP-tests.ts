import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { redeemTCandTPBehavior } from "../behaviors/redeemTCandTP.behavior";
import { redeemTCandTPQueueBehavior } from "../behaviors/queue/redeemTCandTPQueue.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 redeem TC and TP", function () {
  describe("GIVEN a MocCARC20 implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocContracts, mocFunctions };
    }
    redeemTCandTPBehavior(setup);
  });

  describe("GIVEN a MocCARC20 implementation deployed behind MocQueue", function () {
    beforeEach(async function () {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      this.mocContracts = await fixtureDeploy();
      this.mocFunctions = await mocFunctionsRC20(this.mocContracts);
    });

    redeemTCandTPQueueBehavior();
  });
});
