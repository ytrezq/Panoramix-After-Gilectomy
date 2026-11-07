import { expect } from "chai";
import { getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { CONSTANTS, ERRORS, pEth, timedDescribe } from "../../helpers/utils";
import { MocMultiCollateralGuard } from "../../../typechain";
import { fixtureLiquidation } from "../fixture";
import { addSwappers } from "./utils";

timedDescribe("Feature: multicollateral micro liquidation validations", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let from: Address;
  let alice: Address;
  let tp0: Address;
  let mocCore0: Address;
  const execute = false;
  const BASEFEE = 1;

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
      mocCore0 = buckets[0].mocImpl.target.toString();

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
    });
    describe("WHEN MocCore rebalance functions caller is not MultiCollateralGuard", () => {
      it("THEN tx reverts because caller is not MultiCollateralGuard", async () => {
        await expect(buckets[0].mocImpl.rebalance(tp0, 1, 1)).to.be.revertedWithCustomError(
          buckets[0].mocImpl,
          ERRORS.ONLY_MULTICOLLATERALGUARD,
        );
        await expect(buckets[0].mocImpl.acceptRebalance(tp0, 1)).to.be.revertedWithCustomError(
          buckets[0].mocImpl,
          ERRORS.ONLY_MULTICOLLATERALGUARD,
        );
      });
    });
    describe("WHEN trying to execute rebalance on a bucket that has not been set", function () {
      it("THEN tx reverts because bucket does not exist", async function () {
        await expect(mocMultiCollateralGuard.execMicroLiquidation(alice)).to.be.revertedWithCustomError(
          mocMultiCollateralGuard,
          ERRORS.BUCKET_DOES_NOT_EXIST,
        );
      });
    });
    describe("WHEN trying to execute rebalance", () => {
      it("THEN tx reverts because micro liquidation threshold is not reached", async () => {
        await expect(mocMultiCollateralGuard.execMicroLiquidation(mocCore0)).to.be.revertedWithCustomError(
          mocMultiCollateralGuard,
          ERRORS.MICRO_LIQUIDATION_NOT_AVAILABLE,
        );
      });
    });
    describe("WHEN all the buckets AC price fall", function () {
      before(async () => {
        await Promise.all([
          buckets[0].priceProviders[tp0].poke(pEth(0.1)),
          buckets[1].priceProviders[tp0].poke(pEth(0.1)),
          buckets[2].priceProviders[tp0].poke(pEth(0.1)),
        ]);
      });
      describe("WHEN trying to execute micro liquidation", () => {
        it("THEN tx reverts because buckets are below liquidation", async () => {
          for (let bucket of buckets) {
            await expect(
              mocMultiCollateralGuard.execMicroLiquidation(bucket.mocImpl.target.toString()),
            ).to.be.revertedWithCustomError(mocMultiCollateralGuard, ERRORS.MICRO_LIQUIDATION_NOT_AVAILABLE);
          }
        });
      });
      describe("WHEN asks if bucket micro liquidation is available", () => {
        it("THEN returns false", async () => {
          for (let bucket of buckets) {
            expect(await mocMultiCollateralGuard.isMicroLiquidationAvailable(bucket.mocImpl.target.toString())).to.be
              .false;
          }
        });
        it("THEN isMicroLiquidationAvailableWithPrices returns false", async () => {
          const bucketsPACtps = (await buckets[0].mocImpl.getPACtps()).map((p: bigint) => p);
          expect(await mocMultiCollateralGuard.isMicroLiquidationAvailableWithPrices(mocCore0, bucketsPACtps)).to.be
            .false;
        });
        it("THEN readyToMicroLiquidate returns false", async () => {
          const allBucketsPACtps: bigint[][] = await Promise.all(
            buckets.map(async (bucket: any) => {
              const pACtps = await bucket.mocImpl.getPACtps();
              return pACtps.map((p: bigint) => p);
            }),
          );
          expect(await mocMultiCollateralGuard.readyToMicroLiquidate(allBucketsPACtps)).to.be.false;
        });
      });
      describe("WHEN asks for qAC and qTP to rebalance on micro liquidation", () => {
        it("THEN returns 0 because there is no target bucket available to rebalance", async () => {
          for (let bucket of buckets) {
            const { targetBucket, targetTP, qACToSwap, qTPToRebalance, qACExecFee } =
              await mocMultiCollateralGuard.getACAndTPtoRebalanceOnMicroLiquidation(
                bucket.mocImpl.target.toString(),
                BASEFEE,
              );
            expect(targetBucket).to.be.equal(CONSTANTS.ZERO_ADDRESS);
            expect(targetTP).to.be.equal(CONSTANTS.ZERO_ADDRESS);
            expect(qACToSwap).to.be.equal(0);
            expect(qTPToRebalance).to.be.equal(0);
            expect(qACExecFee).to.be.equal(0);
          }
        });
      });
    });
  });
});
