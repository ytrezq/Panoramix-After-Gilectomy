// @ts-nocheck
import { formatUnits } from "ethers";
import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/dist/types";
import { mineNBlocks, pEth } from "../helpers/utils";
import { MocRC20 } from "../../typechain";

const gasEstimationExecBehavior = function ({
  network,
  bucketAmount,
  tpAmount,
  iterations,
  avgOperPerBatch,
  gasPricesWei,
  feeTokenPrice,
  gasAdjustementMultiplier = 1,
}: {
  network: string;
  bucketAmount: number;
  tpAmount: number;
  iterations: number;
  avgOperPerBatch: number;
  gasPricesWei: { max: number; min: number; median: number };
  feeTokenPrice: number;
  gasAdjustementMultiplier?: number;
}) {
  let buckets: { contracts: any; functions: any }[] = [];
  let feeToken: MocRC20;
  let alice: Address;
  let bob: Address;
  let charlie: Address;
  let vendor: Address;
  let gasSummaries = {};

  const gasData = (currStats, rawGasUsed: number) => {
    const gasUsed = rawGasUsed * gasAdjustementMultiplier;
    return {
      count: currStats.count + 1,
      minGas: Math.min(currStats.minGas, gasUsed),
      avgGas: currStats.avgGas + gasUsed,
      maxGas: Math.max(currStats.maxGas, gasUsed),
    };
  };

  const setStats = async (op, operationsInBatch, tx) => {
    const txReceipt = await tx.wait();

    const iface = buckets[0].contracts.mocQueue.interface;

    const topicOpError = iface.getEvent("OperationError").topicHash;
    const topicUnhandledError = iface.getEvent("UnhandledError").topicHash;
    const failed = txReceipt?.logs?.some(it => it.topics[0] === topicOpError || it.topics[0] === topicUnhandledError);

    // Failed operations shouldn't be accounted
    if (failed) {
      console.log("!!! Failed operation.", op);
      for (const log of txReceipt.logs) {
        const parsed = iface.parseLog(log);
        if (parsed) {
          console.log("Event", parsed.name);
        }
      }
      return;
    }
    const gasUsedPerOper = Number(txReceipt.gasUsed) / operationsInBatch;
    gasSummaries[op] = gasData(gasSummaries[op], gasUsedPerOper);
  };

  const describeConditional = process.env.GAS_ESTIMATION === "true" ? describe : describe.skip;
  describeConditional("Running estimation", function () {
    beforeEach(async function () {
      if (bucketAmount > 1) {
        buckets = this.buckets.map((it, i) => ({ contracts: it, functions: this.bucketsFncs[i] }));
      } else {
        buckets[0] = { contracts: this.mocContracts, functions: this.mocFunctions };
      }
      feeToken = buckets[0].contracts.feeToken;
      ({ alice, bob, charlie, vendor } = await getNamedAccounts());
      // initialize bucket to not skip the functions where there are comparisons with 0
      for (const bucket of buckets) {
        await bucket.functions.mintTC({ from: alice, qTC: 10e9 });
        await Promise.all(
          bucket.contracts.mocPeggedTokens.map((p, i) => bucket.functions.mintTP({ i, from: alice, qTP: 100e6 })),
        );
      }

      // Guarantee Alice has fee Token Balance
      await feeToken.mint(alice, pEth(10e3));
    });

    it("RESULTS:", async function () {
      const getParams = (index: number) => {
        const i = index % tpAmount;
        const iTo = (index + 1) % tpAmount;
        const result = { i, iFrom: i, iTo, from: alice, qTC: 1, qTP: 100, execute: false };
        // Ensure at least on time we get the max and min cases
        if (index == 0) {
          result.to = undefined;
          result.vendor = undefined;
        } else if (index == 1) {
          result.to = bob;
          result.vendor = vendor;
        } else {
          // Randomly sends funds to other user or himself (undefined)
          result.to = [undefined, alice, bob, charlie][(Math.random() * 4).toFixed(0)];
          // Use Vendors 80 % of the time
          result.vendor = Math.random() > 0.2 ? vendor : undefined;
        }
        return result;
      };

      const operWrap = (j, index, f) => async args => {
        let feeTokenProbability = Math.random();
        // Ensure at least on time we get the min (index = 0) and max (index = 1) cases
        if (index == 0) {
          feeTokenProbability = 0;
        } else if (index == 1) {
          feeTokenProbability = 1;
        }
        // Use fee Token ~50% of the time
        const receipt = await feeToken
          .connect(await ethers.getSigner(alice))
          .approve(buckets[j].contracts.mocImpl.target.toString(), pEth(feeTokenProbability > 0.5 ? 100 : 0));

        await receipt.wait();

        return f(args);
      };

      const getOps = mocFncs => {
        const operations = {
          mintTC: (j, i) => operWrap(j, i, mocFncs.mintTC)({ ...getParams(i) }),
          redeemTC: (j, i) => operWrap(j, i, mocFncs.redeemTC)(getParams(i)),
          mintTP: (j, i) => operWrap(j, i, mocFncs.mintTP)(getParams(i)),
          redeemTP: (j, i) => operWrap(j, i, mocFncs.redeemTP)(getParams(i)),
          swapTPforTC: (j, i) => operWrap(j, i, mocFncs.swapTPforTC)(getParams(i)),
          swapTCforTP: (j, i) => operWrap(j, i, mocFncs.swapTCforTP)(getParams(i)),
          redeemTCandTP: (j, i) => operWrap(j, i, mocFncs.redeemTCandTP)(getParams(i)),
          mintTCandTP: (j, i) => operWrap(j, i, mocFncs.mintTCandTP)(getParams(i)),
        };
        if (tpAmount > 1) {
          operations.swapTPforTP = (j, i) => operWrap(j, i, mocFncs.swapTPforTP)(getParams(i));
        }
        return operations;
      };
      const ops = buckets.map(it => getOps(it.functions));
      for (let i = 0; i < iterations; i++) {
        const batchSize = Math.max(1, (Math.random() * avgOperPerBatch).toFixed(0));
        let operPerBucket = Math.max(1, batchSize / bucketAmount);
        for (let op of Object.keys(ops[0])) {
          for (let j = 0; j < bucketAmount; j++) {
            operPerBucket = j == bucketAmount - 1 ? batchSize - operPerBucket : operPerBucket;
            const mocFnc = buckets[j].functions;
            if (i == 0) {
              gasSummaries[op] = { minGas: Number.MAX_SAFE_INTEGER, maxGas: 0, avgGas: 0, count: 0 };
            }
            for (let k = 0; k < operPerBucket; k++) {
              await mineNBlocks((Math.random() * 5).toFixed(0));
              await Promise.all(
                Array.from(Array(tpAmount).keys()).map(i => {
                  return mocFnc.pokePrice(i, 0.95 + Math.random() / 10);
                }),
              );

              // queue de Operation
              await ops[j][op](j, i + k);
            }
          }
          await setStats(op, batchSize, await buckets[0].functions.executeQueue());
        }
      }
      for (let op of Object.keys(ops[0])) {
        gasSummaries[op].avgGas = (gasSummaries[op].avgGas / gasSummaries[op].count).toFixed(0);
        gasSummaries[op].minGas = gasSummaries[op].minGas.toFixed(0);
        gasSummaries[op].maxGas = gasSummaries[op].maxGas.toFixed(0);

        gasSummaries[op]["$ Best"] = ((gasSummaries[op].minGas * gasPricesWei.min * feeTokenPrice) / 1e18).toFixed(4);
        gasSummaries[op]["$ Worst"] = ((gasSummaries[op].maxGas * gasPricesWei.max * feeTokenPrice) / 1e18).toFixed(4);

        for (const priceField of ["min", "avg", "median", "max"]) {
          const gasPrice = gasPricesWei[priceField];
          gasSummaries[op][`$ avgGas @ ${formatUnits(gasPrice, "gwei")}gw`] = (
            (gasSummaries[op].avgGas * gasPrice * feeTokenPrice) /
            1e18
          ).toFixed(4);
        }
      }

      console.log(
        `${network} Executing; Price: $${feeTokenPrice}; Average OPs per batch: ${avgOperPerBatch}; Collaterals: ${bucketAmount}; Pegs: ${tpAmount}; Gas adjustment: ${gasAdjustementMultiplier}`,
      );
      console.table(gasSummaries);
    }).timeout(10e6);
  });
};

export { gasEstimationExecBehavior };
