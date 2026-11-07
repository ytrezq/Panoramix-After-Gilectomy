import { expect } from "chai";
import { getNamedAccounts, ethers } from "hardhat";
import { ContractRunner, ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture, setNextBlockBaseFeePerGas } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../../helpers/assertHelper";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { ERRORS, pEth, timedDescribe } from "../../helpers/utils";
import {
  DataProviderMock,
  MocMultiCollateralGuard,
  PriceProviderMock__factory,
  V3SwapRouterMock__factory,
  V3SwapRouterMock,
} from "../../../typechain";
import { fixtureLiquidation } from "../fixture";
import { addSwappers, calcBucketScore } from "./utils";

timedDescribe("Feature: multicollateral micro liquidation from RC20 to coinbase", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let deployer: Address;
  let from: Address;
  let alice: Address;
  let tp0: Address;
  let tp1: Address;
  let mocCore0: Address;
  let mocCore1: Address;
  let signer: ContractRunner;
  let swapRouter: V3SwapRouterMock;
  let maxACtoSwapProvider: DataProviderMock;
  const execute = false;
  const BASEFEE = 1;

  describe("GIVEN 3 Moc implementations deployed", function () {
    before(async () => {
      ({ deployer, alice } = await getNamedAccounts());
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
      [signer] = await ethers.getSigners();

      const {
        coinbaseRC20Wrapper,
        maxACtoSwapProvider: swapProvider,
        mocSwapperV3,
      } = await addSwappers(mocMultiCollateralGuard, buckets);
      maxACtoSwapProvider = swapProvider;
      // set price and add liquidity to the swap router
      swapRouter = V3SwapRouterMock__factory.connect(await mocSwapperV3.swapRouter(), signer);
      await coinbaseRC20Wrapper.deposit({ value: pEth(2000) });
      await coinbaseRC20Wrapper.transfer(swapRouter.target.toString(), pEth(2000));
      await swapRouter.setPrice(pEth(0.5)); // 2 RC20 == 1 Coinbase

      // bucket 0 acCoinbasePrice
      const acCoinbasePriceProviderAddress = await mocMultiCollateralGuard.acCoinbasePriceProvider(await mocCore0);
      const acCoinbasePrice = PriceProviderMock__factory.connect(acCoinbasePriceProviderAddress, signer);
      // use an AC coinbase price != 1
      await acCoinbasePrice.poke(pEth(0.9));
    });
    describe("WHEN bucket 0 AC price falls making coverage go below the micro liquidation threshold", function () {
      let targetBucket: Address;
      let targetTP: Address;
      let qACToSwap: bigint;
      let qTPToRebalance: bigint;
      let qACExecFee: bigint;
      before(async () => {
        await buckets[0].priceProviders[tp0].poke(pEth(18));
        await buckets[0].priceProviders[tp1].poke(pEth(4));
        ({ targetBucket, targetTP, qACToSwap, qTPToRebalance, qACExecFee } =
          await mocMultiCollateralGuard.getACAndTPtoRebalanceOnMicroLiquidation(mocCore0, BASEFEE));
      });
      it("THEN bucket 0 coverage is below the micro liquidation threshold 1.22 < 1.3", async () => {
        // tp0 LckAC = 23500 / 18 = 1305.55
        // tp1 LckAC = 52.5 / 4 = 13.125
        // coverage => 1610 / 1318.68 = 1.22
        assertPrec(await buckets[0].mocImpl.getCglb(), "1.220917373216072463");
        expect(await buckets[0].mocImpl.getCglb()).to.be.lessThan(
          await mocMultiCollateralGuard.microLiquidationThrld(mocCore0),
        );
      });
      it("THEN micro liquidation is available on bucket 0", async () => {
        expect(await mocMultiCollateralGuard.isMicroLiquidationAvailable(mocCore0)).to.be.true;
      });
      it("THEN isMicroLiquidationAvailableWithPrices returns true", async () => {
        const bucketsPACtps = (await buckets[0].mocImpl.getPACtps()).map((p: bigint) => p);
        expect(await mocMultiCollateralGuard.isMicroLiquidationAvailableWithPrices(mocCore0, bucketsPACtps)).to.be.true;
      });
      it("THEN readyToMicroLiquidate returns true", async () => {
        const allBucketsPACtps: bigint[][] = await Promise.all(
          buckets.map(async (bucket: any) => {
            const pACtps = await bucket.mocImpl.getPACtps();
            return pACtps.map((p: bigint) => p);
          }),
        );
        expect(await mocMultiCollateralGuard.readyToMicroLiquidate(allBucketsPACtps)).to.be.true;
      });
      it("THEN target bucket is 1(coinbase) because its score is greater than bucket 2", async () => {
        // bucket 1 coverage = 1720 / 220 = 7.81
        // bucket 1 totalACAvailable = 1720
        // bucket 1 ctargemaCA = 4.9
        //  => bucket 1 score = 7.81 * 1720 / 4.9
        const bucket1Score = await calcBucketScore(buckets[1]);
        assertPrec(bucket1Score, "2739.259259259259259479");

        // bucket 2 coverage = 1830 / 330 = 5.54
        // bucket 2 totalACAvailable = 1830
        // bucket 2 ctargemaCA = 4.9
        //  => bucket 2 score = 5.54 * 1830 / 4.9
        const bucket2Score = await calcBucketScore(buckets[2]);
        assertPrec(bucket2Score, "2067.222222222222222402");

        expect(bucket1Score).to.be.greaterThan(bucket2Score);
        expect(targetBucket).to.be.equal(mocCore1);
      });
      it("THEN target TP is 0 because its LckAc is greater than TP 1", async () => {
        // tp0 LckAC = 23500 / 18 = 1305.55
        // tp1 LckAC = 52.5 / 4 = 13.125
        expect(targetTP).to.be.equal(tp0);
      });
      it("THEN calcACAndTPtoRebalance returns qACToSwap, qTPToRebalance and qACExecFee amounts", async () => {
        // pr = 0.007
        // rtc = 1.8
        // lckAC = 1305.55 + 13.125 = 1318.680555555555555555
        // qACExecFee = 0.01 / 0.9 = 0.011
        // totalACAvailable = 1610
        // => qACOnTP = (1.8 * 1318.68 + 0.011 - 1610) / (1.8 - 1.007) = 962.971136331792069494
        // => qACToSwap = 962.971136331792069494 * 1.007 = 969.711934286114613981
        // => qTPToRebalance = 962.971136331792069494 * 18 = 17333.480453972257250910
        assertPrec(qACToSwap, "969.711934286114613981");
        assertPrec(qTPToRebalance, "17333.480453972257250910");
        assertPrec(qACExecFee, "0.011111111111111111");
      });
      describe("AND the micro liquidation is executed", () => {
        let execTX: ContractTransactionResponse;
        before(async () => {
          await setNextBlockBaseFeePerGas(BASEFEE);
          execTX = await mocMultiCollateralGuard.execMicroLiquidation(mocCore0, { gasPrice: BASEFEE });
          await execTX.wait();
          await setNextBlockBaseFeePerGas(0);
        });
        it("THEN a MicroLiquidationExecuted event is emitted", async () => {
          await expect(execTX)
            .to.emit(mocMultiCollateralGuard, "MicroLiquidationExecuted")
            .withArgs(
              deployer,
              mocCore0,
              mocCore1,
              tp0,
              pEth("969.711934286114613981"),
              pEth("484.855967143057306990"),
              pEth("17333.480453972257250910"),
              pEth("0.011111111111111111"),
            );
        });
        it("THEN bucket 0 coverage increase to rtc = 1.8", async () => {
          assertPrec(await buckets[0].mocImpl.getCglb(), await mocMultiCollateralGuard.rtcThrld(mocCore0));
        });
        it("THEN exec fee recipient balance increase by 0.011", async () => {
          const rebalanceExecFeeRecipient = await mocMultiCollateralGuard.rebalanceExecFeeRecipient(mocCore0);
          const execFeeRecipientBalanceIncrement = await mocFunctions[0].acBalanceOf(rebalanceExecFeeRecipient);
          assertPrec(execFeeRecipientBalanceIncrement, "0.011111111111111111");
        });
        it("THEN bucket 0 nTP 0 is 6166.51 = 23500 - 17333.48", async () => {
          assertPrec(await buckets[0].mocImpl.getNTP(tp0), "6166.519546027742749090");
        });
        it("THEN bucket 1 nTP 0 is 40833.48 = 23500 + 17333.48", async () => {
          assertPrec(await buckets[1].mocImpl.getNTP(tp0), "40833.480453972257250910");
        });
        it("THEN both buckets nACcb match with their balances", async () => {
          expect(await buckets[0].mocImpl.nACcb()).to.be.equal(await mocFunctions[0].acBalanceOf(mocCore0));
          expect(await buckets[1].mocImpl.nACcb()).to.be.equal(await mocFunctions[1].acBalanceOf(mocCore1));
        });
        it("THEN bucket 0 nACcb is 640.76 = 1610 - 969.71 qACToSwap", async () => {
          assertPrec(await buckets[0].mocImpl.nACcb(), "640.276954602774274908");
        });
        it("THEN bucket 1 nACcb is 2204.85 = 1720 + 483.09(969.71 qACToSwap / 2 pool price)", async () => {
          assertPrec(await buckets[1].mocImpl.nACcb(), "2204.855967143057306990");
        });
        it("THEN bucket 1 coverage decrease to 5.99", async () => {
          // bucket 1 totalACAvailable = 2204.85
          // tp0 LckAC = (23500 + 17333.48) / 117.5 = 347.51
          // tp1 LckAC = 52.5 / 2.625 = 20
          // coverage => 2204.85 / 367.51 = 5.99
          assertPrec(await buckets[1].mocImpl.getCglb(), "5.999298190321722385");
        });
        it("THEN bucket 1 pTCac increase to 1.22", async () => {
          // bucket 1 totalACAvailable = 2204.85
          // tp0 LckAC = (23500 + 17333.48) / 117.5 = 347.51
          // tp1 LckAC = 52.5 / 2.625 = 20
          // pTCac => (2204.85 - 367.51) / 1500 = 1.22
          assertPrec(await buckets[1].mocImpl.getPTCac(), "1.224891323037372915");
        });
        describe("WHEN trying to execute micro liquidation again", () => {
          it("THEN tx reverts because micro liquidation threshold is not reached", async () => {
            await expect(mocMultiCollateralGuard.execMicroLiquidation(mocCore0)).to.be.revertedWithCustomError(
              mocMultiCollateralGuard,
              ERRORS.MICRO_LIQUIDATION_NOT_AVAILABLE,
            );
          });
        });
        describe("WHEN bucket 0 AC price falls more making coverage go below the micro liquidation threshold again", function () {
          before(async () => {
            await buckets[0].priceProviders[tp0].poke(pEth(120));
            await buckets[0].priceProviders[tp1].poke(pEth(0.1));
            ({ targetBucket, targetTP, qACToSwap, qTPToRebalance, qACExecFee } =
              await mocMultiCollateralGuard.getACAndTPtoRebalanceOnMicroLiquidation(mocCore0, BASEFEE));
          });
          it("THEN bucket 0 coverage is below the micro liquidation threshold 1.11 < 1.3", async () => {
            // tp0 LckAC = (23500 - 17333.48) / 120 = 51.38
            // tp1 LckAC = 52.5 / 0.1 = 525
            // coverage => 640.76 / 576.38 = 1.11
            assertPrec(await buckets[0].mocImpl.getCglb(), "1.110844308151189491");
            expect(await buckets[0].mocImpl.getCglb()).to.be.lessThan(
              await mocMultiCollateralGuard.microLiquidationThrld(mocCore0),
            );
          });
          it("THEN target TP is 1 because its LckAc is greater than TP 0", async () => {
            // tp0 LckAC = (23500 - 17333.48) / 120 = 51.38
            // tp1 LckAC = 52.5 / 0.1 = 525
            expect(targetTP).to.be.equal(tp1);
          });
          it("THEN target bucket is 1(coinbase) because its score is greater than bucket 2", async () => {
            expect(targetBucket).to.be.equal(mocCore1);
          });
          it("THEN calcACAndTPtoRebalance returns qACToSwap, qTPToRebalance and qACExecFee amounts", async () => {
            // pr = 0.007
            // rtc = 1.8
            // lckAC = 51.38 + 525 = 576.38
            // qACExecFee = 0.01 / 0.9 = 0.011
            // totalACAvailable = 640.76
            // => qACOnTP = (1.8 * 576.38 + 0.011 - 640.76) / (1.8 - 1.007) = 500.923013491491774827
            // => qACToSwap = 500.923013491491774827 * 1.007 = 504.429474585932217251
            // => qTPToRebalance = 500.923013491491774827 * 0.1 = 50.092301349149177482
            assertPrec(qACToSwap, "504.429474585932217251");
            assertPrec(qTPToRebalance, "50.092301349149177482");
            assertPrec(qACExecFee, "0.011111111111111111");
          });
          describe("AND maxACtoSwap is set to 300", () => {
            before(async () => {
              // bucket 0 maxACtoSwapProvider
              await maxACtoSwapProvider.poke(pEth(300));
            });
            after(async () => {
              await maxACtoSwapProvider.poke(pEth(10000));
            });
            it("THEN qACToSwap is 300 and qTPToRebalance is 29.79", async () => {
              const { qACToSwap, qTPToRebalance } =
                await mocMultiCollateralGuard.getACAndTPtoRebalanceOnMicroLiquidation(mocCore0, BASEFEE);
              // => qACToSwap = 300
              // => qTPToRebalance = 300 / 1.007 * 0.1 = 29.791459781529294935
              assertPrec(qACToSwap, 300);
              assertPrec(qTPToRebalance, "29.791459781529294935");
            });
          });
          describe("AND bucket 1 and bucket 2 coverage falls", () => {
            before(async () => {
              await Promise.all([
                buckets[1].priceProviders[tp0].poke(pEth(235) / 6n),
                buckets[1].priceProviders[tp1].poke(pEth(5.25) / 15n),
                buckets[2].priceProviders[tp0].poke(pEth(235) / 8n),
                buckets[2].priceProviders[tp1].poke(pEth(5.25) / 8n),
              ]);
              ({ targetBucket, targetTP, qACToSwap, qTPToRebalance, qACExecFee } =
                await mocMultiCollateralGuard.getACAndTPtoRebalanceOnMicroLiquidation(mocCore0, BASEFEE));
            });
            it("THEN target bucket is 1(coinbase) because its score is greater than bucket 2", async () => {
              const bucket1Score = await calcBucketScore(buckets[1]);
              const bucket2Score = await calcBucketScore(buckets[2]);
              expect(bucket1Score).to.be.greaterThan(bucket2Score);
              expect(targetBucket).to.be.equal(mocCore1);
            });
            it("THEN qTPToRebalance is 25.48 and qACToSwap 248.86", async () => {
              // bucket 1 coverage = 2204.85 / (1042.55 + 150) = 1.84
              // bucket 1 totalACAvailable = 2204.85
              // bucket 1 rtc = 1.8
              // => TPAvailable on bucket 1 = ((1.84 - 1.8) * 2204.85) / (1.84 * (1.8 - 1)) * 0.35 = 25.48
              // => TPAvailable = min(52.5, 25.48) = 25.48

              // => qACToSwap = 25.4858892633049523754 / 0.1 * 1.007 = 256.642904881480870416
              // => qTPToRebalance = 25.485889263304952375
              assertPrec(qACToSwap, "256.642904881480870416");
              assertPrec(qTPToRebalance, "25.485889263304952375");
            });
            describe("AND bucket 2 redeems all its TPs (infinite coverage) and the micro liquidation is executed", () => {
              before(async () => {
                await Promise.all([
                  mocFunctions[2].redeemTP({ from, tp: tps[0], qTP: 23500, execute }),
                  mocFunctions[2].redeemTP({ from, tp: tps[1], qTP: 52.5, execute }),
                ]);
                await mocMultiCollateralGuard.execute();

                // validates that bucket 2 has infinite coverage and is not selected as target for micro liquidation
                // and the micro liquidation is executed as well
                expect(await buckets[2].mocImpl.getCglb()).to.be.equal(ethers.MaxUint256);
                const { targetBucket } = await mocMultiCollateralGuard.getACAndTPtoRebalanceOnMicroLiquidation(
                  mocCore0,
                  BASEFEE,
                );
                expect(targetBucket).to.be.equal(mocCore1);

                await setNextBlockBaseFeePerGas(BASEFEE);
                const execML = await mocMultiCollateralGuard.execMicroLiquidation(mocCore0, {
                  gasPrice: BASEFEE,
                });
                await execML.wait();
                await setNextBlockBaseFeePerGas(0);
              });
              it("THEN bucket 0 nTP 1 is 27.01 = 52.5 - 25.48", async () => {
                assertPrec(await buckets[0].mocImpl.getNTP(tp1), "27.014110736695047625");
              });
              it("THEN bucket 1 nTP 1 is 77.98 = 52.5 + 25.48", async () => {
                assertPrec(await buckets[1].mocImpl.getNTP(tp1), "77.985889263304952375");
              });
              it("THEN bucket 0 nACcb is 383.62 = 640.76 - 256.64 AcToSwap", async () => {
                assertPrec(await buckets[0].mocImpl.nACcb(), "383.622938610182293381");
              });
              it("THEN bucket 1 nACcb is 2333.17 = 2204.85 + 128.32(256.64 AcToSwap / 2 pool price)", async () => {
                assertPrec(await buckets[1].mocImpl.nACcb(), "2333.177419583797742198");
              });
              it("THEN qACmin used was 72.81 = qTPToRebalance / pAC1TP1", async () => {
                // qTPToRebalance = 25.48
                // pAC1TP1 = 5.25 / 15 = 0.35
                // => qACmin = 25.48 / 0.35 = 72.81
                assertPrec(await swapRouter.lastAmountOutMinimum(), "72.816826466585578214");
              });
            });
          });
        });
      });
    });
  });
});
