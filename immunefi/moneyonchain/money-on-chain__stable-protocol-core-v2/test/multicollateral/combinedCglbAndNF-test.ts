import { getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { MocMultiCollateralGuard, MocRC20 } from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { CONSTANTS, pEth, timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMulticollateral } from "./fixture";

timedDescribe("Feature: multicollateral combined coverage and normalization factor", function () {
  let mocFunctions = new Array<any>(2);
  let bucket0: any;
  let bucket1: any;
  let deployer: Address;
  let tp0: MocRC20;
  let tp1: MocRC20;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let assertCombinedCoverage = async (expectedValue: any) =>
    assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), expectedValue);
  let assertNormalizationFactor = async (expectedValue: any) =>
    assertPrec((await mocMultiCollateralGuard.getNormalizationFactors())[1], expectedValue);

  describe("GIVEN 2 Moc implementations deployed with 5 TP added, AC0 price is 5 times AC1 price", function () {
    before(async function () {
      ({ deployer } = await getNamedAccounts());
      // deploy priceProviders for bucket 1 with prices multiplied by 5
      const bucket1TPsToAdd = tpParams.map((param, index) => ({
        index,
        params: { ...param, price: param.price * 5n },
      }));

      const mocContracts = await fixtureDeployedMulticollateral(5, tpParams, 0, [bucket1TPsToAdd]);
      ({
        mocBucketContracts: [bucket0, bucket1],
        mocMultiCollateralGuard,
        mocPeggedTokens: [tp0, tp1],
      } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...bucket0, ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...bucket1, ...mocContracts });
    });
    describe("WHEN mints 1000 TC on bucket 0 being bucket 0 and bucket 1 empty", () => {
      before(async () => {
        await mocFunctions[0].mintTC({ from: deployer, qTC: 1000 });
      });
      it("THEN combined coverage is max uint256", async () => {
        await assertCombinedCoverage(CONSTANTS.MAX_UINT256);
      });
      describe("AND mints 2350 TP 0 on bucket 0 being bucket 1 empty", () => {
        before(async () => {
          await mocFunctions[0].mintTP({ tp: tp0.target.toString(), from: deployer, qTP: 2350 });
        });
        it("THEN combined coverage is 101", async () => {
          // AC = 1010
          // lckAC = 10
          // coverage = 1010 / 10 = 101
          await assertCombinedCoverage(101);
        });
        describe("WHEN mints 1000 TC on bucket 1", () => {
          before(async () => {
            await mocFunctions[1].mintTC({ from: deployer, qTC: 1000 });
          });
          it("THEN combined coverage is still 101 because not TP were minted on bucket 1", async () => {
            // AC = 1010
            // lckAC = 10
            // coverage = 1010 / 10 = 101
            await assertCombinedCoverage(101);
          });
          describe("AND mints 11750 TP 0 to bucket 1", () => {
            before(async () => {
              await mocFunctions[1].mintTP({ tp: tp0.target.toString(), from: deployer, qTP: 11750 });
            });
            it("THEN combined coverage is 101 nf1 == 5", async () => {
              // AC bucket 0 = 1010
              // lckAC bucket 0 = 10
              // coverage bucket 0 = 1010 / 10 = 101

              // AC bucket 1 = 1010
              // lckAC bucket 1 = 10
              // coverage bucket 1 = 1010 / 10 = 101

              // normalization factor AC1 = 1175 / 235 = 5
              // lckAC1 normalized = 10 * 5 = 50 AC0
              // combined coverage = (101 * 10 + 101 * 50) / (10 + 50) = 101
              await assertCombinedCoverage(101);
            });
            describe("AND mints 525 TP 1 to bucket 0", () => {
              before(async () => {
                await mocFunctions[0].mintTP({ tp: tp1.target.toString(), from: deployer, qTP: 525 });
              });
              it("THEN normalization factor AC1 is 5", async () => {
                // AC bucket 0 = 1110
                // lckAC bucket 0 = 110
                // coverage bucket 0 = 1110 / 110 = 10.09

                // AC bucket 1 = 1010
                // lckAC bucket 1 = 10
                // coverage bucket 1 = 1010 / 10 = 101

                // normalization factor AC1 = 1175 / 235  = 5
                await assertNormalizationFactor(5);
              });
              it("THEN combined coverage is 38.49 with nf1 == 5", async () => {
                // lckAC1 normalized = 10 * 5 = 50 AC0
                // combined coverage = (10.09 * 110 + 101 * 50) / (110 + 50) = 38.49
                await assertCombinedCoverage("38.499999999999999999");
              });
              describe("AND TP 1 price goes to 105 for bucket 1, increasing the nf1 to 8", () => {
                before(async () => {
                  await bucket1.priceProviders[tp1.target.toString()].poke(pEth(105));
                });
                it("THEN normalization factor AC1 is 8", async () => {
                  // AC bucket 0 = 1110
                  // lckAC bucket 0 = 110
                  // coverage bucket 0 = 1110 / 110 = 10.09

                  // AC bucket 1 = 1010
                  // lckAC bucket 1 = 10
                  // coverage bucket 1 = 1010 / 10 = 101

                  // normalization factor AC1 = 8
                  await assertNormalizationFactor(8);
                });
                // TODO: review this if we change avg calculation by the median
                it("THEN combined coverage is 48.36 with nf1 == 8", async () => {
                  // lckAC1 normalized = 10 * 8 = 80 AC0
                  // combined coverage = (10.09 * 110 + 101 * 80) / (110 + 80) = 48.36
                  await assertCombinedCoverage("48.368421052631578947");
                });
              });
              describe("AND TP 1 price goes to 1.05 for bucket 1, decreasing the nf1 to 4.04", () => {
                before(async () => {
                  await bucket1.priceProviders[tp1.target.toString()].poke(pEth(1.05));
                });
                it("THEN normalization factor AC1 is 4.04", async () => {
                  // AC bucket 0 = 1110
                  // lckAC bucket 0 = 110
                  // coverage bucket 0 = 1110 / 110 = 10.09

                  // AC bucket 1 = 1010
                  // lckAC bucket 1 = 10
                  // coverage bucket 1 = 1010 / 10 = 101

                  // normalization factor AC1 = 4.04
                  await assertNormalizationFactor(4.04);
                });
                // TODO: review this if we change avg calculation by the median
                it("THEN combined coverage is 34.51 with nf1 == 4.04", async () => {
                  // lckAC1 normalized = 10 * 4.04 = 40.4 AC0
                  // combined coverage = (10.09 * 110 + 101 * 40.4) / (110 + 40.4) = 34.51
                  await assertCombinedCoverage("34.510638297872340425");
                });
              });
              describe("AND TPs bucket 0 have double price than bucket 1, decreasing the nf1 to 0.5", () => {
                before(async () => {
                  await Promise.all(
                    tpParams.map(async (tpParam, index) => {
                      const tp = await bucket1.mocImpl.tpTokens(index);
                      return bucket1.priceProviders[tp].poke(tpParam.price / 2n);
                    }),
                  );
                });
                it("THEN normalization factor AC1 is 0.5", async () => {
                  // AC bucket 0 = 1110
                  // lckAC bucket 0 = 110
                  // coverage bucket 0 = 1110 / 110 = 10.09

                  // AC bucket 1 = 1010
                  // lckAC bucket 1 = 100
                  // coverage bucket 1 = 1010 / 100 = 10.1

                  // normalization factor AC1 = 0.5
                  await assertNormalizationFactor(0.5);
                });
                // TODO: review this if we change avg calculation by the median
                it("THEN combined coverage is 10.09 with nf1 == 0.5", async () => {
                  // lckAC1 normalized = 100 * 0.5 = 50 AC0
                  // combined coverage = (10.09 * 110 + 10.1 * 50) / (110 + 50) = 10.09
                  await assertCombinedCoverage("10.093749999999999999");
                });
              });
              describe("AND TPs on bucket 0 have the same price than bucket 1, making the nf1 == 1", () => {
                before(async () => {
                  await Promise.all(
                    tpParams.map(async (tpParam, index) => {
                      const tp = await bucket1.mocImpl.tpTokens(index);
                      return bucket1.priceProviders[tp].poke(tpParam.price);
                    }),
                  );
                });
                it("THEN normalization factor AC1 is 1", async () => {
                  await assertNormalizationFactor(1);
                });
                // TODO: review this if we change avg calculation by the median
                it("THEN combined coverage is 13.24 with nf1 == 1", async () => {
                  // AC bucket 0 = 1110
                  // lckAC bucket 0 = 110
                  // coverage bucket 0 = 1110 / 110 = 10.09

                  // AC bucket 1 = 1010
                  // lckAC bucket 1 = 50
                  // coverage bucket 1 = 1010 / 50 = 20.2
                  // lckAC1 normalized = 10 * 1 = 10 AC0

                  // combined coverage = (10.09 * 110 + 20.2 * 50) / (110 + 50) = 13.24
                  await assertCombinedCoverage("13.249999999999999999");
                });
              });
            });
          });
        });
      });
    });
  });
});
