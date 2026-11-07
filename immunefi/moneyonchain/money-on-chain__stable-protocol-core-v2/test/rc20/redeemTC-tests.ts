import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { redeemTCBehavior } from "../behaviors/redeemTC.behavior";
import { redeemTCQueueBehavior } from "../behaviors/queue/redeemTCQueue.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 redeem TC", function () {
  describe("GIVEN a MocCARC20 implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocContracts, mocFunctions };
    }
    redeemTCBehavior(setup);
  });

  describe("GIVEN a MocCARC20 implementation deployed behind MocQueue", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocContracts, mocFunctions };
    }

    redeemTCQueueBehavior(setup);
  });
});
