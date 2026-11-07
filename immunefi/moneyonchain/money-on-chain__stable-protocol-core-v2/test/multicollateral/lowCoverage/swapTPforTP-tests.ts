import { expect } from "chai";
import { getNamedAccounts } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { Address } from "hardhat-deploy/types";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { Balance, pEth, timedDescribe } from "../../helpers/utils";
import { MocMultiCollateralGuard } from "../../../typechain";
import { fixtureCase2 } from "../fixture";

timedDescribe("Feature: multicollateral swap Pegged Token for another Pegged Token", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let alice: Address;
  let tpBalanceBefore: Balance;
  let combCoverageBefore: Balance;

  describe("SCENARIO: bucket 0 below combined coverage and bucket 1 above it", function () {
    async function baseSetup() {
      ({ alice } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixtureCase2);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
    }
    describe("GIVEN 2 Moc implementations deployed with TCs and TPs ", function () {
      async function aliceHasTCAndTPSetup() {
        await loadFixture(baseSetup);
        // add collateral
        await Promise.all([
          mocFunctions[0].mintTC({ from: alice, qTC: 1000 }),
          mocFunctions[1].mintTC({ from: alice, qTC: 1000 }),
        ]);

        // add TPs
        await Promise.all([
          mocFunctions[0].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 47000 }),
          mocFunctions[1].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500 }),
          mocFunctions[0].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 52.5 }),
          mocFunctions[1].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 52.5 }),
        ]);
      }
      describe("WHEN TPs prices fall on bucket 0 making combined coverage go below the target", function () {
        async function B0TP0RevaluesSetup() {
          await loadFixture(aliceHasTCAndTPSetup);
          await buckets[0].priceProviders[tps[0].target.toString()].poke(pEth(100));
          await buckets[0].priceProviders[tps[1].target.toString()].poke(pEth(4));
          // verify that coverage is below the bucket0 target and is not operable
          expect(await mocMultiCollateralGuard.getCombinedCglb()).to.be.lessThan(
            await buckets[0].mocImpl.getCtargemaCA(),
          );
        }
        describe("AND a swapTPforTP operation is done on bucket 0 for 47000 TP0 to TP1", function () {
          before(async function () {
            await loadFixture(B0TP0RevaluesSetup);
            tpBalanceBefore = await tps[0].balanceOf(alice);
            await mocFunctions[0].swapTPforTP({ tpFrom: tps[0], tpTo: tps[1], from: alice, qTP: 47000 });
            // verify that operation succeeds
            expect(tpBalanceBefore).to.be.gt(await tps[0].balanceOf(alice));
          });
          it("THEN combined coverage is still above combined ctargema", async function () {
            expect(await mocMultiCollateralGuard.getCombinedCglb()).to.be.greaterThanOrEqual(
              await mocMultiCollateralGuard.getCombinedCtargemaCA(),
            );
          });
        });
        describe("AND a swapTPforTP operation is done on bucket 1 for 23500 TP0 to TP1", function () {
          before(async function () {
            await loadFixture(B0TP0RevaluesSetup);
            await mocFunctions[1].swapTPforTP({ tpFrom: tps[0], tpTo: tps[1], from: alice, qTP: 23500 });
          });
          it("THEN operation fails because low coverage", async function () {
            expect(tpBalanceBefore).to.be.equal(await tps[0].balanceOf(alice));
          });
        });
        describe("AND a swapTPforTP operation is done on bucket 0 for 52.5 TP1 to TP0", function () {
          before(async function () {
            await loadFixture(B0TP0RevaluesSetup);
            tpBalanceBefore = await tps[1].balanceOf(alice);
            await mocFunctions[0].swapTPforTP({ tpFrom: tps[1], tpTo: tps[0], from: alice, qTP: 52.5 });
          });
          it("THEN operation fails because low coverage", async function () {
            expect(tpBalanceBefore).to.be.equal(await tps[1].balanceOf(alice));
          });
        });
        describe("AND a swapTPforTP operation is done on bucket 1 for 52.5 TP1 to TP0", function () {
          before(async function () {
            await loadFixture(B0TP0RevaluesSetup);
            tpBalanceBefore = await tps[1].balanceOf(alice);
            await mocFunctions[1].swapTPforTP({ tpFrom: tps[1], tpTo: tps[0], from: alice, qTP: 52.5 });
            // verify that operation succeeds
            expect(tpBalanceBefore).to.be.gt(await tps[1].balanceOf(alice));
          });
          it("THEN combined coverage is still above combined ctargema", async function () {
            expect(await mocMultiCollateralGuard.getCombinedCglb()).to.be.greaterThanOrEqual(
              await mocMultiCollateralGuard.getCombinedCtargemaCA(),
            );
          });
        });
        describe("WHEN TP0 price falls on bucket 1 making combined coverage below the target", function () {
          async function B1TP0RevaluesSetup() {
            await loadFixture(B0TP0RevaluesSetup);
            tpBalanceBefore = await tps[0].balanceOf(alice);
            await buckets[1].priceProviders[tps[0].target.toString()].poke(pEth(50));
            // verify that coverage is below the target and is not operable
            expect(await mocMultiCollateralGuard.getCombinedCglb()).to.be.lessThan(
              await mocMultiCollateralGuard.getCombinedCtargemaCA(),
            );
          }
          describe("AND a swapTPforTP operation is done on bucket 0 for 47000 TP0 for TP1", function () {
            before(async function () {
              await loadFixture(B1TP0RevaluesSetup);
              tpBalanceBefore = await tps[0].balanceOf(alice);
              combCoverageBefore = await mocMultiCollateralGuard.getCombinedCglb();
              await mocFunctions[0].swapTPforTP({ tpFrom: tps[0], tpTo: tps[1], from: alice, qTP: 47000 });
              // verify that operation succeeds
              expect(tpBalanceBefore).to.be.gt(await tps[0].balanceOf(alice));
            });
            it("THEN combined coverage didn't change", async function () {
              expect(combCoverageBefore).to.be.equal(await mocMultiCollateralGuard.getCombinedCglb());
            });
          });
          describe("AND a swapTPforTP operation is done on bucket 1 for 52.5 TP1 to TP0", function () {
            before(async function () {
              await loadFixture(B1TP0RevaluesSetup);
              tpBalanceBefore = await tps[1].balanceOf(alice);
              combCoverageBefore = await mocMultiCollateralGuard.getCombinedCglb();
              await mocFunctions[1].swapTPforTP({ tpFrom: tps[1], tpTo: tps[0], from: alice, qTP: 52.5 });
              // verify that operation succeeds
              expect(tpBalanceBefore).to.be.gt(await tps[1].balanceOf(alice));
            });
            it("THEN combined coverage didn't change", async function () {
              expect(combCoverageBefore).to.be.equal(await mocMultiCollateralGuard.getCombinedCglb());
            });
          });
        });
      });
    });
  });
});
