import { expect } from "chai";
import { getNamedAccounts, ethers } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture, setNextBlockBaseFeePerGas } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../../helpers/assertHelper";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { CONSTANTS, ERRORS, pEth, timedDescribe } from "../../helpers/utils";
import { MocMultiCollateralGuard, PriceProviderMock__factory, V3SwapRouterMock__factory } from "../../../typechain";
import { fixtureLiquidation } from "../fixture";
import { addSwappers } from "./utils";

// bucket 1 and 2 are below the rtc threshold, so when bucket 0 starts the liquidation
// the amount of tokens rebalanced are limited to their liquidation threshold.
timedDescribe("Feature: multicollateral liquidate using liquidation threshold", () => {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let deployer: Address;
  let alice: Address;
  let from: Address;
  let tp0: Address;
  let tp1: Address;
  let mocCore0: Address;
  let mocCore1: Address;
  let mocCore2: Address;
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

      const swapRouter = V3SwapRouterMock__factory.connect(await mocSwapperV3.swapRouter(), signer);
      await coinbaseRC20Wrapper.deposit({ value: pEth(2000) });
      await coinbaseRC20Wrapper.transfer(swapRouter.target.toString(), pEth(2000));
      await buckets[2].collateralAsset.transfer(swapRouter.target.toString(), pEth(2000));
      await swapRouter.setPrice(pEth(1));

      // bucket 0 acCoinbasePrice
      const acCoinbasePriceProviderAddress = await mocMultiCollateralGuard.acCoinbasePriceProvider(await mocCore0);
      const acCoinbasePrice = PriceProviderMock__factory.connect(acCoinbasePriceProviderAddress, signer);
      // use an AC coinbase price != 1
      await acCoinbasePrice.poke(pEth(0.9));

      // enable liquidation
      await buckets[0].mocImpl.setLiqEnabled(true);
    });
    describe("WHEN bucket 0 AC price falls making coverage go below the liquidation threshold", () => {
      let targetBucket: Address;
      let targetTP: Address;
      let qACToSwap: bigint;
      let qTPToRebalance: bigint;
      let qACExecFee: bigint;
      before(async () => {
        await buckets[0].priceProviders[tp0].poke(pEth(15));
        await buckets[0].priceProviders[tp1].poke(pEth(4));
      });
      describe("WHEN other buckets AC price fall making coverage go below the rtc threshold", () => {
        before(async () => {
          await buckets[1].priceProviders[tp0].poke(pEth(15));
          await buckets[2].priceProviders[tp0].poke(pEth(14));
          expect(await buckets[1].mocImpl.getCglb()).to.be.lessThan(await mocMultiCollateralGuard.rtcThrld(mocCore1));
          expect(await buckets[2].mocImpl.getCglb()).to.be.lessThan(await mocMultiCollateralGuard.rtcThrld(mocCore2));
          ({ targetBucket, targetTP, qACToSwap, qTPToRebalance, qACExecFee } =
            await mocMultiCollateralGuard.getACAndTPtoRebalanceOnLiquidation(mocCore0, BASEFEE));
        });
        it("THEN bucket 0 coverage is below the liquidate threshold 1.01 < 1.04", async () => {
          // tp0 LckAC = 23500 / 15 = 1566.66
          // tp1 LckAC = 52.5 / 4 = 13.125
          // coverage => 1610 / 1579.78 = 1.01
          assertPrec(await buckets[0].mocImpl.getCglb(), "1.019121719636027957");
          expect(await buckets[0].mocImpl.getCglb()).to.be.lessThan(await buckets[0].mocImpl.liqThrld());
        });
        it("THEN liquidation is available on bucket 0", async () => {
          expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.true;
        });
        it("THEN target bucket is 2(RC20) because its score is greater than bucket 1", async () => {
          expect(targetBucket).to.be.equal(mocCore2);
        });
        it("THEN target TP is 0 because its LckAc is greater than TP 1", async () => {
          // tp0 LckAC = 23500 / 15 = 1566.66
          // tp1 LckAC = 52.5 / 4 = 13.125
          expect(targetTP).to.be.equal(tp0);
        });
        it("THEN calcACAndTPtoRebalance returns qACToSwap, qTPToRebalance and qACExecFee amounts", async () => {
          // lckAC = 1566.66 + 13.125 = 1579.78
          // qACExecFee = 0.1 / 0.9 = 0.11
          // totalACAvailable = 1610
          // => tpLiqPrice = 15 * 1579.78 / (1610 - 0.11) = 14.719
          // => TPAvailable on bucket 2 = ((1.07 - 1.04) * 1830) / (1.07 * (1.04 - 1)) * 14 = 18579.99
          // => qTPToRebalance = 18579.99
          // => qACToSwap = 18579.99 / 14.719 = 1262.264984541445022311
          assertPrec(qTPToRebalance, "18579.999999999999662105");
          assertPrec(qACToSwap, "1262.264984541445022311");
          assertPrec(qACExecFee, "0.111111111111111111");
        });
        describe("AND the liquidation is executed", () => {
          let execTX: ContractTransactionResponse;
          before(async () => {
            await setNextBlockBaseFeePerGas(BASEFEE);
            execTX = await mocMultiCollateralGuard.execLiquidation(mocCore0, { gasPrice: BASEFEE });
            await execTX.wait();
            await setNextBlockBaseFeePerGas(0);
          });
          it("THEN a PartialLiquidationExecuted event is emitted", async () => {
            await expect(execTX)
              .to.emit(mocMultiCollateralGuard, "PartialLiquidationExecuted")
              .withArgs(
                deployer,
                mocCore0,
                mocCore2,
                tp0,
                pEth("1262.264984541445022311"),
                pEth("1262.264984541445022311"),
                pEth("18579.999999999999662105"),
                pEth("0.111111111111111111"),
              );
          });
          it("THEN bucket 0 coverage is 1.019", async () => {
            // lckAC = 328 + 13.125 = 341.125
            // totalACAvailable = 1610 - 1262.26 - 0.11 = 347.63
            // coverage => 347.63 / 341.125 = 1.019
            assertPrec(await buckets[0].mocImpl.getCglb(), "1.019051386874148314");
          });
          it("THEN bucket 2 coverage is below liquidation threshold", async () => {
            assertPrec(await buckets[2].mocImpl.getCglb(), "1.018628465496005427");
          });
          it("THEN target bucket is 1(coinbase) because its still above the liquidation threshold", async () => {
            ({ targetBucket, targetTP, qACToSwap, qTPToRebalance, qACExecFee } =
              await mocMultiCollateralGuard.getACAndTPtoRebalanceOnLiquidation(mocCore0, BASEFEE));
            expect(targetBucket).to.be.equal(mocCore1);
            expect(targetTP).to.be.equal(tp0);
            // lckAC = 328 + 13.125 = 341.125
            // qACExecFee = 0.1 / 0.9 = 0.11
            // totalACAvailable = 347.63
            // => tpLiqPrice = 15 * 341.125 / (347.63 - 0.11) = 14.719
            // => TPAvailable on bucket 2 = ((1.07 - 1.04) * 1830) / (1.07 * (1.04 - 1)) * 14 = 18579.99
            // => qTPToRebalance = 18579.99
            // => qACToSwap = 18579.99 / 14.719 = 1262.264984541445022311
            assertPrec(qTPToRebalance, "4920.000000000000337895");
            assertPrec(qACToSwap, "334.142018853842855539");
            assertPrec(qACExecFee, "0.111111111111111111");
          });
          describe("AND the liquidation is executed again on bucket 0", () => {
            before(async () => {
              await setNextBlockBaseFeePerGas(BASEFEE);
              execTX = await mocMultiCollateralGuard.execLiquidation(mocCore0, { gasPrice: BASEFEE });
              await execTX.wait();
              await setNextBlockBaseFeePerGas(0);
            });
            it("THEN a PartialLiquidationExecuted event is emitted", async () => {
              await expect(execTX)
                .to.emit(mocMultiCollateralGuard, "PartialLiquidationExecuted")
                .withArgs(
                  deployer,
                  mocCore0,
                  mocCore1,
                  tp0,
                  pEth("334.142018853842855539"),
                  pEth("334.142018853842855539"),
                  pEth("4920.000000000000337895"),
                  pEth("0.111111111111111111"),
                );
            });
            it("THEN bucket 0 nTP 0 is 0", async () => {
              assertPrec(await buckets[0].mocImpl.getNTP(tp0), 0);
            });
            it("THEN bucket 1 coverage is still above liquidation threshold", async () => {
              assertPrec(await buckets[1].mocImpl.getCglb(), "1.072845761936199250");
            });
            it("THEN target bucket is 1(coinbase) because its still above the liquidation threshold", async () => {
              ({ targetBucket, targetTP, qACToSwap, qTPToRebalance, qACExecFee } =
                await mocMultiCollateralGuard.getACAndTPtoRebalanceOnLiquidation(mocCore0, BASEFEE));
              expect(targetBucket).to.be.equal(mocCore1);
              expect(targetTP).to.be.equal(tp1);
              // lckAC = 0 + 13.125 = 13.125
              // qACExecFee = 0.1 / 0.9 = 0.11
              // totalACAvailable = 347.63 - 334.14 - 0.11 = 13.38
              // => tpLiqPrice = 4 * 13.125 / (13.38 - 0.11) = 3.95
              // => qTPToRebalance = 52.5
              // => qACToSwap = 52.5 / 3.95 = 13.25
              assertPrec(qTPToRebalance, 52.5);
              assertPrec(qACToSwap, "13.259663271378788818");
              assertPrec(qACExecFee, "0.111111111111111110");
            });
            describe("AND the liquidation is executed again on bucket 0", () => {
              before(async () => {
                await setNextBlockBaseFeePerGas(BASEFEE);
                execTX = await mocMultiCollateralGuard.execLiquidation(mocCore0, { gasPrice: BASEFEE });
                await execTX.wait();
                await setNextBlockBaseFeePerGas(0);
              });
              it("THEN a PartialLiquidationExecuted event is emitted", async () => {
                await expect(execTX)
                  .to.emit(mocMultiCollateralGuard, "PartialLiquidationExecuted")
                  .withArgs(
                    deployer,
                    mocCore0,
                    mocCore1,
                    tp1,
                    pEth("13.259663271378788818"),
                    pEth("13.259663271378788818"),
                    pEth(52.5),
                    pEth("0.111111111111111110"),
                  );
              });
              it("THEN a BucketLiquidated event is emitted", async () => {
                await expect(execTX).to.emit(mocMultiCollateralGuard, "BucketLiquidated").withArgs(mocCore0);
              });
              it("THEN bucket 0 nACcb is 0", async () => {
                assertPrec(await buckets[0].mocImpl.nACcb(), 0);
              });
              it("THEN bucket 0 nTP 1 is 0", async () => {
                assertPrec(await buckets[0].mocImpl.getNTP(tp1), 0);
              });
              it("THEN bucket 0 coverage is MAX_UINT256", async () => {
                assertPrec(await buckets[0].mocImpl.getCglb(), CONSTANTS.MAX_UINT256);
              });
              describe("AND the liquidation is executed again", () => {
                it("THEN tx reverts because does not exist", async () => {
                  await expect(mocMultiCollateralGuard.execLiquidation(mocCore0)).to.be.revertedWithCustomError(
                    mocMultiCollateralGuard,
                    ERRORS.BUCKET_DOES_NOT_EXIST,
                  );
                });
              });
            });
          });
        });
      });
    });
  });
});
