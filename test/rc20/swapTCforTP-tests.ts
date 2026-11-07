import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { swapTCforTPBehavior } from "../behaviors/swapTCforTP.behavior";
import { swapTCforTPQueueBehavior } from "../behaviors/queue/swapTCforTPQueue.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 swap TC for TP", function () {
  describe("GIVEN a MocCARC20 implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocContracts, mocFunctions };
    }
    swapTCforTPBehavior(setup);
  });
  describe("GIVEN a MocCARC20 implementation deployed behind MocQueue", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocFunctions, mocContracts };
    }
    swapTCforTPQueueBehavior(setup);
  });
});
