import { expect } from "chai";
import { getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { MocMultiCollateralGuard, MocRC20 } from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { ERROR_SELECTOR, pEth, timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMulticollateral } from "./fixture";

timedDescribe("Feature: multicollateral real TP available to mint", function () {
  let mocFunctions = new Array<any>(3);
  let bucket0: any;
  let bucket1: any;
  let tp0: MocRC20;
  let tp1: MocRC20;
  let deployer: Address;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let verifyCoverage: () => Promise<void>;
  let assertTPAvailableToMint = async (
    bucket: any,
    tp: any,
    expectedValue: any,
    message?: string,
    tolerance?: number,
  ) =>
    assertPrec(
      await mocMultiCollateralGuard.getRealTPAvailableToMint(bucket.mocImpl.target.toString(), tp.target.toString()),
      expectedValue,
      message,
      tolerance,
    );
  let expectFail = async (bucket: any, tx: any) =>
    expect(await tx)
      .to.emit(bucket.mocQueue, "OperationError")
      .withArgs(
        (await bucket.mocQueue.operIdCount()) - 1n,
        ERROR_SELECTOR.INSUFFICIENT_TP_TO_MINT,
        "Insufficient tp to mint",
      );

  describe("GIVEN 2 mocCore implementation deployed with 2 TPs added on each bucket", function () {
    async function fixture() {
      return fixtureDeployedMulticollateral(2, tpParams);
    }
    beforeEach(async function () {
      ({ deployer } = await getNamedAccounts());

      const mocContracts = await loadFixture(fixture);
      ({
        mocBucketContracts: [bucket0, bucket1],
        mocMultiCollateralGuard,
        mocPeggedTokens: [tp0, tp1],
      } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...bucket0, ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...bucket1, ...mocContracts });

      verifyCoverage = async () => {
        const [
          bucket0LocalCglb,
          bucket1LocalCglb,
          bucket0CtargemaCA,
          bucket1CtargemaCA,
          combinedCglb,
          combinedCtargemaCA,
        ] = await Promise.all([
          bucket0.mocImpl.getCglb(),
          bucket1.mocImpl.getCglb(),
          bucket0.mocImpl.getCtargemaCA(),
          bucket1.mocImpl.getCtargemaCA(),
          mocMultiCollateralGuard.getCombinedCglb(),
          mocMultiCollateralGuard.getCombinedCtargemaCA(),
        ]);
        expect(bucket0LocalCglb).be.greaterThanOrEqual(bucket0CtargemaCA);
        expect(bucket1LocalCglb).be.greaterThanOrEqual(bucket1CtargemaCA);
        expect(combinedCglb).be.greaterThanOrEqual(combinedCtargemaCA);
      };
    });
    describe("WHEN mints 1000 TC on bucket 0 and 500 TC on bucket 1", () => {
      beforeEach(async () => {
        await mocFunctions[0].mintTC({ from: deployer, qTC: 1000 });
        await mocFunctions[1].mintTC({ from: deployer, qTC: 500 });
      });
      it("THEN there are TP 0 available to mint: 51746 on bucket 0 and 25873 on bucket 1", async () => {
        // bucket 0:
        //  AC: 1000
        //  lckAC: 0
        // ctargemaTP0: 5.54 => TPAvailableToMint: 51746.07

        // bucket 1:
        //  AC: 500
        //  lckAC: 0
        //  ctargemaTP0: 5.54 => TPAvailableToMint: 25873.03

        // realTPtoMint = min(51746.07, 51746.07 + 25873.03)
        await assertTPAvailableToMint(bucket0, tp0, "51746.074603306471719859");
        // realTPtoMint = min(25873.05, 51746.07 + 25873.03)
        await assertTPAvailableToMint(bucket1, tp0, "25873.037301653235859929");
      });
      it("THEN there are TP 1 available to mint: 1657 on bucket 0 and 828 on bucket 1", async () => {
        // bucket 0:
        //  AC: 1000
        //  lckAC: 0
        // ctargemaTP1: 4.16 => TPAvailableToMint: 1657.89

        // bucket 1:
        //  AC: 500
        //  lckAC: 0
        //  ctargemaTP1: 4.16 => TPAvailableToMint: 828.94

        // realTPtoMint = min(1657.89, 1657.89 + 828.94)
        await assertTPAvailableToMint(bucket0, tp1, "1657.894736842105263506");
        // realTPtoMint = min(828.94, 1657.89 + 828.94)
        await assertTPAvailableToMint(bucket1, tp1, "828.947368421052631753");
      });
      describe("WHEN tries to mint 51746 TP 0 + 1 on bucket 0", () => {
        it("THEN Operations fails as there is not enough TP to mint, and Operation Error event is emitted", async () => {
          await expectFail(
            bucket0,
            mocFunctions[0].mintTP({ from: deployer, tp: tp0.target.toString(), qTP: "51746.074603306471719860" }),
          );
        });
      });
      describe("WHEN mints 51746 TP 0 on bucket 0", () => {
        beforeEach(async () => {
          await mocFunctions[0].mintTP({ from: deployer, tp: tp0.target.toString(), qTP: "51746.074603306471719859" });
        });
        it("THEN there are TP 0 available to mint: 0 on bucket 0 and 25873 on bucket 1", async () => {
          await assertTPAvailableToMint(bucket0, tp0, 0, undefined, 10);
          await assertTPAvailableToMint(bucket1, tp0, "25873.037301653235859929");
        });
        it("THEN buckets are still above its local coverage and the combined one", async () => {
          await verifyCoverage();
        });
      });
      describe("WHEN tries to mint 25873 TP 0 + 1 on bucket 1", () => {
        it("THEN Operations fails as there is not enough TP to mint, and Operation Error event is emitted", async () => {
          await expectFail(
            bucket1,
            mocFunctions[1].mintTP({ from: deployer, tp: tp0.target.toString(), qTP: "25873.037301653235859930" }),
          );
        });
      });
      describe("WHEN mints 25873 TP 0 on bucket 1", () => {
        beforeEach(async () => {
          await mocFunctions[1].mintTP({ from: deployer, tp: tp0.target.toString(), qTP: "25873.037301653235859929" });
        });
        it("THEN there are TP 0 available to mint: 51746 on bucket 0 and 0 on bucket 1", async () => {
          await assertTPAvailableToMint(bucket0, tp0, "51746.074603306471719859");
          await assertTPAvailableToMint(bucket1, tp0, 0, undefined, 200);
        });
        it("THEN buckets are still above its local coverage and the combined one", async () => {
          await verifyCoverage();
        });
        describe("AND mints 51746 TP 0 on bucket 0", () => {
          beforeEach(async () => {
            await mocFunctions[0].mintTP({
              from: deployer,
              tp: tp0.target.toString(),
              qTP: "51746.074603306471719859",
            });
          });
          it("THEN there are not TP 0 available to mint on any bucket", async () => {
            await verifyCoverage();
            await assertTPAvailableToMint(bucket0, tp0, 0, undefined, 10);
            await assertTPAvailableToMint(bucket1, tp0, 0, undefined, 200);
          });
          it("THEN buckets are still above its local coverage and the combined one", async () => {
            await verifyCoverage();
          });
        });
      });
      describe("AND mints 2350 TP 0 on bucket 0 and 23500 TP 0 on bucket 1", () => {
        beforeEach(async () => {
          await mocFunctions[0].mintTP({ tp: tp0.target.toString(), from: deployer, qTP: 2350 });
          await mocFunctions[1].mintTP({ tp: tp0.target.toString(), from: deployer, qTP: 23500 });
        });
        it("THEN there are TP 0 available to mint: 49396 on bucket 0 and 2373 on bucket 1", async () => {
          // bucket 0:
          //  AC: 1010
          //  lckAC: 10
          // ctargemaTP0: 5.54 => TPAvailableToMint: 49396.07

          // bucket 1:
          //  AC: 600
          //  lckAC: 100
          //  ctargemaTP0: 5.54 => TPAvailableToMint: 2373.03

          // realTPtoMint = min(49396.07, 49396.07 + 2373.03)
          await assertTPAvailableToMint(bucket0, tp0, "49396.074603306471719859");
          // realTPtoMint = min(2373.03, 49396.07 + 2373.03)
          await assertTPAvailableToMint(bucket1, tp0, "2373.037301653235859929");
        });
        it("THEN there are TP 1 available to mint: 1582 on bucket 0 and 76 on bucket 1", async () => {
          // bucket 0:
          //  AC: 1010
          //  lckAC: 10
          // ctargemaTP1: 4.16 => TPAvailableToMint: 1582.60

          // bucket 1:
          //  AC: 600
          //  lckAC: 100
          //  ctargemaTP1: 4.16 => TPAvailableToMint: 76.02

          // realTPtoMint = min(1582.60, 1582.60 + 76.02)
          await assertTPAvailableToMint(bucket0, tp1, "1582.602984541149138044");
          // realTPtoMint = min(76.02, 1582.60 + 76.02)
          await assertTPAvailableToMint(bucket1, tp1, "76.029845411491377126");
        });
        describe("WHEN TP0 price goes to 150 on bucket 1", () => {
          beforeEach(async () => {
            await bucket1.priceProviders[tp0.target.toString()].poke(pEth(150));
          });
          it("THEN there are TP 0 available to mint: 42521 on bucket 0 and 0 on bucket 1", async () => {
            // bucket 0:
            //  AC: 1010
            //  lckAC: 10
            // ctargemaTP0: 5.54 => TPAvailableToMint: 49396.07

            // bucket 1:
            //  AC: 600
            //  lckAC: 156.66
            //  ctargemaTP0: 5 => TPAvailableToMint: -6875

            // realTPtoMint = min(49396.07, 49396.07 - 6875)
            await assertTPAvailableToMint(bucket0, tp0, "42521.074603306471719984");
            // realTPtoMint = min(0, 49396.07 - 6875)
            await assertTPAvailableToMint(bucket1, tp0, 0);
          });
        });
        describe("WHEN TP0 price goes to 300 on bucket 1", () => {
          beforeEach(async () => {
            await bucket1.priceProviders[tp0.target.toString()].poke(pEth(300));
          });
          it("THEN there are TP 0 available to mint: 47768 on bucket 0 and 0 on bucket 1", async () => {
            // bucket 0:
            //  AC: 1010
            //  lckAC: 10
            // ctargemaTP0: 5.54 => TPAvailableToMint: 49396.07

            // bucket 1:
            //  AC: 600
            //  lckAC: 78.33
            //  nACgain: 2.16
            //  ctargemaTP0: 7.07 => TPAvailableToMint: -1627.08

            // realTPtoMint = min(49396.07, 49396.07 - 1627.08)
            await assertTPAvailableToMint(bucket0, tp0, "47768.985252705521382361");
            // realTPtoMint = min(0, 49396.07 - 1627.08)
            await assertTPAvailableToMint(bucket1, tp0, 0);
          });
        });
        describe("AND mints 525 TP 1 on bucket 0 and bucket 1", () => {
          beforeEach(async () => {
            await mocFunctions[0].mintTP({ tp: tp1.target.toString(), from: deployer, qTP: 525 });
            await mocFunctions[1].mintTP({ tp: tp1.target.toString(), from: deployer, qTP: 52.5 });
          });
          it("THEN there are TP 0 available to mint: 33009 on bucket 0 and 734 on bucket 1", async () => {
            // bucket 0:
            //  AC: 1110
            //  lckAC: 110
            // ctargemaTP0: 5.54 => TPAvailableToMint: 33009.81

            // bucket 1:
            //  AC: 610
            //  lckAC: 110
            //  ctargemaTP0: 5.54 => TPAvailableToMint: 734.41

            // realTPtoMint = min(33009.81, 33009.81 + 734.41)
            assertPrec(
              await mocMultiCollateralGuard.getRealTPAvailableToMint(
                bucket0.mocImpl.target.toString(),
                tp0.target.toString(),
              ),
              "33009.817645592755683344",
            );
            // realTPtoMint = min(734.41, 33009.81 + 734.41)
            assertPrec(
              await mocMultiCollateralGuard.getRealTPAvailableToMint(
                bucket1.mocImpl.target.toString(),
                tp0.target.toString(),
              ),
              "734.411605881864256847",
            );
          });
          it("THEN there are TP 1 available to mint: 1057 on bucket 0 and 23 on bucket 1", async () => {
            // bucket 0:
            //  AC: 1110
            //  lckAC: 110
            // ctargemaTP1: 4.16 => TPAvailableToMint: 1057.60

            // bucket 1:
            //  AC: 610
            //  lckAC: 110
            //  ctargemaTP1: 4.16 => TPAvailableToMint: 23.52

            // realTPtoMint = min(1057.60, 1057.60 + 23.52)
            await assertTPAvailableToMint(bucket0, tp1, "1057.602984541149138193");
            // realTPtoMint = min(23.52, 1057.60 + 23.52)
            await assertTPAvailableToMint(bucket1, tp1, "23.529845411491377159");
          });
          describe("WHEN TP1 price goes to 1 on bucket 1", () => {
            beforeEach(async () => {
              await bucket1.priceProviders[tp1.target.toString()].poke(pEth(1));
            });
            it("THEN there are TP 1 available to mint: 33009 on bucket 0 and 0 on bucket 1", async () => {
              // bucket 0:
              //  AC: 1110
              //  lckAC: 110
              // ctargemaTP0: 5.54 => TPAvailableToMint: 33009.81

              // bucket 1:
              //  AC: 600
              //  lckAC: 525
              //  ctargemaTP0: 5.54 => TPAvailableToMint: -7976.17

              // realTPtoMint = min(33009.81, 33009.81 - 7976.17)
              await assertTPAvailableToMint(bucket0, tp0, "25033.640026584697203442");
              // realTPtoMint = min(0, 33009.81 - 7976.17)
              await assertTPAvailableToMint(bucket1, tp0, 0);
            });
            it("THEN there are TP 1 available to mint: 1006 on bucket 0 and 0 on bucket 1", async () => {
              // bucket 0:
              //  AC: 1110
              //  lckAC: 110
              // ctargemaTP1: 4.16 => TPAvailableToMint: 1057.60

              // bucket 1:
              //  AC: 600
              //  lckAC: 525
              //  ctargemaTP1: 4 => TPAvailableToMint: -51.38

              // realTPtoMint = min(1057.60, 1057.60 - 51.38)
              await assertTPAvailableToMint(bucket0, tp1, "1006.222741819650050020");
              // realTPtoMint = min(0, 1057.60 - 51.38)
              await assertTPAvailableToMint(bucket1, tp1, 0);
            });
            describe("WHEN TP1 is updated to 2, being 30.57 TP1 available on bucket 0 and -51.38 on bucket 1", () => {
              beforeEach(async () => {
                await bucket0.priceProviders[tp1.target.toString()].poke(pEth(2));
              });
              it("THEN there are not TP1 available to mint on any bucket because bucket 1 limits bucket 0", async () => {
                // bucket 0:
                //  AC: 1110
                //  lckAC: 272.5
                // ctargemaTP1: 4 => TPAvailableToMint: 30.57

                // bucket 1:
                //  AC: 600
                //  lckAC: 525
                //  ctargemaTP1: 4 => TPAvailableToMint: -51.38

                // realTPtoMint = min(30.57, 30.57 - 51.38)
                await assertTPAvailableToMint(bucket0, tp1, 0);
                // realTPtoMint = min(0, 30.57 - 51.38)
                await assertTPAvailableToMint(bucket1, tp1, 0);
              });
            });
            describe("WHEN TP1 is updated to 1, being -348 TP1 available on bucket 0 and -500 on bucket 1", () => {
              beforeEach(async () => {
                await bucket0.priceProviders[tp1.target.toString()].poke(pEth(1));
              });
              it("THEN there are not TP1 available to mint on any bucket", async () => {
                // bucket 0:
                //  AC: 1110
                //  lckAC: 535
                // ctargemaTP1: 4 => TPAvailableToMint: -348.47

                // bucket 1:
                //  AC: 600
                //  lckAC: 525
                //  ctargemaTP1: 4 => TPAvailableToMint: -500

                // realTPtoMint = min(0, -348.47 - 500)
                await assertTPAvailableToMint(bucket0, tp1, 0);
                // realTPtoMint = min(0, 1057.60 - 500)
                await assertTPAvailableToMint(bucket1, tp1, 0);
              });
            });
          });
          describe("WHEN TP0 price is updated on bucket 0 causing the combined coverage to drop extremely", () => {
            beforeEach(async () => {
              await bucket0.priceProviders[tp0.target.toString()].poke(1000);
            });
            it("THEN there not TP available to mint on any bucket", async () => {
              await assertTPAvailableToMint(bucket0, tp0, 0);
              await assertTPAvailableToMint(bucket0, tp1, 0);
              await assertTPAvailableToMint(bucket1, tp0, 0);
              await assertTPAvailableToMint(bucket1, tp1, 0);
            });
          });
        });
      });
    });
  });
});
