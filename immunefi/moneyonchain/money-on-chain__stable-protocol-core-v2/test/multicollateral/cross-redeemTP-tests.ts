import { getNamedAccounts } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { Address } from "hardhat-deploy/types";
import { assertPrec } from "../helpers/assertHelper";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { CONSTANTS, timedDescribe, tpParams } from "../helpers/utils";
import { fixtureDeployedMulticollateral } from "./fixture";

timedDescribe("Feature: multicollateral redeem Pegged Tokens between different buckets", function () {
  let mocFunctions = new Array<any>(2);
  let buckets = new Array<any>(2);
  let tps = new Array<any>(2);
  let alice: Address;
  let bob: Address;

  describe("GIVEN 2 Moc implementations deployed", function () {
    async function fixture() {
      return fixtureDeployedMulticollateral(2, tpParams);
    }
    before(async function () {
      ({ alice, bob } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixture);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });

      // add collateral to every buckets
      await Promise.all(mocFunctions.map(fncs => fncs.mintTC({ from: alice, qTC: 100000, execute: true })));
    });
    describe("AND alice mints 23500 TP0 on bucket 0 and bob mints 2350 TP0 on bucket 1", function () {
      before(async function () {
        await Promise.all([
          mocFunctions[0].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500, execute: false }), // 100 AC0
          mocFunctions[1].mintTP({ tp: tps[0].target.toString(), from: bob, qTP: 2350, execute: false }), // 10 AC1
        ]);
        await mocFunctions[0].executeQueue();
      });
      describe("WHEN alice tries to redeem 2351 TP0 on bucket 1", function () {
        it("THEN the operation failed", async function () {
          await mocFunctions[1].redeemTP({ tp: tps[0], from: alice, qTP: 2351, execute: true });
          assertPrec(await tps[0].balanceOf(alice), 23500);
        });
      });
      describe("WHEN alice redeems 2350 TP0 on bucket 1", function () {
        it("THEN the operation succeeded and bucket 1 has no more TP0 available", async function () {
          await mocFunctions[1].redeemTP({ tp: tps[0], from: alice, qTP: 2350, execute: true });
          assertPrec(await tps[0].balanceOf(alice), 23500 - 2350);
          assertPrec(await buckets[1].mocImpl.getCglb(), CONSTANTS.MAX_UINT256);
          assertPrec(await buckets[1].mocImpl.getLckAC(), 0);
        });
        describe("AND bob tries to redeem 1 TP0 on bucket 1", function () {
          it("THEN the operation failed", async function () {
            await mocFunctions[1].redeemTP({ tp: tps[0], from: bob, qTP: 1, execute: true });
            assertPrec(await tps[0].balanceOf(bob), 2350);
          });
        });
        describe("WHEN bob redeems 2350 TP0 on bucket 0", function () {
          it("THEN the operation succeeded and bob has no more TP0", async function () {
            await mocFunctions[0].redeemTP({ tp: tps[0], from: bob, qTP: 2350, execute: true });
            assertPrec(await tps[0].balanceOf(bob), 0);
          });
          describe("WHEN alice redeems all the TP0 on bucket 0", function () {
            it("THEN the operation succeeded and both buckets are empty", async function () {
              await mocFunctions[0].redeemTP({ tp: tps[0], from: alice, qTP: 23500 - 2350, execute: true });
              assertPrec(await tps[0].balanceOf(alice), 0);
              assertPrec(await tps[0].balanceOf(bob), 0);
              assertPrec(await buckets[0].mocImpl.getCglb(), CONSTANTS.MAX_UINT256);
              assertPrec(await buckets[0].mocImpl.getLckAC(), 0);
              assertPrec(await buckets[1].mocImpl.getCglb(), CONSTANTS.MAX_UINT256);
              assertPrec(await buckets[1].mocImpl.getLckAC(), 0);
            });
          });
        });
      });
    });
  });
});
