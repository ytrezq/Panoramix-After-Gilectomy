import { expect } from "chai";
import { getNamedAccounts, ethers } from "hardhat";
import { loadFixture, setNextBlockBaseFeePerGas } from "@nomicfoundation/hardhat-network-helpers";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { pEth, timedDescribe } from "../../helpers/utils";
import { MocMultiCollateralGuard, PriceProviderMock__factory, V3SwapRouterMock__factory } from "../../../typechain";
import { fixtureLiquidation } from "../fixture";
import { addSwappers } from "./utils";

async function setupLiquidatableBucket() {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(1);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;

  const { alice: from } = await getNamedAccounts();
  const mocContracts = await loadFixture(fixtureLiquidation);
  ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);
  mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
  mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
  mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });

  const tp0 = tps[0].target.toString();
  const tp1 = tps[1].target.toString();
  const mocCore0 = buckets[0].mocImpl.target.toString();
  const execute = false;
  await Promise.all([
    mocFunctions[0].mintTC({ from, qTC: 1500, execute }),
    mocFunctions[1].mintTC({ from, qTC: 1500, execute }),
    mocFunctions[2].mintTC({ from, qTC: 1500, execute }),
  ]);
  await Promise.all([
    mocFunctions[0].mintTP({ from, tp: tp0, qTP: 23500, execute }),
    mocFunctions[0].mintTP({ from, tp: tp1, qTP: 52.5, execute }),
    mocFunctions[1].mintTP({ from, tp: tp0, qTP: 23500, execute }),
    mocFunctions[1].mintTP({ from, tp: tp1, qTP: 52.5, execute }),
    mocFunctions[2].mintTP({ from, tp: tp0, qTP: 23500, execute }),
    mocFunctions[2].mintTP({ from, tp: tp1, qTP: 52.5, execute }),
  ]);
  await mocMultiCollateralGuard.execute();
  const [signer] = await ethers.getSigners();
  const { coinbaseRC20Wrapper, mocSwapperV3 } = await addSwappers(mocMultiCollateralGuard, buckets);
  const swapRouter = V3SwapRouterMock__factory.connect(await mocSwapperV3.swapRouter(), signer);
  await coinbaseRC20Wrapper.deposit({ value: pEth(50000) });
  await coinbaseRC20Wrapper.transfer(swapRouter.target.toString(), pEth(50000));
  if (buckets[0].collateralAsset) {
    await buckets[0].collateralAsset.mint(swapRouter.target.toString(), pEth(50000));
  }
  if (buckets[2].collateralAsset) {
    await buckets[2].collateralAsset.mint(swapRouter.target.toString(), pEth(50000));
  }
  await swapRouter.setPrice(pEth(0.5));
  const acCoinbasePriceProviderAddress = await mocMultiCollateralGuard.acCoinbasePriceProvider(mocCore0);
  const acCoinbasePrice = PriceProviderMock__factory.connect(acCoinbasePriceProviderAddress, signer);
  await acCoinbasePrice.poke(pEth(1));
  await buckets[0].mocImpl.setLiqEnabled(true);
  // Drop price to make bucket 0 liquidatable (coverage ~1.01)
  await buckets[0].priceProviders[tp0].poke(pEth(15));
  await buckets[0].priceProviders[tp1].poke(pEth(4));
  return { buckets, tps, mocMultiCollateralGuard, mocFunctions, mocCore0, tp0, tp1 };
}
timedDescribe("Feature: bucket do not stuck in liquidatable state due to tpLiqPrice underflow", () => {
  const BASEFEE = 1;
  describe("Scenario 1: governance increases liquidationExecCost after partial drain", function () {
    it("THEN execLiquidation works and exec fee recipient did not receive execution fees", async () => {
      const { buckets, mocMultiCollateralGuard, mocCore0 } = await setupLiquidatableBucket();
      const feeRecipient = await mocMultiCollateralGuard.rebalanceExecFeeRecipient(mocCore0);
      const feeRecipientBalanceBefore = await buckets[0].collateralAsset.balanceOf(feeRecipient);
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.true;
      // Round 1: drain most AC (moves tp0, leaves tp1 with ~13 AC)
      await setNextBlockBaseFeePerGas(BASEFEE);
      await mocMultiCollateralGuard.execLiquidation(mocCore0, { gasPrice: BASEFEE });
      await setNextBlockBaseFeePerGas(0);
      const remainingAC = await buckets[0].mocImpl.getTotalACavailable();
      const remainingLckAC = await buckets[0].mocImpl.getLckAC();
      const feeRecipientBalanceBefore2 = await buckets[0].collateralAsset.balanceOf(feeRecipient);

      expect(remainingLckAC).to.be.greaterThan(0);
      expect(remainingAC).to.be.greaterThan(0);
      // Confirm fee recipient received normal execution fees
      expect(feeRecipientBalanceBefore2).to.be.gt(feeRecipientBalanceBefore);
      // Governance increases liquidationExecCost above remaining AC
      // qACExecFee = liquidationExecCost * basefee / acCoinbasePrice
      // With basefee=1, acCoinbasePrice=1e18: qACExecFee ≈ liquidationExecCost
      await mocMultiCollateralGuard.setLiquidationExecCost(remainingAC + pEth(1));
      // Bucket is still liquidatable
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.true;
      // tpLiqPrice = (pACtp * lckAC) / (totalACavailable - qACExecFee)
      // totalACavailable (~13.4) < qACExecFee =>  qACExecFee = 0
      await setNextBlockBaseFeePerGas(BASEFEE);
      await mocMultiCollateralGuard.execLiquidation(mocCore0, { gasPrice: BASEFEE });
      await setNextBlockBaseFeePerGas(0);
      // Confirm liquidation
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.false;
      expect(await buckets[0].mocImpl.getLckAC()).to.be.eq(0);
      expect(await buckets[0].mocImpl.liquidated()).to.be.true;
      // Confirm fee recipient did not receive execution fees due to underflow protection
      expect(await buckets[0].collateralAsset.balanceOf(feeRecipient)).to.be.eq(feeRecipientBalanceBefore2);
    });
  });
  describe("Scenario 2: basefee spike combined with moderately raised exec cost", function () {
    it("THEN execLiquidation works and exec fee recipient did not receive execution fees", async () => {
      const { buckets, mocMultiCollateralGuard, mocCore0 } = await setupLiquidatableBucket();
      const feeRecipient = await mocMultiCollateralGuard.rebalanceExecFeeRecipient(mocCore0);
      const feeRecipientBalanceBefore = await buckets[0].collateralAsset.balanceOf(feeRecipient);
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.true;
      // Round 1: drain at normal basefee
      await setNextBlockBaseFeePerGas(BASEFEE);
      await mocMultiCollateralGuard.execLiquidation(mocCore0, { gasPrice: BASEFEE });
      await setNextBlockBaseFeePerGas(0);
      const remainingAC = await buckets[0].mocImpl.getTotalACavailable();
      const remainingLckAC = await buckets[0].mocImpl.getLckAC();
      const feeRecipientBalanceBefore2 = await buckets[0].collateralAsset.balanceOf(feeRecipient);
      expect(remainingLckAC).to.be.greaterThan(0);
      // Confirm fee recipient received normal execution fees
      expect(feeRecipientBalanceBefore2).to.be.gt(feeRecipientBalanceBefore);
      // Combined trigger: raise exec cost to ~remainingAC/2 and use basefee=3
      // qACExecFee = liquidationExecCost * basefee / acCoinbasePrice
      // With acCoinbasePrice=1: qACExecFee = execCost * basefee
      // Need qACExecFee > remainingAC, so execCost * 3 > remainingAC
      const newExecCost = remainingAC / 2n; // half of remaining
      await mocMultiCollateralGuard.setLiquidationExecCost(newExecCost);
      const spikedBasefee = 3; // 3x normal — qACExecFee = remainingAC/2 * 3 = 1.5 * remainingAC
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.true;

      await setNextBlockBaseFeePerGas(spikedBasefee);
      await mocMultiCollateralGuard.execLiquidation(mocCore0, { gasPrice: spikedBasefee });
      await setNextBlockBaseFeePerGas(0);
      // Confirm liquidation
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.false;
      expect(await buckets[0].mocImpl.getLckAC()).to.be.eq(0);
      expect(await buckets[0].mocImpl.liquidated()).to.be.true;
      // Confirm fee recipient did not receive execution fees due to underflow protection
      expect(await buckets[0].collateralAsset.balanceOf(feeRecipient)).to.be.eq(feeRecipientBalanceBefore2);
    });
  });
});
