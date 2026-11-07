import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { simParams } from "../helpers/utils";
import { gasEstimationBehavior } from "../behaviors/gas-estimation-queue.behavior";
import { fixtureDeployedMocRC20 } from "./fixture";

const describeConditional = process.env.GAS_ESTIMATION === "true" ? describe : describe.skip;
// Gets excluded from coverage by regEx "gas estimation"
describeConditional("Feature: MocCARC20 gas estimation", function () {
  const { tpAmount } = simParams();
  describe(`GIVEN a MocCARC20 implementation deployed with ${tpAmount} Pegged Tokens`, function () {
    beforeEach(async function () {
      const fixtureDeploy = fixtureDeployedMocRC20(tpAmount, undefined, "MocQueueMock");
      this.mocContracts = await fixtureDeploy();
      this.mocFunctions = await mocFunctionsRC20(this.mocContracts);
    });
    gasEstimationBehavior("RSK", simParams());
  });
});
