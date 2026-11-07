import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { gasEstimationExecBehavior } from "../behaviors/gas-estimation-exec.behavior";
import { simParams } from "../helpers/utils";
import { fixtureDeployedMulticollateral } from "./fixture";

// Gets excluded from coverage by regEx "gas estimation"
describe("Feature: MultiBucket gas estimation", function () {
  const {
    execFee: { bucketAmount, tpAmount, iter, avgOperPerBatch },
    gasPricesWei,
    feeTokenPrice,
  } = simParams();
  describe(`GIVEN a ${bucketAmount} buckets implementation with ${tpAmount} Pegged Tokens`, function () {
    async function fixture() {
      return fixtureDeployedMulticollateral(tpAmount, undefined, bucketAmount - 1);
    }
    describe(`AND a simulation averaging ${avgOperPerBatch} operations per batch`, function () {
      beforeEach(async function () {
        const mocContracts = await loadFixture(fixture);
        const mocFunctions: any[] = [];
        const bucket0: any = { ...mocContracts.mocBucketContracts[0], ...mocContracts };
        mocFunctions[0] = await mocFunctionsRC20(bucket0);
        const bucket1: any = { ...mocContracts.mocBucketContracts[1], ...mocContracts };
        mocFunctions[1] = await mocFunctionsCoinbase(bucket1);

        this.buckets = [bucket0, bucket1];
        this.bucketsFncs = mocFunctions;
      });
      gasEstimationExecBehavior({
        network: "rsk",
        bucketAmount,
        tpAmount,
        iterations: iter,
        avgOperPerBatch,
        gasPricesWei,
        feeTokenPrice,
      });
    });
  });
});
