import { expect } from "chai";
import hre, { getNamedAccounts, ethers } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture, setNextBlockBaseFeePerGas } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../../helpers/assertHelper";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { Balance, ERRORS, getNetworkDeployParams, pEth, timedDescribe } from "../../helpers/utils";
import { MocMultiCollateralGuard, V3SwapRouterMock, V3SwapRouterMock__factory } from "../../../typechain";
import { fixtureLiquidation } from "../fixture";
import { addSwappers, calcBucketScore } from "./utils";

timedDescribe("Feature: multicollateral micro liquidation from coinbase to RC20", function () {
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
  let swapRouter: V3SwapRouterMock;
  const execute = false;
  const BASEFEE = 1;
  const {
    multiCollateralParams: { coinbaseExecFeeRecipient },
  } = getNetworkDeployParams(hre);

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
      const [signer] = await ethers.getSigners();

      const { mocSwapperV3 } = await addSwappers(mocMultiCollateralGuard, buckets);

      swapRouter = V3SwapRouterMock__factory.connect(await mocSwapperV3.swapRouter(), signer);
      await buckets[0].collateralAsset.transfer(swapRouter.target.toString(), pEth(2000));
      await swapRouter.setPrice(pEth(2)); // 1 Coinbase == 2 RC20

      // use a different rtcThrld for target bucket to rebalance
      await mocMultiCollateralGuard.editBucket(mocCore0, {
        acCoinbasePriceProvider: await mocMultiCollateralGuard.acCoinbasePriceProvider(mocCore0),
        rtcThrld: pEth(1.2),
        rebalanceExecFeeRecipient: await mocMultiCollateralGuard.rebalanceExecFeeRecipient(mocCore0),
        microLiquidationThrld: await mocMultiCollateralGuard.microLiquidationThrld(mocCore0),
        penaltyRate: await mocMultiCollateralGuard.penaltyRate(mocCore0),
      });
    });
    describe("WHEN bucket 1 AC price falls making coverage go below the micro liquidation threshold", function () {
      let targetBucket: Address;
      let targetTP: Address;
      let qACToSwap: bigint;
      let qTPToRebalance: bigint;
      let qACExecFee: bigint;
      before(async () => {
        await buckets[1].priceProviders[tp0].poke(pEth(18));
        await buckets[1].priceProviders[tp1].poke(pEth(2));
        ({ targetBucket, targetTP, qACToSwap, qTPToRebalance, qACExecFee } =
          await mocMultiCollateralGuard.getACAndTPtoRebalanceOnMicroLiquidation(mocCore1, BASEFEE));
      });
      it("THEN bucket 1 coverage is below the micro liquidation threshold 1.29 < 1.3", async () => {
        // tp0 LckAC = 23500 / 18 = 1305.55
        // tp1 LckAC = 52.5 / 2 = 26.25
        // coverage => 1720 / 1331.8 = 1.29
        assertPrec(await buckets[1].mocImpl.getCglb(), "1.291479820627802690");
        expect(await buckets[1].mocImpl.getCglb()).to.be.lessThan(
          await mocMultiCollateralGuard.microLiquidationThrld(mocCore0),
        );
      });
      it("THEN target bucket is 0(rc20) because its score is greater than bucket 2", async () => {
        // bucket 0 coverage = 1610 / 110 = 14.63
        // bucket 0 totalACAvailable = 1610
        // bucket 0 ctargemaCA = 5.41
        //  => bucket 1 score = 14.63 * 1610 / 5.41
        const bucket0Score = await calcBucketScore(buckets[0]);
        assertPrec(bucket0Score, "4350.567016266276170994");

        // bucket 2 coverage = 1830 / 330 = 5.54
        // bucket 2 totalACAvailable = 1830
        // bucket 2 ctargemaCA = 4.9
        //  => bucket 2 score = 5.54 * 1830 / 4.9
        const bucket2Score = await calcBucketScore(buckets[2]);
        assertPrec(bucket2Score, "2067.222222222222222402");

        expect(bucket0Score).to.be.greaterThan(bucket2Score);
        expect(targetBucket).to.be.equal(mocCore0);
      });
      it("THEN target TP is 0 because its LckAc is greater than TP 1", async () => {
        // tp0 LckAC = 23500 / 18 = 1305.55
        // tp1 LckAC = 52.5 / 2 = 26.25
        expect(targetTP).to.be.equal(tp0);
      });
      it("THEN calcACAndTPtoRebalance returns qACOnTP, qTPToRebalance and qACExecFee amounts", async () => {
        // pr = 0.007
        // rtc = 1.8
        // lckAC = 1305.55 + 26.25 = 1331.8
        // qACExecFee = 0.01 / 1 = 0.01
        // totalACAvailable = 1720
        // => qACOnTP = (1.8 * 1331.8 + 0.01 - 1720) / (1.8 - 1.007) = 854.047919293820933163
        // => qACToSwap = 854.047919293820933163 * 1.007 = 860.026254728877679695
        // => qTPToRebalance = 854.047919293820933163 * 18 = 15372.862547288776796934
        assertPrec(qACToSwap, "860.026254728877679695");
        assertPrec(qTPToRebalance, "15372.862547288776796934");
        assertPrec(qACExecFee, 0.01);
      });
      describe("AND the micro liquidation is executed", () => {
        let execFeeRecipientBalanceIncrement: Balance;
        let execTX: ContractTransactionResponse;
        before(async () => {
          execFeeRecipientBalanceIncrement = await mocFunctions[1].acBalanceOf(coinbaseExecFeeRecipient);
          await setNextBlockBaseFeePerGas(BASEFEE);
          execTX = await mocMultiCollateralGuard.execMicroLiquidation(mocCore1, { gasPrice: BASEFEE });
          await execTX.wait();
          await setNextBlockBaseFeePerGas(0);
          execFeeRecipientBalanceIncrement =
            (await mocFunctions[1].acBalanceOf(coinbaseExecFeeRecipient)) - execFeeRecipientBalanceIncrement;
        });
        it("THEN a MicroLiquidationExecuted event is emitted", async () => {
          await expect(execTX)
            .to.emit(mocMultiCollateralGuard, "MicroLiquidationExecuted")
            .withArgs(
              deployer,
              mocCore1,
              mocCore0,
              tp0,
              pEth("860.026254728877679695"),
              pEth("1720.052509457755359390"),
              pEth("15372.862547288776796934"),
              pEth(0.01),
            );
        });
        it("THEN bucket 0 coverage increase to rtc = 1.8", async () => {
          assertPrec(
            await buckets[1].mocImpl.getCglb(),
            await mocMultiCollateralGuard.rtcThrld(mocCore1),
            undefined,
            1,
          );
        });
        it("THEN exec fee recipient balance increase by 0.01", async () => {
          assertPrec(execFeeRecipientBalanceIncrement, 0.01);
        });
        it("THEN bucket 1 nTP 0 is 8127.13 = 23500 - 15372.86", async () => {
          assertPrec(await buckets[1].mocImpl.getNTP(tp0), "8127.137452711223203066");
        });
        it("THEN bucket 0 nTP 0 is 38872.86 = 23500 + 15372.86", async () => {
          assertPrec(await buckets[0].mocImpl.getNTP(tp0), "38872.862547288776796934");
        });
        it("THEN both buckets nACcb match with their balances", async () => {
          expect(await buckets[0].mocImpl.nACcb()).to.be.equal(await mocFunctions[0].acBalanceOf(mocCore0));
          expect(await buckets[1].mocImpl.nACcb()).to.be.equal(await mocFunctions[1].acBalanceOf(mocCore1));
        });
        it("THEN bucket 1 nACcb is 859.96 = 1720 - 860.02 AcToSwap", async () => {
          assertPrec(await buckets[1].mocImpl.nACcb(), "859.963745271122320305");
        });
        it("THEN bucket 0 nACcb is 3330.05 = 1619 + 1720.05(860.02 AcToSwap * 2 pool price)", async () => {
          assertPrec(await buckets[0].mocImpl.nACcb(), "3330.052509457755359390");
        });
        it("THEN qACmin used was 65.41 = qTPToRebalance / pAC0TP0", async () => {
          // qTPToRebalance = 15372.86
          // pAC0TP0 = 235
          // => qACmin = 15372.86 / 235 = 65.41
          assertPrec(await swapRouter.lastAmountOutMinimum(), "65.416436371441603391");
        });
        it("THEN bucket 0 coverage increase to 18.98", async () => {
          // bucket 0 totalACAvailable = 3330.05
          // tp0 LckAC = (23500 + 15372.86) / 235 = 165.41
          // tp1 LckAC = 52.5 / 5.25 = 10
          // coverage => 3330.05 / 175.41 = 18.98
          assertPrec(await buckets[0].mocImpl.getCglb(), "18.983697185629859897");
        });
        it("THEN bucket 0 pTCac increase to 2.10", async () => {
          // bucket 1 totalACAvailable = 3330.05
          // tp0 LckAC = (23500 + 15372.86) / 235 = 165.41
          // tp1 LckAC = 52.5 / 5.25 = 10
          // pTCac => (3330.05 - 175.41) / 1500 = 2.09
          assertPrec(await buckets[0].mocImpl.getPTCac(), "2.103090715390875837");
        });
        describe("WHEN trying to execute micro liquidation again", () => {
          it("THEN tx reverts because micro liquidation threshold is not reached", async () => {
            await expect(mocMultiCollateralGuard.execMicroLiquidation(mocCore1)).to.be.revertedWithCustomError(
              mocMultiCollateralGuard,
              ERRORS.MICRO_LIQUIDATION_NOT_AVAILABLE,
            );
          });
        });
      });
    });
  });
});
