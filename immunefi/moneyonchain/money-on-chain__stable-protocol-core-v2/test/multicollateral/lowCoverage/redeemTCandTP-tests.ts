import { expect } from "chai";
import { getNamedAccounts } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { Address } from "hardhat-deploy/types";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { Balance, pEth, timedDescribe } from "../../helpers/utils";
import { MocMultiCollateralGuard } from "../../../typechain";
import { fixtureCase2 } from "../fixture";
import { assertPrec } from "../../helpers/assertHelper";

timedDescribe("Feature: multicollateral low coverage joint redeem TC and TP operation", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let alice: Address;
  let tpBalanceBefore: Balance;
  let cglbRelationBefore: Balance;

  let getCglbRelation: () => Promise<Balance>;

  describe("SCENARIO: bucket 0 below combined coverage and bucket 1 above it", function () {
    async function baseSetup() {
      ({ alice } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixtureCase2);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      getCglbRelation = async () => {
        const cglb = (await mocMultiCollateralGuard.getCombinedCglb()) - pEth(1);
        const ctargema = (await mocMultiCollateralGuard.getCombinedCtargemaCA()) - pEth(1);
        return (cglb * pEth(1)) / ctargema;
      };
    }
    describe("GIVEN 2 Moc implementations deployed with TCs and TPs ", function () {
      async function aliceHasTCAndTPSetup() {
        await loadFixture(baseSetup);
        // add collateral
        await Promise.all([
          mocFunctions[0].mintTC({ from: alice, qTC: 1000, execute: false }),
          mocFunctions[1].mintTC({ from: alice, qTC: 1000, execute: false }),
        ]);

        // add TPs
        await Promise.all([
          mocFunctions[0].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 47000, execute: false }),
          mocFunctions[1].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500, execute: false }),
          mocFunctions[0].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 52.5, execute: false }),
          mocFunctions[1].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 52.5, execute: false }),
        ]);
        await mocFunctions[0].executeQueue();
      }
      describe("WHEN TPs prices fall on bucket 0 making combined coverage go below the target", function () {
        async function B0TP0RevaluesSetup() {
          await loadFixture(aliceHasTCAndTPSetup);
          await buckets[0].priceProviders[tps[0].target.toString()].poke(pEth(100));
          await buckets[0].priceProviders[tps[1].target.toString()].poke(pEth(4));
          cglbRelationBefore = await getCglbRelation();
          // verify that coverage is below the bucket0 target and is not operable
          expect(await mocMultiCollateralGuard.getCombinedCglb()).to.be.lessThan(
            await buckets[0].mocImpl.getCtargemaCA(),
          );
        }
        describe("AND a redeemTCandTP operation is done on bucket 0 for TP0", function () {
          before(async function () {
            await loadFixture(B0TP0RevaluesSetup);
            tpBalanceBefore = await tps[0].balanceOf(alice);
            await mocFunctions[0].redeemTCandTP({ tp: tps[0], from: alice, qTC: 1000, qTP: 47000 });
            // verify that operation succeeds
            expect(tpBalanceBefore).to.be.gt(await tps[0].balanceOf(alice));
          });
          it("THEN combined coverage is still above combined ctargema", async function () {
            expect(await mocMultiCollateralGuard.getCombinedCglb()).to.be.greaterThanOrEqual(
              await mocMultiCollateralGuard.getCombinedCtargemaCA(),
            );
          });
          it("THEN relation between combined coverage and combined ctargemaCA remains the same", async function () {
            assertPrec(cglbRelationBefore, await getCglbRelation(), undefined, 1);
          });
        });
        describe("AND a redeemTCandTP operation is done on bucket 0 for TP1", function () {
          before(async function () {
            await loadFixture(B0TP0RevaluesSetup);
            tpBalanceBefore = await tps[1].balanceOf(alice);
            await mocFunctions[0].redeemTCandTP({ tp: tps[1], from: alice, qTC: "58.275246667734104300", qTP: 52.5 });
            // verify that operation succeeds
            expect(tpBalanceBefore).to.be.gt(await tps[1].balanceOf(alice));
          });
          it("THEN combined coverage is still above combined ctargema", async function () {
            expect(await mocMultiCollateralGuard.getCombinedCglb()).to.be.greaterThanOrEqual(
              await mocMultiCollateralGuard.getCombinedCtargemaCA(),
            );
          });
          it("THEN relation between combined coverage and combined ctargemaCA remains the same", async function () {
            assertPrec(cglbRelationBefore, await getCglbRelation(), undefined, 1);
          });
        });
        describe("AND a redeemTCandTP operation is done on bucket 1 for max amount of TP0", function () {
          before(async function () {
            await loadFixture(B0TP0RevaluesSetup);
            tpBalanceBefore = await tps[0].balanceOf(alice);
            await mocFunctions[1].redeemTCandTP({ tp: tps[0], from: alice, qTC: "190.488677221936566700", qTP: 23500 });
            // verify that operation succeeds
            expect(tpBalanceBefore).to.be.gt(await tps[0].balanceOf(alice));
          });
          it("THEN combined coverage is still above combined ctargema", async function () {
            expect(await mocMultiCollateralGuard.getCombinedCglb()).to.be.greaterThanOrEqual(
              await mocMultiCollateralGuard.getCombinedCtargemaCA(),
            );
          });
          it("THEN relation between combined coverage and combined ctargemaCA remains the same", async function () {
            assertPrec(cglbRelationBefore, await getCglbRelation(), undefined, 1);
          });
        });
        describe("AND a redeemTCandTP operation is done on bucket 1 for max amount of TP1", function () {
          before(async function () {
            await loadFixture(B0TP0RevaluesSetup);
            tpBalanceBefore = await tps[1].balanceOf(alice);
            await mocFunctions[1].redeemTCandTP({ tp: tps[1], from: alice, qTC: "78.890500594743110810", qTP: 52.5 });
            // verify that operation succeeds
            expect(tpBalanceBefore).to.be.gt(await tps[1].balanceOf(alice));
          });
          it("THEN combined coverage is still above combined ctargema", async function () {
            expect(await mocMultiCollateralGuard.getCombinedCglb()).to.be.greaterThanOrEqual(
              await mocMultiCollateralGuard.getCombinedCtargemaCA(),
            );
          });
          it("THEN relation between combined coverage and combined ctargemaCA remains the same", async function () {
            assertPrec(cglbRelationBefore, await getCglbRelation(), undefined, 1);
          });
        });
        describe("WHEN TP0 price falls on bucket 1 making combined coverage below the target", function () {
          async function B1TP0RevaluesSetup() {
            await loadFixture(B0TP0RevaluesSetup);
            await buckets[1].priceProviders[tps[0].target.toString()].poke(pEth(50));
            cglbRelationBefore = await getCglbRelation();
          }
          describe("AND a redeemTCandTP operation is done on bucket 0 for max amount of TP0", function () {
            before(async function () {
              await loadFixture(B1TP0RevaluesSetup);
              tpBalanceBefore = await tps[0].balanceOf(alice);
              await mocFunctions[0].redeemTCandTP({
                tp: tps[0],
                from: alice,
                qTC: "639.431244671821756560",
                qTP: 23500,
              });
              // verify that operation succeeds
              expect(tpBalanceBefore).to.be.gt(await tps[0].balanceOf(alice));
            });
            it("THEN relation between combined coverage and combined ctargemaCA remains the same", async function () {
              assertPrec(cglbRelationBefore, await getCglbRelation(), undefined, 1);
            });
          });
          describe("AND a redeemTCandTP operation is done on bucket 0 for max amount of TP1", function () {
            before(async function () {
              await loadFixture(B1TP0RevaluesSetup);
              tpBalanceBefore = await tps[1].balanceOf(alice);
              await mocFunctions[0].redeemTCandTP({
                tp: tps[1],
                from: alice,
                qTC: "26.784686445694661000",
                qTP: 52.5,
              });
              // verify that operation succeeds
              expect(tpBalanceBefore).to.be.gt(await tps[1].balanceOf(alice));
            });
            it("THEN relation between combined coverage and combined ctargemaCA remains the same", async function () {
              assertPrec(cglbRelationBefore, await getCglbRelation(), undefined, 1);
            });
          });
          describe("AND a redeemTCandTP operation is done on bucket 1 for max amount of TP0", function () {
            before(async function () {
              await loadFixture(B1TP0RevaluesSetup);
              tpBalanceBefore = await tps[0].balanceOf(alice);
              await mocFunctions[1].redeemTCandTP({
                tp: tps[0],
                from: alice,
                qTC: "553.317364250988617770",
                qTP: 23500,
              });
              // verify that operation succeeds
              expect(tpBalanceBefore).to.be.gt(await tps[0].balanceOf(alice));
            });
            it("THEN relation between combined coverage and combined ctargemaCA remains the same", async function () {
              assertPrec(cglbRelationBefore, await getCglbRelation(), undefined, 1);
            });
          });
          describe("AND a redeemTCandTP operation is done on bucket 1 for max amount of TP1", function () {
            before(async function () {
              await loadFixture(B1TP0RevaluesSetup);
              tpBalanceBefore = await tps[1].balanceOf(alice);
              await mocFunctions[1].redeemTCandTP({ tp: tps[1], from: alice, qTC: "57.555470513105199050", qTP: 52.5 });
              // verify that operation succeeds
              expect(tpBalanceBefore).to.be.gt(await tps[1].balanceOf(alice));
            });
            it("THEN relation between combined coverage and combined ctargemaCA remains the same", async function () {
              assertPrec(cglbRelationBefore, await getCglbRelation());
            });
          });
        });
      });
    });
  });
});
