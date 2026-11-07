import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { feeTokenBehavior } from "../behaviors/queue/feeToken.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase Fee Token", function () {
  describe("GIVEN a MocCoinbase implementation deployed", function () {
    beforeEach(async function () {
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
      this.mocContracts = await fixtureDeploy();
      this.mocFunctions = await mocFunctionsCoinbase(this.mocContracts);
    });
    feeTokenBehavior();
  });
});
