import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { swapTPforTCBehavior } from "../behaviors/swapTPforTC.behavior";
import { swapTPforTCQueueBehavior } from "../behaviors/queue/swapTPforTCQueue.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 swap TP for TC", function () {
  describe("GIVEN a MocCARC20 implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocContracts, mocFunctions };
    }
    swapTPforTCBehavior(setup);
  });
  describe("GIVEN a MocCARC20 implementation deployed behind MocQueue", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocContracts, mocFunctions };
    }
    swapTPforTCQueueBehavior(setup);
  });
});
