import { expect } from "chai";
import { getNamedAccounts, ethers, network } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { loadFixture, setNextBlockBaseFeePerGas } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../../helpers/assertHelper";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { pEth, timedDescribe } from "../../helpers/utils";
import { V3SwapRouterMock__factory, MocMultiCollateralGuard } from "../../../typechain";
import { fixtureLiquidation2 } from "../fixture";
import { addSwappers } from "./utils";

timedDescribe("Feature: multicollateral all buckets liquidated", () => {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(1);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let tp0: Address;
  let mocCore0: Address;
  let mocCore1: Address;
  let mocCore2: Address;
  const BASEFEE = 1;

  describe("GIVEN 3 Moc implementations deployed", function () {
    before(async () => {
      const mocContracts = await loadFixture(fixtureLiquidation2);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });
      tp0 = tps[0].target.toString();
      mocCore0 = buckets[0].mocImpl.target.toString();
      mocCore1 = buckets[1].mocImpl.target.toString();
      mocCore2 = buckets[2].mocImpl.target.toString();

      await buckets[0].priceProviders[tp0].poke(pEth(1));
      await buckets[1].priceProviders[tp0].poke(pEth(1));
      await buckets[2].priceProviders[tp0].poke(pEth(1));

      await setBucketStorage(mocCore0, mocFunctions[0], pEth(10), pEth(50), pEth(40));
      await setBucketStorage(mocCore1, mocFunctions[1], pEth(1000), pEth(900), pEth(0));
      await setBucketStorage(mocCore2, mocFunctions[2], pEth(100), pEth(130), pEth(30));

      const [signer] = await ethers.getSigners();

      const { coinbaseRC20Wrapper, mocSwapperV3 } = await addSwappers(mocMultiCollateralGuard, buckets);

      // set price and add liquidity to the swap router
      const swapRouter = V3SwapRouterMock__factory.connect(await mocSwapperV3.swapRouter(), signer);
      await buckets[0].collateralAsset.transfer(swapRouter.target.toString(), pEth(2000));
      await buckets[2].collateralAsset.transfer(swapRouter.target.toString(), pEth(2000));
      await coinbaseRC20Wrapper.deposit({ value: pEth(20000) });
      await coinbaseRC20Wrapper.transfer(swapRouter.target.toString(), pEth(20000));
      await swapRouter.setPrice(pEth(1));

      // enable liquidation
      await buckets[0].mocImpl.setLiqEnabled(true);
      await buckets[1].mocImpl.setLiqEnabled(true);
      await buckets[2].mocImpl.setLiqEnabled(true);

      // set liquidation exec cost to 0 to avoid interference with the test scenario
      await mocMultiCollateralGuard.setLiquidationExecCost(0);
    });
    it("THEN validate coverages are ok", async () => {
      assertPrec(await buckets[0].mocImpl.getCglb(), 5);
      assertPrec(await buckets[1].mocImpl.getCglb(), 0.9);
      assertPrec(await buckets[2].mocImpl.getCglb(), 1.3);
      assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "0.972972972972972972");
    });
    it("THEN liquidate bucket 1 to bucket 0 until rtc threshold", async () => {
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.false;
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore1)).to.be.true;
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore2)).to.be.false;

      await setNextBlockBaseFeePerGas(BASEFEE);
      await mocMultiCollateralGuard.execLiquidation(mocCore1, { gasPrice: BASEFEE });
      await setNextBlockBaseFeePerGas(0);

      // tpLiqPrice = 1000 / 900 = 1.111
      // TP rebalance = 40 TP
      // AC rebalance = 40 / 1.111 = 36
      assertPrec(await buckets[0].mocImpl.getCglb(), 1.72); // rtc = 1.8 but bucket 0 receives less AC from bucket 1 due to liqPrice > 1
      assertPrec(await buckets[1].mocImpl.getCglb(), "0.899999999999999999");
      assertPrec(await buckets[2].mocImpl.getCglb(), 1.3);
      assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "0.972972972972972972");
    });

    it("THEN liquidate bucket 1 to bucket 2 to liq threshold", async () => {
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.false;
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore1)).to.be.true;
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore2)).to.be.false;

      await setNextBlockBaseFeePerGas(BASEFEE);
      await mocMultiCollateralGuard.execLiquidation(mocCore1, { gasPrice: BASEFEE });
      await setNextBlockBaseFeePerGas(0);

      // tpLiqPrice = 960 / 864 = 1.111
      // TP rebalance = 650 TP
      // AC rebalance = 650 / 1.111 = 585
      assertPrec(await buckets[0].mocImpl.getCglb(), 1.72);
      assertPrec(await buckets[1].mocImpl.getCglb(), "0.899999999999999999");
      assertPrec(await buckets[2].mocImpl.getCglb(), "0.953333333333333333"); // liq = 1.04 but bucket 0 receives less AC from bucket 1 due to liqPrice > 1
      assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "0.972972972972972972");
    });

    it("THEN liquidate bucket 1 to bucket 0 to liq threshold", async () => {
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.false;
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore1)).to.be.true;
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore2)).to.be.true;

      await setNextBlockBaseFeePerGas(BASEFEE);
      await mocMultiCollateralGuard.execLiquidation(mocCore1, { gasPrice: BASEFEE });
      await setNextBlockBaseFeePerGas(0);

      // tpLiqPrice = 310 / 279 = 1.111
      // TP rebalance = 310 TP
      // AC rebalance = 310 / 1.111 = 279
      assertPrec(await buckets[0].mocImpl.getCglb(), "1.013888888888888888"); // liq = 1.04 but bucket 0 receives less AC from bucket 1 due to liqPrice > 1
      assertPrec(await buckets[1].mocImpl.getCglb(), ethers.MaxUint256); // bucket 1 is empty
      assertPrec(await buckets[2].mocImpl.getCglb(), "0.953333333333333333");
      assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "0.972972972972972972");
    });

    it("THEN liquidate bucket 2 to bucket 0", async () => {
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore0)).to.be.true;
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore1)).to.be.false;
      expect(await mocMultiCollateralGuard.isLiquidationAvailable(mocCore2)).to.be.true;

      await setNextBlockBaseFeePerGas(BASEFEE);
      await mocMultiCollateralGuard.execLiquidation(mocCore2, { gasPrice: BASEFEE });
      await setNextBlockBaseFeePerGas(0);

      // tpLiqPrice = 750 / 715 = 1.048951048951048950
      // TP rebalance = 750 TP
      // AC rebalance = 750 / 1.048951048951048950 = 715
      assertPrec(await buckets[0].mocImpl.getCglb(), "0.972972972972972972");
      assertPrec(await buckets[1].mocImpl.getCglb(), ethers.MaxUint256); // bucket 1 is empty
      assertPrec(await buckets[2].mocImpl.getCglb(), ethers.MaxUint256); // bucket 2 is empty
      assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "0.972972972972972972");

      // after all liquidations, bucket 0 should have all the AC and TP from the other buckets
      assertPrec(await buckets[0].mocImpl.nACcb(), 1080);
      assertPrec(await buckets[0].mocImpl.getNTP(tp0), 1110);
    });
  });
});

async function setBucketStorage(mocCore: string, mocFunctions: any, nTP: bigint, nACcb: bigint, nTCcb: bigint) {
  // nACcb slot = 305
  // nTCcb slot = 308
  // pegContainer slot = 311, each item uses 2 slots, nTP offset = 0
  const nACcbSlot = 305n;
  const nTCcbSlot = 308n;
  const pegContainerSlot = 311n;
  const tpIndex = 0n;
  const pegContainerBaseSlot = BigInt(ethers.keccak256(ethers.toBeHex(pegContainerSlot, 32)));
  const nTPSlot = pegContainerBaseSlot + tpIndex * 2n;

  // bucket must have the nACcb balance
  const { alice } = await getNamedAccounts();
  await mocFunctions.acTransfer({ from: alice, to: mocCore, amount: nACcb, applyPrecision: false });

  await network.provider.send("hardhat_setStorageAt", [
    mocCore,
    ethers.toBeHex(nACcbSlot, 32),
    ethers.toBeHex(nACcb, 32),
  ]);
  await network.provider.send("hardhat_setStorageAt", [
    mocCore,
    ethers.toBeHex(nTCcbSlot, 32),
    ethers.toBeHex(nTCcb, 32),
  ]);
  await network.provider.send("hardhat_setStorageAt", [mocCore, ethers.toBeHex(nTPSlot, 32), ethers.toBeHex(nTP, 32)]);
  await network.provider.send("evm_mine");
}
