import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { shouldBehaveLikeLiquidable } from "../behaviors/liquidation.behavior";
import { timedDescribe } from "../helpers/utils";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase Liquidation", function () {
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock and two Pegs", function () {
    shouldBehaveLikeLiquidable(fixtureDeployedMocCoinbase(2), mocFunctionsCoinbase);
  });
});
