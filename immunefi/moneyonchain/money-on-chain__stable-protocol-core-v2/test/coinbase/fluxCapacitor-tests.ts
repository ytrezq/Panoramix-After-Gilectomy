import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { fluxCapacitorBehavior } from "../behaviors/fluxCapacitor.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase Flux capacitor", function () {
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    const setup = async () => {
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsCoinbase(mocContracts);
      // on flux capacitor tests all the operations happens in the same block, we need waiting blocks on 0
      await mocContracts.mocQueue.setMinOperWaitingBlk(0);

      return { mocContracts, mocFunctions };
    };
    fluxCapacitorBehavior(setup);
  });
});
