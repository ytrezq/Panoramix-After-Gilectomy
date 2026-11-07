// @ts-nocheck
import { getNamedAccounts, ethers } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/dist/types";
import { mineNBlocks, pEth, simParams } from "../helpers/utils";

const gasEstimationExecSizeBehavior = function (tpAmount: number, queueSize: number) {
  let mocContracts: any;
  let mocFncs: any;
  let alice: Address;
  let bob: Address;
  let vendor: Address;
  let gasSummaries = {};
  const { gasPrice, btcUsdPrice } = simParams();

  const gasData = (operationsInBatch: number, currStats: any, gasUsed: number) => ({
    count: currStats.count + operationsInBatch,
    min: Math.min(currStats.min, gasUsed),
    avg: currStats.avg + gasUsed,
    max: Math.max(currStats.max, gasUsed),
  });

  const setStats = async (operationsInBatch: number, tx: ContractTransactionResponse) => {
    const txReceipt = await tx.wait();
    const topicOpError = mocContracts.mocQueue.interface.getEvent("OperationError").topicHash;
    const topicUnhandledError = mocContracts.mocQueue.interface.getEvent("UnhandledError").topicHash;
    const failed = txReceipt.logs.some(it => it.topics[0] === topicOpError || it.topics[0] === topicUnhandledError);
    // Failed operations shouldn't be accounted
    if (failed) {
      console.log("FAILED OPERATION !!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      return;
    }
    const execGasUsed = Number(txReceipt.gasUsed);
    gasSummaries = gasData(operationsInBatch, gasSummaries, execGasUsed);
  };

  describe("Feature: queue executing gas on complete batch", function () {
    beforeEach(async function () {
      mocContracts = this.mocContracts;
      mocFncs = this.mocFunctions;
      ({ alice, bob, vendor } = await getNamedAccounts());
      // initialize bucket to not skip the functions where there are comparisons with 0
      await mocFncs.mintTC({ from: alice, qTC: 10e9 });
      await Promise.all(
        mocContracts.mocPeggedTokens.map((_p: any, i: number) => mocFncs.mintTP({ i, from: alice, qTP: 10e6 })),
      );
      // Guarantee Alice has fee Token Balance
      await mocContracts.feeToken.mint(alice, pEth(10e3));
    });

    it("EXEC RESULTS:", async function () {
      const getParams = (index: number) => {
        const i = index % tpAmount;
        const iTo = (index + 1) % tpAmount;
        return { i, iFrom: i, iTo, from: alice, qTC: 1, qTP: 100, execute: false, vendor, to: bob };
      };

      const operWrap = (f: any) => async (args: any) => {
        // Use fee Token 50% of the time
        await mocContracts.feeToken
          .connect(await ethers.getSigner(alice))
          .approve(mocContracts.mocImpl.target.toString(), pEth(Math.random() > 0.5 ? 100 : 0));
        return f(args);
      };
      // This are the most gas intensive operations
      const ops = {
        swapTCforTP: (i: number) => operWrap(mocFncs.swapTCforTP)(getParams(i)),
        redeemTCandTP: (i: number) => operWrap(mocFncs.redeemTCandTP)(getParams(i)),
        mintTCandTP: (i: number) => operWrap(mocFncs.mintTCandTP)(getParams(i)),
      };
      gasSummaries = { min: Number.MAX_SAFE_INTEGER, max: 0, avg: 0, count: 0 };

      for (let j = 0; j < queueSize; j++) {
        let op = Object.keys(ops)[j % Object.keys(ops).length];
        await mineNBlocks((Math.random() * 4).toFixed(0));
        await Promise.all(Array.from(Array(tpAmount).keys()).map(i => mocFncs.pokePrice(i, 0.95 + Math.random() / 10)));
        // queue the Operation
        await ops[op](j);
      }
      await setStats(queueSize, await mocFncs.executeQueue());

      gasSummaries.avg_per_oper = (gasSummaries.avg / gasSummaries.count).toFixed(0);
      gasSummaries["~fee USD"] = ((gasSummaries.avg * gasPrice * btcUsdPrice) / 1e18).toFixed(2);
      console.table(gasSummaries);
    }).timeout(10e6);
  });
};

export { gasEstimationExecSizeBehavior };
