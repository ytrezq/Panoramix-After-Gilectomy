import { expect } from "chai";
import { getNamedAccounts, ethers } from "hardhat";
import { ContractRunner, ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture, setNextBlockBaseFeePerGas } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../../helpers/assertHelper";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { CONSTANTS, ERRORS, pEth, timedDescribe } from "../../helpers/utils";
import {
  MocMultiCollateralGuard,
  PriceProviderMock__factory,
  DataProviderMock,
  V3SwapRouterMock__factory,
  V3SwapRouterMock,
} from "../../../typechain";
import { fixtureLiquidation } from "../fixture";
import { addSwappers } from "./utils";

// bucket 1 and 2 are above the rtc threshold, so when bucket 0 starts the liquidation
// the amount of tokens rebalanced are limited to their rtc threshold
timedDescribe("Feature: multicollateral liquidate using RTC threshold", () => {
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
  let mocCore2: Address;
  let signer: ContractRunner | null | undefined;
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
      const acCoinbasePriceProviderAddress = await mocMultiCollateralGuard.acCoinbasePriceProvider(
        await buckets[0].mocImpl.target.toString(),
      );
      const acCoinbasePrice = PriceProviderMock__factory.connect(acCoinbasePriceProviderAddress, signer);
      // use an AC coinbase price != 1
      await acCoinbasePrice.poke(pEth(0.9));

      // enable liquidation
      await buckets[0].mocImpl.setLiqEnabled(true);
    });
    describe("WHEN bucket 0 AC price falls making coverage go below the liquidate threshold", () => {
      let targetBucket: Address;
      let targetTP: Address;
      let qACToSwap: bigint;
      let qTPToRebalance: bigint;
      let qACExecFee: bigint;
      before(async () => {
        await buckets[0].priceProviders[tp0].poke(pEth(15));
        await buckets[0].priceProviders[tp1].poke(pEth(4));
        ({ targetBucket, targetTP, qACToSwap, qTPToRebalance, qACExecFee } =
          await mocMultiCollateralGuard.getACAndTPtoRebalanceOnLiquidation(
            buckets[0].mocImpl.target.toString(),
            BASEFEE,
          ));
      });
      it("THEN other buckets coverage are above the rtc threshold", async () => {
        expect(await buckets[1].mocImpl.getCglb()).to.be.greaterThan(await mocMultiCollateralGuard.rtcThrld(mocCore1));
        expect(await buckets[2].mocImpl.getCglb()).to.be.greaterThan(await mocMultiCollateralGuard.rtcThrld(mocCore2));
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
      it("THEN isLiquidationAvailableWithPrices returns true", async () => {
        const bucketsPACtps = (await buckets[0].mocImpl.getPACtps()).map((p: bigint) => p);
        expect(await mocMultiCollateralGuard.isLiquidationAvailableWithPrices(mocCore0, bucketsPACtps)).to.be.true;
      });
      it("THEN readyToLiquidate returns true", async () => {
        const allBucketsPACtps: bigint[][] = await Promise.all(
          buckets.map(async (bucket: any) => {
            const pACtps = await bucket.mocImpl.getPACtps();
            return pACtps.map((p: bigint) => p);
          }),
        );
        expect(await mocMultiCollateralGuard.readyToLiquidate(allBucketsPACtps)).to.be.true;
      });
      it("THEN target bucket is 1(coinbase) because its score is greater than bucket 2", async () => {
        expect(targetBucket).to.be.equal(mocCore1);
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
        // => qTPToRebalance = 23500
        // => qACToSwap = 23500 / 14.719 = 1596.513839436165692345
        assertPrec(qTPToRebalance, 23500);
        assertPrec(qACToSwap, "1596.513839436165692345");
        assertPrec(qACExecFee, "0.111111111111111111");
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
          const { qACToSwap, qTPToRebalance } = await mocMultiCollateralGuard.getACAndTPtoRebalanceOnLiquidation(
            mocCore0,
            BASEFEE,
          );
          // => tpLiqPrice = 15 * 1579.78 / (1610 - 0.11) = 14.71
          // => qACToSwap = 300
          // => qTPToRebalance = 300 * 14.71 = 4415.8
          assertPrec(qACToSwap, 300);
          assertPrec(qTPToRebalance, "4415.871523224515149200");
        });
      });
      describe("AND bucket 2 redeems all its TPs (infinite coverage) and the liquidation is executed again", () => {
        let execTX: ContractTransactionResponse;
        before(async () => {
          await Promise.all([
            mocFunctions[2].redeemTP({ from, tp: tps[0], qTP: 23500, execute }),
            mocFunctions[2].redeemTP({ from, tp: tps[1], qTP: 52.5, execute }),
          ]);
          await mocMultiCollateralGuard.execute();

          // validates that bucket 2 has infinite coverage and is not selected as target for micro liquidation
          // and the liquidation is executed as well
          expect(await buckets[2].mocImpl.getCglb()).to.be.equal(ethers.MaxUint256);
          const { targetBucket } = await mocMultiCollateralGuard.getACAndTPtoRebalanceOnLiquidation(mocCore0, BASEFEE);
          expect(targetBucket).to.be.equal(mocCore1);

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
              pEth("1596.513839436165692345"),
              pEth("798.256919718082846172"),
              pEth(23500),
              pEth("0.111111111111111111"),
            );
        });
        it("THEN bucket 0 coverage is 1.019", async () => {
          // lckAC = 0 + 13.125 = 13.125
          // totalACAvailable = 1610 - 1596.51 - 0.11 = 13.38
          // coverage => 13.38 / 13.125 = 1.019
          assertPrec(await buckets[0].mocImpl.getCglb(), "1.019051386874148308");
        });
        it("THEN exec fee recipient balance increase by 0.11", async () => {
          const rebalanceExecFeeRecipient = await mocMultiCollateralGuard.rebalanceExecFeeRecipient(mocCore0);
          const execFeeRecipientBalanceIncrement = await mocFunctions[0].acBalanceOf(rebalanceExecFeeRecipient);
          assertPrec(execFeeRecipientBalanceIncrement, "0.111111111111111111");
        });
        it("THEN bucket 0 nTP 0 is 0", async () => {
          assertPrec(await buckets[0].mocImpl.getNTP(tp0), 0);
        });
        it("THEN bucket 1 nTP 0 is 47000 = 23500 + 23500", async () => {
          assertPrec(await buckets[1].mocImpl.getNTP(tp0), 47000);
        });
        it("THEN both buckets nACcb match with their balances", async () => {
          expect(await buckets[0].mocImpl.nACcb()).to.be.equal(await mocFunctions[0].acBalanceOf(mocCore0));
          expect(await buckets[1].mocImpl.nACcb()).to.be.equal(await mocFunctions[1].acBalanceOf(mocCore1));
        });
        it("THEN bucket 0 nACcb is 13.375 = 1610 - 1596.51 qACToSwap - 0.11 qACExecFee", async () => {
          assertPrec(await buckets[0].mocImpl.nACcb(), "13.375049452723196544");
        });
        it("THEN bucket 1 nACcb is 2518.25 = 1720 + 798.25(1596.51 qACToSwap / 2 pool price)", async () => {
          assertPrec(await buckets[1].mocImpl.nACcb(), "2518.256919718082846172");
        });
        it("THEN bucket 1 coverage decrease to 5.99", async () => {
          // bucket 1 totalACAvailable = 2518.25
          // tp0 LckAC = (23500 + 23500) / 117.5 = 400
          // tp1 LckAC = 52.5 / 2.625 = 20
          // coverage => 2518.25 / 420 = 5.99
          assertPrec(await buckets[1].mocImpl.getCglb(), "5.995849808852578205");
        });
        it("THEN bucket 1 pTCac increase to 1.39", async () => {
          // bucket 1 totalACAvailable = 2518.25
          // tp0 LckAC = (23500 + 23500) / 117.5 = 400
          // tp1 LckAC = 52.5 / 2.625 = 20
          // pTCac => (2518.25 - 420) / 1500 = 1.39
          assertPrec(await buckets[1].mocImpl.getPTCac(), "1.398837946478721897");
        });
        it("THEN qACmin used was 202.38 = qACtoSwap * nf * (1 - penalty rate)", async () => {
          // qACtoSwap = 1596.51
          // nf = pAC0TP0 / pAC1TP0 = 15 / 117.5 = 0.127659
          // qACmin = qACtoSwap * nf * (1 - penalty rate)
          // => qACmin = 1596.51 * 0.127659 * 0.993 = 202.38
          assertPrec(await swapRouter.lastAmountOutMinimum(), "202.383605433205855212");
        });
        describe("AND the liquidation is executed again", () => {
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
                pEth("13.263938341612085435"),
                pEth("6.631969170806042717"),
                pEth(52.5),
                pEth("0.111111111111111109"),
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
          it("THEN qACmin used was 20.07 = qACtoSwap * nf * (1 - penalty rate)", async () => {
            // qACtoSwap = 13.26
            // nf = pAC0TP0 / pAC1TP0 = 4 / 2.625 = 1.523
            // qACmin = qACtoSwap * nf * (1 - penalty rate)
            // => qACmin = 13.26 * 1.523 * 0.993 = 20.07
            assertPrec(await swapRouter.lastAmountOutMinimum(), "20.070233559193601275");
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
