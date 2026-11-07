import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mintTCandTPBehavior } from "../behaviors/mintTCandTP.behavior";
import { mintTCandTPQueueBehavior } from "../behaviors/queue/mintTCandTPQueue.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 mint TC and TP", function () {
  describe("GIVEN a MocCARC20 implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocContracts, mocFunctions };
    }
    mintTCandTPBehavior(setup);
  });
  describe("GIVEN a MocCARC20 implementation deployed behind MocQueue", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocContracts, mocFunctions };
    }
    mintTCandTPQueueBehavior(setup);
  });
});
