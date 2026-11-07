import { expect } from "chai";
import { getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { ERRORS, pEth, timedDescribe } from "../../helpers/utils";
import { MocMultiCollateralGuard } from "../../../typechain";
import { fixtureLiquidation } from "../fixture";
import { addSwappers } from "./utils";

timedDescribe("Feature: multicollateral liquidate validations", () => {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let from: Address;
  let alice: Address;
  let tp0: Address;
  let tp1: Address;
  let mocCore0: Address;
  let mocCore1: Address;
  const execute = false;

  describe("GIVEN 3 Moc implementations deployed", function () {
    before(async () => {
      ({ alice } = await getNamedAccounts());
      from = alice;
      const mocContracts = await loadFixture(fixtureLiquidation);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });
      tp0 = tps[0].target.toString();
      tp1 = tps[1].target.toString();
      mocCore0 = buckets[0].mocImpl.target.toString();
      mocCore1 = buckets[1].mocImpl.target.toString();

      await Promise.all([
        // add collateral
        await mocFunctions[0].mintTC({ from, qTC: 1500, execute }),
        await mocFunctions[1].mintTC({ from, qTC: 1500, execute }),
        await mocFunctions[2].mintTC({ from, qTC: 1500, execute }),
      ]);
      await Promise.all([
        // add TPs
        await mocFunctions[0].mintTP({ from, tp: tp0, qTP: 23500, execute }),
        await mocFunctions[1].mintTP({ from, tp: tp0, qTP: 23500, execute }),
        await mocFunctions[2].mintTP({ from, tp: tp0, qTP: 23500, execute }),
      ]);

      await mocMultiCollateralGuard.execute();

      await addSwappers(mocMultiCollateralGuard, buckets);

      // enable liquidation
      await buckets[0].mocImpl.setLiqEnabled(true);
    });
    describe("WHEN MocCore setLiquidated functions caller is not MultiCollateralGuard", () => {
      it("THEN tx reverts because caller is not MultiCollateralGuard", async () => {
        await expect(buckets[0].mocImpl.setLiquidated()).to.be.revertedWithCustomError(
          buckets[0].mocImpl,
          ERRORS.ONLY_MULTICOLLATERALGUARD,
        );
      });
    });
    describe("WHEN trying to evaluate liquidation on a bucket that has not been set", () => {
      it("THEN tx reverts because bucket does not exist", async () => {
        await expect(mocMultiCollateralGuard.execLiquidation(alice)).to.be.revertedWithCustomError(
          mocMultiCollateralGuard,
          ERRORS.BUCKET_DOES_NOT_EXIST,
        );
      });
    });
    describe("WHEN trying to evaluate liquidation", () => {
      it("THEN tx reverts because liquidation threshold is not reached", async () => {
        await expect(mocMultiCollateralGuard.execLiquidation(mocCore0)).to.be.revertedWithCustomError(
          mocMultiCollateralGuard,
          ERRORS.LIQUIDATION_NOT_AVAILABLE,
        );
      });
    });
    describe("WHEN executeLiquidatedBucket is called for bucket 0", () => {
      it("THEN tx reverts because bucket is not liquidated", async () => {
        await expect(mocMultiCollateralGuard.executeLiquidatedBucket(mocCore0)).to.be.revertedWithCustomError(
          mocMultiCollateralGuard,
          ERRORS.BUCKET_NOT_LIQUIDATED,
        );
      });
    });
    describe("WHEN bucket 1 AC price falls", function () {
      before(async () => {
        await Promise.all([
          buckets[1].priceProviders[tp0].poke(pEth(0.1)),
          buckets[1].priceProviders[tp1].poke(pEth(0.1)),
        ]);
      });
      it("THEN bucket is below the liquidation threshold", async () => {
        expect(await buckets[1].mocImpl.getCglb()).to.be.lessThan(await buckets[1].mocImpl.liqThrld());
      });
      describe("WHEN trying to evaluate liquidation", () => {
        it("THEN tx reverts because liquidation is not enabled in bucket 1", async () => {
          await expect(mocMultiCollateralGuard.execLiquidation(mocCore1)).to.be.revertedWithCustomError(
            mocMultiCollateralGuard,
            ERRORS.LIQUIDATION_NOT_AVAILABLE,
          );
        });
      });
    });
  });
});
