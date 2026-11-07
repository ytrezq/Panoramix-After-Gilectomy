import { expect } from "chai";
import { getNamedAccounts, ethers } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { loadFixture, setNextBlockBaseFeePerGas } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../../helpers/assertHelper";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { ERRORS, ERROR_SELECTOR, pEth, timedDescribe } from "../../helpers/utils";
import { V3SwapRouterMock__factory, MocMultiCollateralGuard, PriceProviderMock__factory } from "../../../typechain";
import { fixtureLiquidation } from "../fixture";
import { addSwappers } from "./utils";

timedDescribe("Feature: multicollateral bucket liquidated", () => {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let from: Address;
  let alice: Address;
  let tp0: Address;
  let tp1: Address;
  let mocCore0: Address;
  let mocCore2: Address;
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
      tp1 = tps[1].target.toString();
      mocCore0 = buckets[0].mocImpl.target.toString();
      mocCore2 = buckets[2].mocImpl.target.toString();

      await Promise.all([
        // add collateral
        mocFunctions[0].mintTC({ from, qTC: 1500, execute }),
        mocFunctions[1].mintTC({ from, qTC: 1500, execute }),
        mocFunctions[2].mintTC({ from, qTC: 1500, execute }),
      ]);
      await Promise.all([
        // add TPs
        mocFunctions[0].mintTP({ from, tp: tp0, qTP: 23500, execute }), // 100 AC
        mocFunctions[0].mintTP({ from, tp: tp1, qTP: 52.5, execute }), // 10 AC
        mocFunctions[1].mintTP({ from, tp: tp0, qTP: 23500, execute }), // 200 AC
        mocFunctions[1].mintTP({ from, tp: tp1, qTP: 52.5, execute }), // 20 AC
        mocFunctions[2].mintTP({ from, tp: tp0, qTP: 23500, execute }), // 300 AC
        mocFunctions[2].mintTP({ from, tp: tp1, qTP: 52.5, execute }), // 30 AC
      ]);

      await mocMultiCollateralGuard.execute();
      const [signer] = await ethers.getSigners();

      const { coinbaseRC20Wrapper, mocSwapperV3 } = await addSwappers(mocMultiCollateralGuard, buckets);

      // set price and add liquidity to the swap router
      const swapRouter = V3SwapRouterMock__factory.connect(await mocSwapperV3.swapRouter(), signer);
      await coinbaseRC20Wrapper.deposit({ value: pEth(20000) });
      await coinbaseRC20Wrapper.transfer(swapRouter.target.toString(), pEth(20000));
      await swapRouter.setPrice(pEth(1));

      // bucket 0 acCoinbasePrice
      const acCoinbasePriceProviderAddress = await mocMultiCollateralGuard.acCoinbasePriceProvider(await mocCore0);
      const acCoinbasePrice = PriceProviderMock__factory.connect(acCoinbasePriceProviderAddress, signer);
      // use an AC coinbase price != 1
      await acCoinbasePrice.poke(pEth(0.9));

      // enable liquidation
      await buckets[0].mocImpl.setLiqEnabled(true);
    });
    describe("WHEN bucket 0 AC price falls making coverage go below the liquidate threshold", () => {
      before(async () => {
        await buckets[0].priceProviders[tp0].poke(pEth(15));
        await buckets[0].priceProviders[tp1].poke(pEth(4));
      });
      it("THEN combined coverage is 3.59", async () => {
        // coverage bucket 0 = 1610 / 1579.78 = 1.01
        // coverage bucket 1 = 1720 / 220 = 7.81
        // coverage bucket 2 = 1830 / 330 = 5.54

        const normalizationFactors = await mocMultiCollateralGuard.getNormalizationFactors();
        // normalization factor AC1 = (117.5 / 15 + 2.52 / 4 + 467.29 / 934.58) / 3 = 2.99
        assertPrec(normalizationFactors[1], "2.996527777777777777");
        // normalization factor AC2 = (78.33 / 15 + 1.75 / 4 + 311.52 / 934.58) / 3 = 1.99
        assertPrec(normalizationFactors[2], "1.997685185185185185");
        // lckAC1 normalized = 220 * 2.99 = 657.8 AC0
        // lckAC2 normalized = 330 * 1.99 = 656.7 AC0
        // combined coverage = (1.01 * 1579.78 + 7.81 * 657.8 + 5.54 * 656.7) / (1579.78 + 657.8 + 656.7) = 3.59
        assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "3.595183898406613153");
      });
      describe("AND operations are enqueued in all the buckets", () => {
        before(async () => {
          // all the operation types on bucket 0
          await Promise.all([
            mocFunctions[0].mintTC({ from, qTC: 1, execute }),
            mocFunctions[0].redeemTC({ from, qTC: 1, execute }),
            mocFunctions[0].mintTP({ from, tp: tp0, qTP: 1, execute }),
            mocFunctions[0].redeemTP({ from, qTP: 1, execute }),
            mocFunctions[0].swapTPforTP({ iFrom: 0, iTo: 1, from, qTP: 1, execute }),
            mocFunctions[0].swapTPforTC({ from, qTP: 1, execute }),
            mocFunctions[0].swapTCforTP({ from, qTC: 1, execute }),
            mocFunctions[0].redeemTCandTP({ from, qTC: 1, qTP: 1, execute }),
            mocFunctions[0].mintTCandTP({ from, qTP: 1, execute }),

            mocFunctions[1].mintTC({ from, qTC: 100, execute }),
            mocFunctions[2].mintTC({ from, qTC: 100, execute }),

            mocFunctions[1].mintTP({ from, tp: tp0, qTP: 2350, execute }), // 20 AC
            mocFunctions[2].mintTP({ from, tp: tp0, qTP: 2350, execute }), // 30 AC
          ]);
        });
        describe("AND the liquidation is executed until all the AC is cleared", () => {
          let execTX: ContractTransactionResponse;
          before(async () => {
            await setNextBlockBaseFeePerGas(BASEFEE);
            // First liquidation will move all the TP0 and part of the AC to other bucket, but won't clear it completely
            execTX = await mocMultiCollateralGuard.execLiquidation(mocCore0, { gasPrice: BASEFEE });
            await execTX.wait();
            // Second liquidation will move all the TP1, empty the bucket AC and so, actually liquidate it
            await setNextBlockBaseFeePerGas(BASEFEE);
            execTX = await mocMultiCollateralGuard.execLiquidation(mocCore0, { gasPrice: BASEFEE });
            await execTX.wait();
            await setNextBlockBaseFeePerGas(0);
          });
          it("THEN a BucketLiquidated event is emitted", async () => {
            await expect(execTX).to.emit(mocMultiCollateralGuard, "BucketLiquidated").withArgs(mocCore0);
          });
          it("THEN bucket 0 is liquidated", async () => {
            expect(await buckets[0].mocImpl.liquidated()).to.be.true;
          });
          it("THEN bucket 0 does not exist in mocMultiCollateralGuard anymore", async () => {
            const { index, exists } = await mocMultiCollateralGuard.bucketIndex(mocCore0);
            expect(index).to.be.equal(0);
            expect(exists).to.be.false;
          });
          it("THEN bucket 0 cannot be added again", async () => {
            await expect(
              mocMultiCollateralGuard.addBucket(
                mocCore0,
                {
                  acCoinbasePriceProvider: mocCore0,
                  rebalanceExecFeeRecipient: ethers.Wallet.createRandom(),
                  rtcThrld: 0,
                  microLiquidationThrld: 0,
                  penaltyRate: 0,
                },
                [],
              ),
            ).to.be.revertedWithCustomError(mocMultiCollateralGuard, ERRORS.BUCKET_ALREADY_EXISTS);
          });
          it("THEN bucket 2 is bucket 0", async () => {
            const { index, exists } = await mocMultiCollateralGuard.bucketIndex(mocCore2);
            expect(index).to.be.equal(0);
            expect(exists).to.be.true;
            expect(await mocMultiCollateralGuard.buckets(0)).to.be.equal(mocCore2);
          });
          it("THEN bucket amount is 2", async () => {
            expect(await mocMultiCollateralGuard.getBucketAmount()).to.be.equal(2);
          });
          it("THEN base bucket is bucket 2 and combined coverage is 6.89", async () => {
            // coverage bucket 1 = (1720 + 1610) / (220 + 220) = 7.56
            // coverage bucket 2 = 1830 / 330 = 5.54

            // normalization factor AC1 = (117.5 / 78.33 + 2.52 / 1.75 + 467.29 / 311.52) / 3 = 1.5
            assertPrec((await mocMultiCollateralGuard.getNormalizationFactors())[1], "1.500000000000000000");
            // lckAC1 normalized = 440 * 1.5 = 660 AC2
            // combined coverage = (7.56 * 660 + 5.54 * 330) / (660 + 330) = 6.88
            assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "6.893602693602693601");
          });
          describe("WHEN queue is executed", () => {
            before(async () => {
              await mocFunctions[0].executeQueue();
            });
            it("THEN bucket 0 operations are not executed because mocMultiCollateralGuard does not consider it", async () => {
              // AC, TC and TP locked on bucket 0 from pending operations
              assertPrec(await buckets[0].mocImpl.qACLockedInPending(), 10 * 6);
              assertPrec(await mocFunctions[0].tcBalanceOf(mocCore0), 1 * 3);
              assertPrec(await mocFunctions[0].tpBalanceOf(0, mocCore0), 1 * 4);
              // 1 * 3 TCs were locked on bucket 0
              assertPrec(await mocFunctions[0].tcBalanceOf(alice), 1500 - 1 * 3);
              // other buckets operations succeed
              assertPrec(await mocFunctions[1].tcBalanceOf(alice), 1500 + 100);
              assertPrec(await mocFunctions[2].tcBalanceOf(alice), 1500 + 100);

              // 1 * 4 TPs were locked on bucket 0
              assertPrec(await mocFunctions[0].tpBalanceOf(0, alice), 23500 * 3 + 2350 * 2 - 1 * 4);
            });
            describe("WHEN executeLiquidatedBucket is called for bucket 0", () => {
              before(async () => {
                execTX = await mocMultiCollateralGuard.executeLiquidatedBucket(mocCore0);
              });
              it("THEN bucket 0 enqueued operations are executed and funds returned", async () => {
                // AC, TC and TP locked on bucket 0 are 0
                assertPrec(await buckets[0].mocImpl.qACLockedInPending(), 0);
                assertPrec(await mocFunctions[0].tcBalanceOf(mocCore0), 0);
                assertPrec(await mocFunctions[0].tpBalanceOf(0, mocCore0), 0);
                // other token balances didn't change
                assertPrec(await mocFunctions[0].tcBalanceOf(alice), 1500);
                assertPrec(await mocFunctions[1].tcBalanceOf(alice), 1500 + 100);
                assertPrec(await mocFunctions[2].tcBalanceOf(alice), 1500 + 100);

                assertPrec(await mocFunctions[0].tpBalanceOf(0, alice), 23500 * 3 + 2350 * 2);
              });
              it("THEN Liquidated UnhandledError is emitted", async () => {
                await expect(execTX)
                  .to.emit(buckets[0].mocQueue, "UnhandledError")
                  .withArgs(anyValue, ERROR_SELECTOR.LIQUIDATED);
              });
            });
            describe("WHEN an operation is enqueued in bucket 0", () => {
              it("THEN tx revert because bucket is liquidated", async () => {
                await expect(mocFunctions[0].mintTC({ from, qTC: 1500, execute })).to.be.revertedWithCustomError(
                  buckets[0].mocImpl,
                  ERRORS.LIQUIDATED,
                );
              });
            });
            describe("AND operations are enqueued in bucket 1 and 2", () => {
              before(async () => {
                await Promise.all([
                  mocFunctions[1].mintTC({ from, qTC: 100, execute }),
                  mocFunctions[2].mintTC({ from, qTC: 100, execute }),

                  mocFunctions[1].mintTP({ from, tp: tp0, qTP: 2350, execute }), // 20 AC
                  mocFunctions[2].mintTP({ from, tp: tp0, qTP: 2350, execute }), // 30 AC
                ]);
              });
              describe("AND queue is executed", () => {
                before(async () => {
                  await mocMultiCollateralGuard.execute();
                });
                it("THEN operations succeed", async () => {
                  assertPrec(await mocFunctions[1].tcBalanceOf(alice), 1500 + 100 + 100);
                  assertPrec(await mocFunctions[2].tcBalanceOf(alice), 1500 + 100 + 100);

                  assertPrec(await mocFunctions[0].tpBalanceOf(0, alice), 23500 * 3 + 2350 * 2 + 2350 * 2);
                });
              });
            });
          });
        });
      });
    });
  });
});
