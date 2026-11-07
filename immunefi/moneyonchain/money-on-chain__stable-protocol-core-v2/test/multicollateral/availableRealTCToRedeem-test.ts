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

timedDescribe("Feature: multicollateral real TC available to redeem", function () {
  let mocFunctions = new Array<any>(2);
  let bucket0: any;
  let bucket1: any;
  let deployer: Address;
  let tp0: MocRC20;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let verifyCoverage: () => Promise<void>;
  let assertTCAvailableToRedeem = async (bucket: any, expectedValue: any, message?: string, tolerance?: number) =>
    assertPrec(
      await mocMultiCollateralGuard.getRealTCAvailableToRedeem(bucket.mocImpl.target.toString()),
      expectedValue,
      message,
      tolerance,
    );
  let expectFail = async (bucket: any, tx: any) =>
    expect(await tx)
      .to.emit(bucket.mocQueue, "OperationError")
      .withArgs(
        (await bucket.mocQueue.operIdCount()) - 1n,
        ERROR_SELECTOR.INSUFFICIENT_TC_TO_REDEEM,
        "Insufficient tc to redeem",
      );

  describe("GIVEN 2 Moc implementations deployed with 3 TPs added on every buckets", function () {
    async function fixture() {
      return fixtureDeployedMulticollateral(1, tpParams);
    }
    beforeEach(async function () {
      ({ deployer } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixture);
      ({
        mocBucketContracts: [bucket0, bucket1],
        mocMultiCollateralGuard,
        mocPeggedTokens: [tp0],
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
      it("THEN all the TC are available to redeem", async () => {
        await assertTCAvailableToRedeem(bucket0, 1000);
        await assertTCAvailableToRedeem(bucket1, 500);
      });
      describe("AND mints 2350 TP 0 on bucket 0", () => {
        beforeEach(async () => {
          await mocFunctions[0].mintTP({ tp: tp0.target.toString(), from: deployer, qTP: 2350 });
        });
        it("THEN there are TC are available to redeem: 954.58 on bucket 0 and 500 on bucket 1", async () => {
          // bucket 0:
          //  AC: 1010
          //  lckAC: 10
          //  pTCac: 1
          // ctargEma: 5.54 => TCAvailableToRedeem: 954.58

          // bucket 1:
          //  AC: 500
          //  pTCac: 1
          //  lckAC: 0 => TCAvailableToRedeem: 500

          // nf1 : 1
          // realTCtoRedeemOnCA = (954.58*1) + (500*1*1) = 1454.58

          // realTCtoRedeem = min(1454.58/1, 954.58)
          await assertTCAvailableToRedeem(bucket0, "954.585927183550273540");
          // realTCtoRedeem = min(1454.58/1*1, 500)
          await assertTCAvailableToRedeem(bucket1, 500);
        });
        describe("AND mints 23500 TP 0 on bucket 1", () => {
          beforeEach(async () => {
            await mocFunctions[1].mintTP({ tp: tp0.target.toString(), from: deployer, qTP: 23500 });
          });
          it("THEN there are TC are available to redeem: 954.58 on bucket 0 and 45.85 on bucket 1", async () => {
            // bucket 0:
            //  AC: 1010
            //  lckAC: 10
            //  pTCac: 1
            // ctargEma: 5.54 => TCAvailableToRedeem: 954.58

            // bucket 1:
            //  AC: 600
            //  pTCac: 1
            //  lckAC: 100
            //  ctargEma: 5.54 => TCAvailableToRedeem: 45.85

            // nf1 : 1
            // realTCtoRedeemOnCA = (954.58*1) + (45.85*1*1) = 1000.44

            // realTCtoRedeem = min(1000.44/1, 954.58)
            await assertTCAvailableToRedeem(bucket0, "954.585927183550273540");
            // realTCtoRedeem = min(1000.44/1*1, 45.85)
            await assertTCAvailableToRedeem(bucket1, "45.859271835502735400");
          });
          describe("WHEN TP0 price goes to 150 on bucket 1", () => {
            beforeEach(async () => {
              await bucket1.priceProviders[tp0.target.toString()].poke(pEth(150));
            });
            it("THEN there are TC are available to redeem: 837.56 on bucket 0 and 0 on bucket 1", async () => {
              // bucket 0:
              //  AC: 1010
              //  lckAC: 10
              //  pTCac: 1
              // ctargEma: 5.54 => TCAvailableToRedeem: 954.58

              // bucket 1:
              //  AC: 600
              //  pTCac: 0.88
              //  lckAC: 156.66
              //  ctargEma: 5 => TCAvailableToRedeem: -206.76

              // nf1 : 0.638
              // realTCtoRedeemOnCA = (954.58*1) + (-206.76*0.638*0.88) = 837.56

              // realTCtoRedeem = min(837.56/1, 954.58)
              await assertTCAvailableToRedeem(bucket0, "837.564650587805592858");
              // realTCtoRedeem = min(837.56/0.88*1.566, -206.76)
              await assertTCAvailableToRedeem(bucket1, 0);
            });
            it("THEN combined ctargemaCA is still above the combined coverage", async () => {
              expect(await mocMultiCollateralGuard.getCombinedCglb()).be.greaterThanOrEqual(
                await mocMultiCollateralGuard.getCombinedCtargemaCA(),
              );
            });
          });
          describe("WHEN TP0 price goes to 300 on bucket 1", () => {
            beforeEach(async () => {
              await bucket1.priceProviders[tp0.target.toString()].poke(pEth(300));
            });
            it("THEN there are TC are available to redeem: 912.52 on bucket 0 and 0 on bucket 1", async () => {
              // bucket 0:
              //  AC: 1010
              //  lckAC: 10
              //  pTCac: 1
              // ctargEma: 5.54 => TCAvailableToRedeem: 954.58

              // bucket 1:
              //  AC: 600
              //  pTCac: 1.017
              //  lckAC: 78.33
              //  nACGain: 2.16
              //  ctargEma: 7.07 => TCAvailableToRedeem: -32.38

              // nf1 : 1.276
              // realTCtoRedeemOnCA = (954.58*1) + (-32.38*1.276*1.017) = 912.52

              // realTCtoRedeem = min(912.52/1, 954.58)
              await assertTCAvailableToRedeem(bucket0, "912.529912059948544538");
              // realTCtoRedeem = min(912.52/1.017*1.276, -32.38)
              await assertTCAvailableToRedeem(bucket1, 0);
            });
            it("THEN combined ctargemaCA is still above the combined coverage", async () => {
              expect(await mocMultiCollateralGuard.getCombinedCglb()).be.greaterThanOrEqual(
                await mocMultiCollateralGuard.getCombinedCtargemaCA(),
              );
            });
          });
          describe("WHEN TP0 is updated being 37 TC available on bucket 0 and -787 on bucket 1", () => {
            beforeEach(async () => {
              await bucket0.priceProviders[tp0.target.toString()].poke(pEth(12));
              await bucket1.priceProviders[tp0.target.toString()].poke(pEth(100));
            });
            it("THEN there are not TC available to redeem on any bucket because bucket 1 limits bucket 0", async () => {
              // bucket 0:
              //  AC: 1010
              //  lckAC: 195.83
              //  pTCac: 0.814
              // ctargEma: 5 => TCAvailableToRedeem: 37.8

              // bucket 1:
              //  AC: 600
              //  pTCac: 0.73
              //  lckAC: 235
              //  ctargEma: 5 => TCAvailableToRedeem: -787.67
              await assertTCAvailableToRedeem(bucket0, 0);
              await assertTCAvailableToRedeem(bucket1, 0);
            });
          });
          describe("WHEN TP0 price goes to 220 on bucket 1", () => {
            beforeEach(async () => {
              await bucket1.priceProviders[tp0.target.toString()].poke(pEth(220));
            });
            it("THEN there are TC are available to redeem: 954.58 on bucket 0 and 46.49 on bucket 1", async () => {
              // bucket 0:
              //  AC: 1010
              //  lckAC: 10
              //  pTCac: 1
              // ctargEma: 5.54 => TCAvailableToRedeem: 954.58

              // bucket 1:
              //  AC: 600
              //  pTCac: 0.98
              //  lckAC: 100
              //  ctargEma: 5.18 => TCAvailableToRedeem: 46.49

              // nf1 : 0.93
              // realTCtoRedeemOnCA = (954.58*1) + (46.49*0.93*0.98) = 996.95

              // realTCtoRedeem = min(996.95/1, 954.58)
              await assertTCAvailableToRedeem(bucket0, "954.585927183550273540");
              // realTCtoRedeem = min(996.95/0.98*0.93, 46.49)
              await assertTCAvailableToRedeem(bucket1, "46.493270985302312412");
            });
            describe("WHEN tries to redeem 954.58 TC + 1 on bucket 0", () => {
              it("THEN Operations fails with Insufficient tc to redeem, and Operation Error event is emitted", async () => {
                await expectFail(
                  bucket0,
                  await mocFunctions[0].redeemTC({ from: deployer, qTC: "954.585927183550273541" }),
                );
              });
            });
            describe("WHEN tries to redeem 46.49 TC + 1 on bucket 1", () => {
              it("THEN Operations fails with Insufficient tc to redeem, and Operation Error event is emitted", async () => {
                await expectFail(
                  bucket1,
                  await mocFunctions[1].redeemTC({ from: deployer, qTC: "46.493270985302312413" }),
                );
              });
            });
            describe("WHEN redeems 954.58 TC on bucket 0", () => {
              beforeEach(async () => {
                await mocFunctions[0].redeemTC({ from: deployer, qTC: "954.585927183550273540" });
              });
              it("THEN there are TC are available to redeem: 0 on bucket 0 and 46.49 on bucket 1", async () => {
                // bucket 0:
                //  AC: 55.41
                //  lckAC: 10
                //  pTCac: 1
                // ctargEma: 5.54 => TCAvailableToRedeem: 0

                // bucket 1:
                //  AC: 600
                //  pTCac: 0.98
                //  lckAC: 100
                //  ctargEma: 5.18 => TCAvailableToRedeem: 46.49

                // nf1 : 1.06
                // realTCtoRedeemOnCA = (0*1) + (46.49*1.06*0.98) = 48.98

                // realTCtoRedeem = min(48.98/1, 0)
                await assertTCAvailableToRedeem(bucket0, 0);
                // realTCtoRedeem = min(48.98/0.98*1.06, 46.49)
                await assertTCAvailableToRedeem(bucket1, "46.493270985302312412");
              });
              it("THEN buckets are still above its local coverage and the combined one", async () => {
                await verifyCoverage();
              });
            });
            describe("WHEN redeems 46.49 TC on bucket 1", () => {
              beforeEach(async () => {
                await mocFunctions[1].redeemTC({ from: deployer, qTC: "46.493270985302312412" });
              });
              it("THEN there are TC are available to redeem: 954.58 on bucket 0 and 0 on bucket 1", async () => {
                // bucket 0:
                //  AC: 1010
                //  lckAC: 10
                //  pTCac: 1
                // ctargEma: 5.54 => TCAvailableToRedeem: 954.58

                // bucket 1:
                //  AC: 554.14
                //  pTCac: 0.98
                //  lckAC: 100
                //  ctargEma: 5.18 => TCAvailableToRedeem: 0

                // nf1 : 1.06
                // realTCtoRedeemOnCA = (954.58*1) + (0*1.06*0.98) = 954.58

                // realTCtoRedeem = min(954.58/1, 954.58)
                await assertTCAvailableToRedeem(bucket0, "954.585927183550273540");
                // realTCtoRedeem = min(954.58/0.98*1.06, 0)
                await assertTCAvailableToRedeem(bucket1, 0, undefined, 1);
              });
              it("THEN buckets are still above its local coverage and the combined one", async () => {
                await verifyCoverage();
              });
              describe("AND redeems 954.58 TC on bucket 0", () => {
                beforeEach(async () => {
                  await mocFunctions[0].redeemTC({ from: deployer, qTC: "954.585927183550273540" });
                });
                it("THEN there are not TC available to redeem on any bucket", async () => {
                  await assertTCAvailableToRedeem(bucket0, 0);
                  await assertTCAvailableToRedeem(bucket1, 0, undefined, 1);
                });
                it("THEN buckets are still above its local coverage and the combined one", async () => {
                  await verifyCoverage();
                });
              });
            });
            describe("WHEN redeems 500 TC on bucket 0", () => {
              beforeEach(async () => {
                await mocFunctions[0].redeemTC({ from: deployer, qTC: 500 });
              });
              it("THEN there are TC are available to redeem: 454.58 on bucket 0 and 46.49 on bucket 1", async () => {
                // bucket 0:
                //  AC: 510
                //  lckAC: 10
                //  pTCac: 1
                // ctargEma: 5.54 => TCAvailableToRedeem: 454.58

                // bucket 1:
                //  AC: 600
                //  pTCac: 0.98
                //  lckAC: 100
                //  ctargEma: 5.18 => TCAvailableToRedeem: 46.49

                // nf1 : 1.06
                // realTCtoRedeemOnCA = (454.58*1) + (46.49*1.06*0.98) = 502.87

                // realTCtoRedeem = min(502.87/1, 454.58)
                await assertTCAvailableToRedeem(bucket0, "454.585927183550273540");
                // realTCtoRedeem = min(502.87/0.98*1.06, 46.49)
                await assertTCAvailableToRedeem(bucket1, "46.493270985302312412");
              });
            });
          });
          describe("WHEN TP0 price is updated on bucket 0 causing the combined coverage to drop extremely", () => {
            beforeEach(async () => {
              await bucket0.priceProviders[tp0.target.toString()].poke(1000);
            });
            it("THEN there not TC available to redeem on any bucket", async () => {
              await assertTCAvailableToRedeem(bucket0, 0);
              await assertTCAvailableToRedeem(bucket1, 0);
            });
          });
        });
      });
    });
  });
});
