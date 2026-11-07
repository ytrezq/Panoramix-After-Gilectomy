// @ts-nocheck
import { formatUnits } from "ethers";
import { getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/dist/types";
import { expect } from "chai";
import { time } from "../helpers/utils";

const gasEstimationBehavior = function (network, netParams) {
  let mocContracts: any;
  let mocFunctions: any;
  let deployer: Address;
  let gasSummaries = {};
  const TP_0 = 0;
  const TP_1 = 1;

  const gasData = (rawEstimatedGas: number) => {
    const estimatedGas = Math.round(rawEstimatedGas * netParams.gasAdjustmentMultiplier);
    const limit = netParams.blockGasLimit;
    const result = {
      blockGasLimit: limit,
      estimatedGas: estimatedGas,
      gasLeftPct: (((limit - estimatedGas) / limit) * 100).toFixed(2) + "%",
    };

    for (const priceField of ["min", "avg", "median", "max"]) {
      const gasPrice = netParams.gasPricesWei[priceField];
      const gasUsed = estimatedGas * gasPrice;
      result[`${priceField} fee @ ${formatUnits(gasPrice, "gwei")}gw`] = gasUsed;

      result[`$ ${priceField}`] = ((gasUsed * netParams.feeTokenPrice) / 1e18).toFixed(4);
    }

    return result;
  };

  const setGasUsed = async (op, tx) => {
    const gasUsed = Number((await tx.wait())?.gasUsed);
    Object.assign(gasSummaries, { [op]: gasData(gasUsed) });
  };

  const describeConditional = process.env.GAS_ESTIMATION === "true" ? describe : describe.skip;
  describeConditional("Feature: queuing gas estimation", function () {
    beforeEach(async function () {
      mocContracts = this.mocContracts;
      mocFunctions = this.mocFunctions;
      ({ deployer } = await getNamedAccounts());
    });
    describe("GIVEN there are some open positions", function () {
      beforeEach(async function () {
        // initialize bucket to not skip the functions where there are comparisons with 0
        await mocFunctions.mintTC({ from: deployer, qTC: 1000000 });
        await Promise.all(
          mocContracts.mocPeggedTokens.map((p, i) => mocFunctions.mintTP({ i, from: deployer, qTP: 1000 })),
        );
      });
      it("THEN block gas left is over 50% of block gas limit in each one", async function () {
        const common = { from: deployer, qTC: 1, qTP: 100, execute: false };
        const ops = {
          mintTC: () => mocFunctions.mintTC({ ...common }),
          redeemTC: () => mocFunctions.redeemTC({ ...common }),
          mintTP: () => mocFunctions.mintTP({ ...common }),
          redeemTP: () => mocFunctions.redeemTP({ ...common }),
          swapTPforTP: () => mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, ...common }),
          swapTPforTC: () => mocFunctions.swapTPforTC({ ...common }),
          swapTCforTP: () => mocFunctions.swapTCforTP({ ...common }),
          redeemTCandTP: () => mocFunctions.redeemTCandTP({ ...common }),
          mintTCandTP: () => mocFunctions.mintTCandTP({ ...common }),
          execSettlement: async () => {
            await time.increaseTo(await mocContracts.mocImpl.nextSettlementTime());
            return mocContracts.mocImpl.execSettlement();
          },
        };

        for (let op of Object.keys(ops)) {
          await setGasUsed(op, await ops[op]());
          // gas spent should be less than 50% of block gas limit
          expect(gasSummaries[op].estimatedGas, op).lt(netParams.blockGasLimit / 2);
        }
        console.log(
          `${network} Queueing; Price: $${netParams.feeTokenPrice}; Gas adjustment: ${netParams.gasAdjustmentMultiplier}`,
        );
        console.table(gasSummaries);
      }).timeout(10e6);
    });
  });
};

export { gasEstimationBehavior };
