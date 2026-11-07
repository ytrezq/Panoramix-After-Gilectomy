import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { successFeeBehavior } from "../behaviors/successFee.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase success fee distribution", function () {
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsCoinbase(mocContracts);
      return { mocContracts, mocFunctions };
    }
    successFeeBehavior(setup);
  });
});
