import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { successFeeBehavior } from "../behaviors/successFee.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCR20 success fee distribution", function () {
  describe("GIVEN a MocCR20 implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsRC20(mocContracts);
      return { mocContracts, mocFunctions };
    }
    successFeeBehavior(setup);
  });
});
