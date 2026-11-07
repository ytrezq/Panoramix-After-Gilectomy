import { expect } from "chai";
import { getNamedAccounts } from "hardhat";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { ERROR_SELECTOR, timedDescribe, tpParams } from "../helpers/utils";
import { MocMultiCollateralGuard } from "../../typechain";
import { fixtureDeployedMulticollateral } from "../multicollateral/fixture";
import { assertPrec } from "../helpers/assertHelper";

timedDescribe("Feature: multicollateral invalid prices handle error", () => {
  let mocFunctions = new Array<any>(2);
  let buckets = new Array<any>(2);
  let tps = new Array<any>(2);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let from: Address;
  let alice: Address;
  let tp0: Address;
  let tp1: Address;
  let mocCore0: Address;
  const execute = false;

  describe("GIVEN 2 Moc implementations deployed", function () {
    async function fixture() {
      return fixtureDeployedMulticollateral(2, tpParams);
    }
    before(async () => {
      ({ alice } = await getNamedAccounts());
      from = alice;
      const mocContracts = await loadFixture(fixture);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      tp0 = tps[0].target.toString();
      tp1 = tps[1].target.toString();
      mocCore0 = buckets[0].mocImpl.target.toString();

      await Promise.all([
        // add collateral
        await mocFunctions[0].mintTC({ from, qTC: 1500, execute }),
        await mocFunctions[1].mintTC({ from, qTC: 1500, execute }),
        // add TPs
        await mocFunctions[0].mintTP({ from, tp: tp1, qTP: 525, execute }),
        await mocFunctions[1].mintTP({ from, tp: tp0, qTP: 23500, execute }),
      ]);

      await mocMultiCollateralGuard.execute();
    });
    describe("WHEN TP 1 has no valid prices on bucket 1", () => {
      const expectMissingProviderEvent = async () => {
        const tx = await mocMultiCollateralGuard.execute();
        await expect(tx)
          .to.emit(buckets[0].mocQueue, "UnhandledError")
          .withArgs(
            anyValue,
            ERROR_SELECTOR.MISSING_PROVIDER_PRICE +
              "0".repeat(24) +
              buckets[1].priceProviders[tp1].target.toString().toLowerCase().slice(2),
          );
        // funds are returned
        assertPrec(await buckets[0].mocImpl.qACLockedInPending(), 0);
        assertPrec(await mocFunctions[0].tcBalanceOf(mocCore0), 0);
        assertPrec(await mocFunctions[0].tpBalanceOf(0, mocCore0), 0);
      };

      before(async () => {
        await buckets[1].priceProviders[tp1].deprecatePriceProvider();
      });
      describe("AND a redeemTC operation is executed on bucket 0", () => {
        it("THEN a Unhandled Error event is emitted and funds returned", async () => {
          await mocFunctions[0].redeemTC({ from, qTC: 10, execute });
          await expectMissingProviderEvent();
        });
      });
      describe("AND a mintTP operation is executed on bucket 0", () => {
        it("THEN a Unhandled Error event is emitted and funds returned", async () => {
          await mocFunctions[0].mintTP({ from, tp: tp0, qTP: 10, execute });
          await expectMissingProviderEvent();
        });
      });
      describe("AND a redeemTCandTP operation is executed on bucket 0", () => {
        it("THEN a Unhandled Error event is emitted and funds returned", async () => {
          await mocFunctions[0].redeemTCandTP({ from, qTC: 1, qTP: 1, execute });
          await expectMissingProviderEvent();
        });
      });
      describe("AND a swapTCforTP operation is executed on bucket 0", () => {
        it("THEN a Unhandled Error event is emitted and funds returned", async () => {
          await mocFunctions[0].swapTCforTP({ from, qTC: 1, execute });
          await expectMissingProviderEvent();
        });
      });
      describe("AND a swapTPforTP operation is executed on bucket 0", () => {
        it("THEN a Unhandled Error event is emitted and funds returned", async () => {
          await mocFunctions[0].swapTPforTP({ iFrom: 1, iTo: 0, from, qTP: 1, execute });
          await expectMissingProviderEvent();
        });
      });
    });
  });
});
