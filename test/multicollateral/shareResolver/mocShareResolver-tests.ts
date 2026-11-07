import { expect } from "chai";
import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { loadFixture, setNextBlockBaseFeePerGas } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../../helpers/assertHelper";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { pEth, timedDescribe } from "../../helpers/utils";
import { MocMultiCollateralGuard, MocShareResolver, V3SwapRouterMock__factory } from "../../../typechain";
import { addSwappers } from "../liquidation/utils";
import { fixtureCase1 } from "../fixture";

timedDescribe("Feature: multicollateral ShareResolver", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let alice: Address;
  let tp0: Address;
  let tp1: Address;
  let tp2: Address;

  describe("GIVEN 3 Moc implementations deployed with 3 TPs and some operations executed", function () {
    before(async function () {
      ({ alice } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixtureCase1);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });
      tp0 = tps[0].target;
      tp1 = tps[1].target;
      tp2 = tps[2].target;

      // add collateral to every buckets
      await Promise.all(mocFunctions.map(fncs => fncs.mintTC({ from: alice, qTC: 10000, execute: false })));
      await mocFunctions[0].executeQueue();

      await Promise.all([
        mocFunctions[0].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500, execute: false }), // 100 AC0
        mocFunctions[0].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 525, execute: false }), // 100 AC0
        mocFunctions[0].mintTP({ tp: tps[2].target.toString(), from: alice, qTP: 93458, execute: false }), // 100 AC0

        mocFunctions[1].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500 * 2, execute: false }), // 400 AC1
        mocFunctions[1].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 525 / 2, execute: false }), // 100 AC1
        mocFunctions[1].mintTP({ tp: tps[2].target.toString(), from: alice, qTP: 93458 / 2, execute: false }), // 100 AC1

        mocFunctions[2].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500 * 1.5, execute: false }), // 450 AC2
        mocFunctions[2].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 525 / 2, execute: false }), // 150 AC1
        mocFunctions[2].mintTP({ tp: tps[2].target.toString(), from: alice, qTP: 93458, execute: false }), // 300 AC2
      ]);

      await mocFunctions[0].executeQueue();

      const { coinbaseRC20Wrapper, mocSwapperV3 } = await addSwappers(mocMultiCollateralGuard, buckets);

      // set price and add liquidity to the swap router
      const [signer] = await ethers.getSigners();
      const swapRouter = V3SwapRouterMock__factory.connect(await mocSwapperV3.swapRouter(), signer);
      await coinbaseRC20Wrapper.deposit({ value: pEth(20000) });
      await coinbaseRC20Wrapper.transfer(swapRouter.target.toString(), pEth(20000));
      await buckets[2].collateralAsset.transfer(swapRouter.target.toString(), pEth(200000));
      await swapRouter.setPrice(pEth(1));
    });
    describe("WHEN metrics are requested", function () {
      it("THEN in bucket 0 the TVL is 10300, the LckAC is 300 and TC 0 total supply is 10000", async function () {
        const tvl = await buckets[0].mocImpl.getTotalACavailable();
        const lckAC = await buckets[0].mocImpl.getLckAC();
        const nTCcb = await buckets[0].mocImpl.nTCcb();
        assertPrec(tvl, 10300);
        assertPrec(lckAC, 300);
        assertPrec(nTCcb, 10000);
      });
      it("THEN in bucket 1 the TVL is 10600, the LckAC is 600 and TC 1 total supply is 10000", async function () {
        const tvl = await buckets[1].mocImpl.getTotalACavailable();
        const lckAC = await buckets[1].mocImpl.getLckAC();
        const nTCcb = await buckets[1].mocImpl.nTCcb();
        assertPrec(tvl, 10600);
        assertPrec(lckAC, 600);
        assertPrec(nTCcb, 10000);
      });
      it("THEN in bucket 2 the TVL is 10900, the LckAC is 900 and TC 2 total supply is 10000", async function () {
        const tvl = await buckets[2].mocImpl.getTotalACavailable();
        const lckAC = await buckets[2].mocImpl.getLckAC();
        const nTCcb = await buckets[2].mocImpl.nTCcb();
        assertPrec(tvl, 10900, undefined, 1);
        assertPrec(lckAC, 900, undefined, 1);
        assertPrec(nTCcb, 10000);
      });
      it("THEN normalization factors are 1, 0.5 and 0.33", async function () {
        const normFactors = await mocMultiCollateralGuard.getNormalizationFactors();
        assertPrec(normFactors[0], 1);
        assertPrec(normFactors[1], 0.5);
        assertPrec(normFactors[2], "0.333333333333333333");
      });
    });
    describe("AND a MocShareResolver is deployed", function () {
      let mocShareResolver: MocShareResolver;
      before(async function () {
        const MocShareResolverFactory = await ethers.getContractFactory("MocShareResolver");
        mocShareResolver = await MocShareResolverFactory.deploy(mocMultiCollateralGuard.target);
      });
      describe("WHEN checks getPACtps values", function () {
        it("THEN bucket 0 address and pACtps are ok", async function () {
          const bucket0 = buckets[0].mocImpl;
          expect((await mocShareResolver.getPACtps()).buckets[0]).to.be.equal(bucket0.target);
          expect((await mocShareResolver.getPACtps()).pACtps[0]).to.be.deep.eq(await bucket0.getPACtps());
        });
        it("THEN bucket 1 address and pACtps are ok", async function () {
          const bucket1 = buckets[1].mocImpl;
          expect((await mocShareResolver.getPACtps()).buckets[1]).to.be.equal(bucket1.target);
          expect((await mocShareResolver.getPACtps()).pACtps[1]).to.be.deep.eq(await bucket1.getPACtps());
        });
        it("THEN bucket 2 address and pACtps are ok", async function () {
          const bucket2 = buckets[2].mocImpl;
          expect((await mocShareResolver.getPACtps()).buckets[2]).to.be.equal(bucket2.target);
          expect((await mocShareResolver.getPACtps()).pACtps[2]).to.be.deep.eq(await bucket2.getPACtps());
        });
      });
      describe("AND some TP prices are expired", function () {
        before(async function () {
          await buckets[0].priceProviders[0].deprecatePriceProvider();
          await buckets[1].priceProviders[1].deprecatePriceProvider();
          await buckets[2].priceProviders[1].deprecatePriceProvider();
        });
        after(async function () {
          await buckets[0].priceProviders[0].restorePriceProvider();
          await buckets[1].priceProviders[1].restorePriceProvider();
          await buckets[2].priceProviders[1].restorePriceProvider();
        });
        it("THEN getPACtps does not revert", async function () {
          expect((await mocShareResolver.getPACtps()).buckets).to.have.length.above(0);
        });
        describe("WHEN call getTokenShare with an invalid token", function () {
          it("THEN tx reverts by InvalidToken", async function () {
            await expect(mocShareResolver.getTokenShare(tp0, 1)).to.be.revertedWithCustomError(
              mocShareResolver,
              "InvalidToken",
            );
          });
        });
        it("THEN TC 0 full token share is 54.54%", async function () {
          // AC available normalized = 10000 * 1
          // total AC available normalized = 10000 * 1 + 10000 * 0.5 + 10000 * 0.33 = 18333.33
          // shares = 10000 / 18333.33 = 0.54
          assertPrec(
            await mocShareResolver.getTokenShare(buckets[0].mocCollateralToken.target, pEth(10000)),
            "0.545454545454545454",
          );
        });
        it("THEN TC 1 full token share is 27.27%", async function () {
          // AC available normalized = 10000 * 0.5
          // total AC available normalized = 10000 * 1 + 10000 * 0.5 + 10000 * 0.33 = 18333.33
          // shares = 5000 / 18333.33 = 0.27
          assertPrec(
            await mocShareResolver.getTokenShare(buckets[1].mocCollateralToken.target, pEth(10000)),
            "0.272727272727272727",
          );
        });
        it("THEN TC 2 full token share is 18.18%", async function () {
          // AC available normalized = 10000 * 0.33
          // total AC available normalized = 10000 * 1 + 10000 * 0.5 + 10000 * 0.33 = 18333.33
          // shares = 3333 / 18333.33 = 0.18
          assertPrec(
            await mocShareResolver.getTokenShare(buckets[2].mocCollateralToken.target, pEth(10000)),
            "0.181818181818181818",
          );
        });
      });
      describe("AND bucket 0 is full liquidated and removed from the protocol", function () {
        before(async function () {
          await buckets[0].priceProviders[tp0].poke(pEth(1));
          await buckets[0].priceProviders[tp1].poke(pEth(1));
          await buckets[0].priceProviders[tp2].poke(pEth(1));

          await buckets[0].mocImpl.setLiqEnabled(true);
          const BASEFEE = 1;
          await setNextBlockBaseFeePerGas(BASEFEE);
          await mocMultiCollateralGuard.execLiquidation(buckets[0].mocImpl.target, { gasPrice: BASEFEE });
          await mocMultiCollateralGuard.execLiquidation(buckets[0].mocImpl.target, { gasPrice: BASEFEE });
          await mocMultiCollateralGuard.execLiquidation(buckets[0].mocImpl.target, { gasPrice: BASEFEE });
          await setNextBlockBaseFeePerGas(0);
        });
        it("THEN bucket 0 is removed and AC rebalanced to bucket 1", async function () {
          expect(await mocMultiCollateralGuard.getBucketAmount()).to.be.equal(2);
          assertPrec(await buckets[1].mocImpl.nACcb(), "20899.700000000000000002");
          assertPrec(await buckets[1].mocImpl.getLckAC(), "1200.000000000000000000");
          assertPrec(await buckets[2].mocImpl.nACcb(), "10900.000000000000000001");
          assertPrec(await buckets[2].mocImpl.getLckAC(), "900.000000000000000001");
        });
        it("THEN bucket 2 is index 0 now", async function () {
          expect(await mocMultiCollateralGuard.buckets(0)).to.be.equal(buckets[2].mocImpl.target);
          expect(await mocMultiCollateralGuard.buckets(1)).to.be.equal(buckets[1].mocImpl.target);
        });
        it("THEN normalization factors are 1 and 1.5", async function () {
          const normFactors = await mocMultiCollateralGuard.getNormalizationFactors();
          assertPrec(normFactors[0], 1);
          assertPrec(normFactors[1], 1.5);
        });
        it("THEN bucket 1 address and pACtps are ok", async function () {
          const bucket1 = buckets[1].mocImpl;
          expect((await mocShareResolver.getPACtps()).buckets[1]).to.be.equal(bucket1.target);
          expect((await mocShareResolver.getPACtps()).pACtps[1]).to.be.deep.eq(await bucket1.getPACtps());
        });
        it("THEN bucket 2 address and pACtps are ok", async function () {
          const bucket2 = buckets[2].mocImpl;
          expect((await mocShareResolver.getPACtps()).buckets[0]).to.be.equal(bucket2.target);
          expect((await mocShareResolver.getPACtps()).pACtps[0]).to.be.deep.eq(await bucket2.getPACtps());
        });
        it("THEN TC 0 reverts by InvalidToken", async function () {
          await expect(mocShareResolver.getTokenShare(tp0, 1)).to.be.revertedWithCustomError(
            mocShareResolver,
            "InvalidToken",
          );
        });
        it("THEN TC 1 full token share is 74.71%", async function () {
          // AC available normalized = (20899.7 - 1200) * 1.5 = 29549.55
          // total AC available normalized = (20899.7 - 1200) * 1.5 + 10000 * 1 = 39549.55
          // shares = 29549.55 / 39549.55 = 0.7471
          assertPrec(
            await mocShareResolver.getTokenShare(buckets[1].mocCollateralToken.target, pEth(10000)),
            "0.747152622469787898",
          );
        });
        it("THEN TC 2 full token share is 25.28%", async function () {
          // AC available normalized = 10000 * 1
          // total AC available normalized = (20899.7 - 1200) * 1.5 + 10000 * 1 = 39549.55
          // shares = 10000 / 39549.55 = 0.2528
          assertPrec(
            await mocShareResolver.getTokenShare(buckets[2].mocCollateralToken.target, pEth(10000)),
            "0.252847377530212101",
          );
        });
        describe("AND bucket 1 is full liquidated and removed from the protocol", function () {
          before(async function () {
            await buckets[1].priceProviders[tp0].poke(pEth(1));
            await buckets[1].priceProviders[tp1].poke(pEth(1));
            await buckets[1].priceProviders[tp2].poke(pEth(1));

            await buckets[1].mocImpl.setLiqEnabled(true);
            const BASEFEE = 1;
            await setNextBlockBaseFeePerGas(BASEFEE);
            await mocMultiCollateralGuard.execLiquidation(buckets[1].mocImpl.target, { gasPrice: BASEFEE });
            await mocMultiCollateralGuard.execLiquidation(buckets[1].mocImpl.target, { gasPrice: BASEFEE });
            await mocMultiCollateralGuard.execLiquidation(buckets[1].mocImpl.target, { gasPrice: BASEFEE });
            await mocMultiCollateralGuard.execLiquidation(buckets[1].mocImpl.target, { gasPrice: BASEFEE });
            await setNextBlockBaseFeePerGas(0);
          });
          it("THEN bucket 1 is removed and AC rebalanced to bucket 2", async function () {
            expect(await mocMultiCollateralGuard.getBucketAmount()).to.be.equal(1);
            assertPrec(await buckets[2].mocImpl.nACcb(), "31799.300000000000000008");
            assertPrec(await buckets[2].mocImpl.getLckAC(), "2700.000000000000000006");
          });
          it("THEN bucket 2 address and pACtps are ok", async function () {
            const bucket2 = buckets[2].mocImpl;
            expect((await mocShareResolver.getPACtps()).buckets[0]).to.be.equal(bucket2.target);
            expect((await mocShareResolver.getPACtps()).pACtps[0]).to.be.deep.eq(await bucket2.getPACtps());
          });
          it("THEN TC 1 reverts by InvalidToken", async function () {
            await expect(mocShareResolver.getTokenShare(tp1, 1)).to.be.revertedWithCustomError(
              mocShareResolver,
              "InvalidToken",
            );
          });
          it("THEN TC 2 full token share is 100%", async function () {
            assertPrec(await mocShareResolver.getTokenShare(buckets[2].mocCollateralToken.target, pEth(10000)), 1);
          });
          it("THEN TC 2 half token share is 50%", async function () {
            assertPrec(
              await mocShareResolver.getTokenShare(buckets[2].mocCollateralToken.target, pEth(10000 / 2)),
              0.5,
            );
          });
        });
      });
    });
  });
});
