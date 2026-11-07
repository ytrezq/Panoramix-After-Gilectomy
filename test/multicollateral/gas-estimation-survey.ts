import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { gasEstimationExecBehavior } from "../behaviors/gas-estimation-exec.behavior";
import { gasEstimationBehavior } from "../behaviors/gas-estimation-queue.behavior";
import { fixtureDeployedMocRC20 } from "../rc20/fixture";
import { fixtureDeployedMulticollateral } from "./fixture";

const networks = {
  ETH: {
    feeTokenPrice: 3245,
    blockGasLimit: 60000000,
    gasPricesWei: {
      min: 27000000,
      avg: 249400000,
      median: 147500000,
      max: 2310000000,
    },
    gasAdjustmentMultiplier: 1.2,
  },
  ARB: {
    feeTokenPrice: 3245,
    blockGasLimit: 32000000,
    gasPricesWei: {
      min: 10000000,
      avg: 29000000,
      median: 19000000,
      max: 1000000000,
    },
    gasAdjustmentMultiplier: 1.2,
  },
  POL: {
    feeTokenPrice: 0.122,
    blockGasLimit: 45000000,
    gasPricesWei: {
      min: 27000000000,
      avg: 15000000000,
      median: 18000000000,
      max: 439000000000,
    },
    gasAdjustmentMultiplier: 1.2,
  },
  BNB: {
    feeTokenPrice: 885,
    blockGasLimit: 100000000,
    gasPricesWei: {
      min: 50000000,
      avg: 50000000,
      median: 50000000,
      max: 50000000,
    },
    gasAdjustmentMultiplier: 1.1,
  },
};

// Gets excluded from coverage by regEx "gas estimation"
describe("Feature: General survey gas estimation", function () {
  const baseBuckets = 2;
  const tpCounts = [2, 3, 4, 5];
  const extraBucketCounts = [0, 1, 2, 3];

  for (const [network, netParams] of Object.entries(networks)) {
    const gasPricesWei = netParams.gasPricesWei;
    const feeTokenPrice = netParams.feeTokenPrice;

    describe(`GIVEN a MocCARC2 implementation deployed with 5 Pegged Tokens`, async function () {
      beforeEach(async function () {
        const fixtureDeploy = fixtureDeployedMocRC20(5);
        this.mocContracts = await fixtureDeploy();
        this.mocFunctions = await mocFunctionsRC20(this.mocContracts);
      });
      gasEstimationBehavior(network, netParams);
    });

    for (const extraBuckets of extraBucketCounts) {
      const bucketAmount = baseBuckets + extraBuckets;

      for (const tpAmount of tpCounts) {
        describe(`GIVEN a ${bucketAmount} buckets implementation with ${tpAmount} Pegged Tokens`, function () {
          async function fixture() {
            // This deployment implies two initial buckets.
            return fixtureDeployedMulticollateral(tpAmount, undefined, extraBuckets);
          }
          for (const [avgOperPerBatch, iterations] of [
            [1, 100],
            [10, 100],
          ]) {
            describe(`AND a simulation averaging ${avgOperPerBatch} operations per batch`, function () {
              beforeEach(async function () {
                const mocContracts = await loadFixture(fixture);
                const mocFunctions: any[] = [];
                const mocBuckets: any[] = [];

                mocBuckets[0] = { ...mocContracts.mocBucketContracts[0], ...mocContracts };
                mocFunctions[0] = await mocFunctionsRC20(mocBuckets[0]);

                mocBuckets[1] = { ...mocContracts.mocBucketContracts[1], ...mocContracts };
                mocFunctions[1] = await mocFunctionsCoinbase(mocBuckets[1]);

                for (let i = 2; i < bucketAmount; i++) {
                  mocBuckets[i] = { ...mocContracts.mocBucketContracts[i], ...mocContracts };
                  mocFunctions[i] = await mocFunctionsRC20(mocBuckets[i]);
                }

                this.buckets = mocBuckets;
                this.bucketsFncs = mocFunctions;
              });
              gasEstimationExecBehavior({
                network,
                bucketAmount,
                tpAmount,
                iterations,
                avgOperPerBatch,
                gasPricesWei,
                feeTokenPrice,
                gasAdjustementMultiplier: netParams.gasAdjustmentMultiplier,
              });
            });
          }
        });
      }
    }
  }
});
