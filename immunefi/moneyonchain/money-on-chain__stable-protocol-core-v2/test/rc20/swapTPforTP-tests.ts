import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { swapTPforTPBehavior } from "../behaviors/swapTPforTP.behavior";
import { swapTPforTPQueueBehavior } from "../behaviors/queue/swapTPforTPQueue.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 swap TP for TP", function () {
  describe("GIVEN a MocCARC20 implementation deployed with mocQueueMock", function () {
    const setup = async () => {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocFunctions, mocContracts };
    };
    swapTPforTPBehavior(setup);
  });
  describe("GIVEN a MocCARC20 implementation deployed behind MocQueue", function () {
    const setup = async () => {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocFunctions, mocContracts };
    };
    swapTPforTPQueueBehavior(setup);
  });
});
