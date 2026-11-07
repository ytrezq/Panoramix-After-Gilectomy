import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { tcHoldersInterestPaymentBehavior } from "../behaviors/tcHoldersInterestPayment.behavior";
import { timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase TC holders interest payment", function () {
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    before(async function () {
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
      this.mocContracts = await fixtureDeploy();
      this.mocFunctions = await mocFunctionsCoinbase(this.mocContracts);
    });
    tcHoldersInterestPaymentBehavior();
  });
});
