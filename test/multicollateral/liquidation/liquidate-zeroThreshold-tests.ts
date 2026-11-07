import { expect } from "chai";
import { getNamedAccounts, ethers } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture, setNextBlockBaseFeePerGas } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../../helpers/assertHelper";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { pEth, timedDescribe } from "../../helpers/utils";
import { MocMultiCollateralGuard, PriceProviderMock__factory, V3SwapRouterMock__factory } from "../../../typechain";
import { fixtureLiquidation } from "../fixture";
import { addSwappers } from "./utils";

// bucket 1 and 2 are below the liquidate threshold, so when bucket 0 starts the liquidation
// the amount of tokens rebalanced have no limit
timedDescribe("Feature: multicollateral liquidate using no threshold", () => {
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
  let mocCore2: Address;
  const execute = false;
  const BASEFEE = 1;

  describe("GIVEN 3 Moc implementations deployed", async () => {
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
      let qACToSwap: bigint;
      let qTPToRebalance: bigint;
      let qACExecFee: bigint;
      before(async () => {
        await buckets[0].priceProviders[tp0].poke(pEth(15));
        await buckets[0].priceProviders[tp1].poke(pEth(4));
      });
      describe("WHEN other buckets AC price fall making coverage go below the liquidation threshold", () => {
        before(async () => {
          await buckets[1].priceProviders[tp0].poke(pEth(11));
          await buckets[2].priceProviders[tp0].poke(pEth(11));
          expect(await buckets[1].mocImpl.getCglb()).to.be.lessThan(await buckets[1].mocImpl.liqThrld());
          expect(await buckets[2].mocImpl.getCglb()).to.be.lessThan(await buckets[2].mocImpl.liqThrld());
        });
        it("THEN calcACAndTPtoRebalance returns qACToSwap, qTPToRebalance and qACExecFee amounts", async () => {
          ({ qACToSwap, qTPToRebalance, qACExecFee } = await mocMultiCollateralGuard.getACAndTPtoRebalanceOnLiquidation(
            mocCore0,
            BASEFEE,
          ));
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
                pEth("1596.513839436165692345"),
                pEth("1596.513839436165692345"),
                pEth(23500),
                pEth("0.111111111111111111"),
              );
          });
          describe("AND TP0 prices rises again", () => {
            before(async () => {
              await buckets[0].priceProviders[tp0].poke(pEth(1500));
            });
            it("THEN bucket 0 coverage is still below the liquidate threshold because there is not AC locked on TP 0", async () => {
              expect(await buckets[0].mocImpl.getCglb()).to.be.lessThan(await buckets[0].mocImpl.liqThrld());
            });
          });
          describe("AND TP1 prices rises again", () => {
            before(async () => {
              await buckets[0].priceProviders[tp1].poke(pEth(150));
            });
            it("THEN bucket 0 coverage is above the liquidate threshold", async () => {
              expect(await buckets[0].mocImpl.getCglb()).to.be.greaterThan(await buckets[0].mocImpl.liqThrld());
            });
            it("AND liquidation is not available anymore", async () => {
              expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.false;
            });
            it("THEN isLiquidationAvailableWithPrices returns false", async () => {
              const bucketsPACtps = (await buckets[0].mocImpl.getPACtps()).map((p: bigint) => p);
              expect(await mocMultiCollateralGuard.isLiquidationAvailableWithPrices(mocCore0, bucketsPACtps)).to.be
                .false;
            });
            it("THEN readyToLiquidate returns false", async () => {
              const allBucketsPACtps: bigint[][] = await Promise.all(
                buckets.map(async (bucket: any) => {
                  const pACtps = await bucket.mocImpl.getPACtps();
                  return pACtps.map((p: bigint) => p);
                }),
              );
              expect(await mocMultiCollateralGuard.readyToLiquidate(allBucketsPACtps)).to.be.false;
            });
          });
        });
      });
    });
  });
});
