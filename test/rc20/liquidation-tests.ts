import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { shouldBehaveLikeLiquidable } from "../behaviors/liquidation.behavior";
import { timedDescribe } from "../helpers/utils";
import { fixtureDeployedMocRC20 } from "./fixture";

timedDescribe("Feature: MocCARC20 Liquidation", function () {
  describe("GIVEN a MocCARC20 implementation deployed with two Pegs", function () {
    shouldBehaveLikeLiquidable(fixtureDeployedMocRC20(2), mocFunctionsRC20);
  });
});
