import { ethers, getNamedAccounts } from "hardhat";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { Address } from "hardhat-deploy/dist/types";
import { expect } from "chai";
import { ContractTransactionResponse } from "ethers";
import { Balance, CONSTANTS, ERRORS, ERROR_SELECTOR, pEth } from "../helpers/utils";
import {
  MocCACoinbase,
  MocCARC20,
  MocMultiCollateralGuard,
  MocQueue,
  MocRC20,
  PriceProviderMock,
} from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";

const shouldBehaveLikeLiquidable = function (fixture: any, functions: any) {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let mocQueue: MocQueue;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let mocCollateralToken: MocRC20;
  let priceProviders: PriceProviderMock[];
  let alice: Address, bob: Address, charlie: Address, otherUser: Address;
  let tp1: Address;

  describe("GIVEN there are open positions by multiple users", function () {
    async function baseSetup() {
      mocContracts = await fixture();
      mocFunctions = await functions(mocContracts);
      ({ alice, bob, charlie, otherUser } = await getNamedAccounts());
      await mocFunctions.mintTC({ from: alice, qTC: 100 });
      await mocFunctions.mintTP({ i: 0, from: bob, qTP: 20 });
      await mocFunctions.mintTP({ i: 1, from: charlie, qTP: 10 });
      ({ mocImpl, mocCollateralToken, priceProviders, mocQueue, mocMultiCollateralGuard } = mocContracts);
      tp1 = mocContracts.mocPeggedTokens[1].target.toString();

      await priceProviders[0].poke(pEth(0.1));
      await priceProviders[1].poke(pEth(0.1));

      // set rebalance parameters to 0, since we want to test single bucket liquidation with these parameter disabled
      await mocMultiCollateralGuard.setMicroLiquidationExecCost(0);
      await mocMultiCollateralGuard.setLiquidationExecCost(0);
      await mocMultiCollateralGuard.editBucket(mocImpl.target.toString(), {
        acCoinbasePriceProvider: CONSTANTS.ZERO_ADDRESS,
        rebalanceExecFeeRecipient: ethers.Wallet.createRandom(),
        rtcThrld: 0n,
        microLiquidationThrld: 0n,
        penaltyRate: 0n,
      });
    }
    describe("WHEN AC prices falls, and makes the coverage go under liquidation threshold", function () {
      before(async function () {
        await baseSetup();
      });
      it("THEN isLiquidationReached returns true", async function () {
        expect(await mocImpl.isLiquidationReached()).to.be.true;
      });
      describe("WHEN someone evaluates liquidation", function () {
        it("THEN it doesn't have any effect, as liquidation is disabled", async function () {
          await expect(
            mocMultiCollateralGuard.execLiquidation(mocImpl.target.toString()),
          ).to.be.revertedWithCustomError(mocMultiCollateralGuard, ERRORS.LIQUIDATION_NOT_AVAILABLE);
        });
      });
      describe("WHEN alice tries to liquidate his TP", function () {
        it("THEN tx fails because contract is not liquidated yet", async function () {
          await expect(mocFunctions.liqRedeemTP({ from: alice })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.ONLY_LIQUIDATED,
          );
        });
      });
      describe("WHEN someone tries to execute micro liquidation", function () {
        it("THEN tx fails because micro liquidation is not available", async function () {
          await expect(
            mocMultiCollateralGuard.execMicroLiquidation(mocImpl.target.toString()),
          ).to.be.revertedWithCustomError(mocMultiCollateralGuard, ERRORS.MICRO_LIQUIDATION_NOT_AVAILABLE);
        });
      });
      describe("AND micro liquidation is enabled", function () {
        before(async function () {
          await priceProviders[0].poke(pEth(0.3));
          await priceProviders[1].poke(pEth(0.3));
          await mocMultiCollateralGuard.editBucket(mocImpl.target.toString(), {
            acCoinbasePriceProvider: CONSTANTS.ZERO_ADDRESS,
            rebalanceExecFeeRecipient: ethers.Wallet.createRandom(),
            rtcThrld: 0n,
            microLiquidationThrld: pEth(1.8),
            penaltyRate: 0n,
          });
        });
        describe("WHEN someone tries to execute micro Liquidation", function () {
          it("THEN tx fails because there is not another bucket available", async function () {
            await expect(
              mocMultiCollateralGuard.execMicroLiquidation(mocImpl.target.toString()),
            ).to.be.revertedWithCustomError(mocMultiCollateralGuard, ERRORS.BUCKET_NOT_AVAILABLE);
          });
        });
      });
      describe("WHEN liquidation is enabled, someone injects collateral and re-evaluates", function () {
        it("THEN Liquidation is not longer Reached", async function () {
          await mocImpl.setLiqEnabled(true);
          await mocFunctions.acTransfer({
            from: alice,
            to: mocImpl.target.toString(),
            amount: 1000,
          });
          await expect(
            mocMultiCollateralGuard.execLiquidation(mocImpl.target.toString()),
          ).to.be.revertedWithCustomError(mocMultiCollateralGuard, ERRORS.LIQUIDATION_NOT_AVAILABLE);
        });
      });
      describe("WHEN liquidation is enabled, and then evaluated", function () {
        let tx: ContractTransactionResponse;
        before(async function () {
          await baseSetup();
          await mocImpl.setLiqEnabled(true);
          tx = await mocMultiCollateralGuard.execLiquidation(mocImpl.target.toString());

          await priceProviders[0].poke(pEth(1));
          await priceProviders[1].poke(pEth(1));
        });
        describe("WHEN liquidation is evaluated on a bucket that has not been set", function () {
          it("THEN tx reverts because bucket does not exist", async function () {
            await expect(mocMultiCollateralGuard.execLiquidation(alice)).to.be.revertedWithCustomError(
              mocMultiCollateralGuard,
              ERRORS.BUCKET_DOES_NOT_EXIST,
            );
          });
        });
        describe("WHEN liquidation is evaluated directly on mocCore contract", function () {
          it("THEN tx reverts because only MultiCollateralGuard can call it", async function () {
            await expect(mocImpl.liquidate()).to.be.revertedWithCustomError(mocImpl, ERRORS.ONLY_MULTICOLLATERALGUARD);
          });
        });
        it("THEN contract is liquidated", async function () {
          expect(await mocImpl.liquidated()).to.be.true;
        });
        it("THEN BucketLiquidated event is emitted", async function () {
          await expect(tx).to.emit(mocMultiCollateralGuard, "BucketLiquidated");
        });
        it("THEN even if prices are restored, alice cannot mintTC", async function () {
          await expect(mocFunctions.mintTC({ from: alice, qTC: 1 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.LIQUIDATED,
          );
        });
        it("THEN even if prices are restored, alice cannot redeemTC", async function () {
          await expect(mocFunctions.redeemTC({ from: alice, qTC: 1 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.LIQUIDATED,
          );
        });
        it("THEN even if prices are restored, bob cannot mintTP", async function () {
          await expect(mocFunctions.mintTP({ from: bob, qTP: 1 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.LIQUIDATED,
          );
        });
        it("THEN even if prices are restored, bob cannot redeemTP", async function () {
          await expect(mocFunctions.redeemTP({ from: bob, qTP: 1 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.LIQUIDATED,
          );
        });
        it("THEN even if prices are restored, bob cannot swapTPforTP", async function () {
          await expect(mocFunctions.swapTPforTP({ iFrom: 0, iTo: 1, from: bob, qTP: 1 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.LIQUIDATED,
          );
        });
        it("THEN even if prices are restored, bob cannot swapTPforTC", async function () {
          await expect(mocFunctions.swapTPforTC({ from: bob, qTP: 1 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.LIQUIDATED,
          );
        });
        it("THEN even if prices are restored, bob cannot swapTCforTP", async function () {
          await expect(mocFunctions.swapTCforTP({ from: bob, qTC: 1 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.LIQUIDATED,
          );
        });
        it("THEN even if prices are restored, bob cannot redeemTCandTP", async function () {
          await expect(mocFunctions.redeemTCandTP({ from: bob, qTC: 1, qTP: 1 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.LIQUIDATED,
          );
        });
        it("THEN even if prices are restored, bob cannot mintTCandTP", async function () {
          await expect(mocFunctions.mintTCandTP({ from: bob, qTP: 1 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.LIQUIDATED,
          );
        });
        describe("WHEN Bob and Charlie redeem their TPs by liquidation redeem", async function () {
          let bobPrevAssetBalance: Balance, charliePrevAssetBalance: Balance, otherUserPrevAssetBalance: Balance;
          before(async function () {
            [bobPrevAssetBalance, charliePrevAssetBalance, otherUserPrevAssetBalance] = await Promise.all(
              [bob, charlie, otherUser].map(account => mocFunctions.assetBalanceOf(account)),
            );
            await mocFunctions.liqRedeemTP({ from: bob });
            tx = await mocFunctions.liqRedeemTP({ i: 1, from: charlie, to: otherUser });
          });
          it("THEN theirs TP are burned", async function () {
            assertPrec(0, await mocFunctions.tpBalanceOf(0, bob));
            assertPrec(0, await mocFunctions.tpBalanceOf(1, charlie));
          });
          it("THEN a liq redeem event is generated for Charlie", async function () {
            // i: 1
            // sender: charlie
            // receiver: otherUser
            // qTP: 10 TP
            // qAC: 0.43333... AC
            const qAC = "43333333333333333247";
            await expect(tx).to.emit(mocImpl, "LiqTPRedeemed").withArgs(tp1, charlie, otherUser, pEth(10), qAC);
          });
          it("THEN they receive the corresponding AC amount", async function () {
            // Alice, bob and Charlie contribution at 1:1
            const totalAC = 100 + 20 + 10;
            const lckAC = 20n + 10n;
            const bobACShare = pEth(20 * totalAC) / lckAC;
            const charlieACShare = pEth(10 * totalAC) / lckAC;
            const [bobActualAssetBalance, charlieActualAssetBalance, otherUserActualAssetBalance] = await Promise.all(
              [bob, charlie, otherUser].map(account => mocFunctions.assetBalanceOf(account)),
            );
            const bobDiff = bobActualAssetBalance - bobPrevAssetBalance;
            const charlieDiff = charlieActualAssetBalance - charliePrevAssetBalance;
            const otherUserDiff = otherUserActualAssetBalance - otherUserPrevAssetBalance;
            // 1/14th of a reference value as tolerance
            const tolerance = Number(bobACShare / BigInt(10e14));
            assertPrec(bobACShare, bobDiff, "Bob's Asset balance", tolerance);
            assertPrec(0, charlieDiff, "Charlies's Asset balance", tolerance);
            assertPrec(charlieACShare, otherUserDiff, "Charlies's Asset balance", tolerance);
          });
          it("THEN contract balance is zero", async function () {
            assertPrec(0, await mocFunctions.acBalanceOf(mocImpl.target.toString()));
          });
          describe("WHEN Bob tries to redeem again", async function () {
            it("THEN it fails as he has no TPs left", async function () {
              await expect(mocFunctions.liqRedeemTP({ i: 1, from: bob })).to.be.revertedWithCustomError(
                mocImpl,
                ERRORS.INSUFFICIENT_TP_TO_REDEEM,
              );
            });
          });
        });
        describe("WHEN otherUser tries to redeem TPs by liquidation redeem", async function () {
          it("THEN it fails", async function () {
            await expect(mocFunctions.liqRedeemTP({ i: 1, from: otherUser })).to.be.reverted;
          });
        });
      });
    });
    const liquidateProtocol = async function () {
      await priceProviders[0].poke(pEth(0.1));
      await priceProviders[1].poke(pEth(0.1));
      await mocImpl.setLiqEnabled(true);
      await mocMultiCollateralGuard.execLiquidation(mocImpl.target.toString());
      // Reset prices to avoid Low coverage failures
      await priceProviders[0].poke(pEth(1));
      await priceProviders[1].poke(pEth(1));
    };
    const expectLiquidatedEvent = async (result: any) =>
      expect(result).to.emit(mocQueue, "UnhandledError").withArgs(anyValue, ERROR_SELECTOR.LIQUIDATED); // operID is not relevant here

    describe("WHEN alice enqueue a mintTC operation", function () {
      before(async function () {
        await baseSetup();
        await mocFunctions.mintTC({ from: alice, qTC: 1, execute: false });
      });
      describe("AND protocol is liquidated", function () {
        before(async function () {
          await liquidateProtocol();
        });
        describe("WHEN queue is executed", function () {
          it("THEN Operations fails with Unhandled Error", async function () {
            await expectLiquidatedEvent(mocMultiCollateralGuard.executeLiquidatedBucket(mocImpl.target.toString()));
            // tokens are returned
            assertPrec(await mocImpl.qACLockedInPending(), 0);
          });
        });
      });
    });
    describe("WHEN alice enqueue a redeemTC operation", function () {
      before(async function () {
        await baseSetup();
        await mocFunctions.redeemTC({ from: alice, qTC: 1, execute: false });
      });
      describe("AND protocol is liquidated", function () {
        before(async function () {
          await liquidateProtocol();
        });
        describe("WHEN queue is executed", function () {
          it("THEN Operations fails with Unhandled Error", async function () {
            await expectLiquidatedEvent(mocMultiCollateralGuard.executeLiquidatedBucket(mocImpl.target.toString()));
            // tokens are returned
            assertPrec(await mocFunctions.tcBalanceOf(mocImpl.target.toString()), 0);
          });
        });
      });
    });
    describe("WHEN alice enqueue a mintTP operation", function () {
      before(async function () {
        await baseSetup();
        await mocFunctions.mintTP({ from: alice, qTP: 1, execute: false });
      });
      describe("AND protocol is liquidated", function () {
        before(async function () {
          await liquidateProtocol();
        });
        describe("WHEN queue is executed", function () {
          it("THEN Operations fails with Unhandled Error", async function () {
            await expectLiquidatedEvent(mocMultiCollateralGuard.executeLiquidatedBucket(mocImpl.target.toString()));
            // tokens are returned
            assertPrec(await mocImpl.qACLockedInPending(), 0);
          });
        });
      });
    });
    describe("WHEN bob enqueue a redeemTP operation", function () {
      before(async function () {
        await baseSetup();
        await mocFunctions.redeemTP({ from: bob, qTP: 3, execute: false });
      });
      describe("AND protocol is liquidated", function () {
        before(async function () {
          await liquidateProtocol();
        });
        describe("WHEN queue is executed", function () {
          it("THEN Operations fails with Unhandled Error", async function () {
            await expectLiquidatedEvent(mocMultiCollateralGuard.executeLiquidatedBucket(mocImpl.target.toString()));
            // tokens are returned
            assertPrec(await mocFunctions.tpBalanceOf(0, mocImpl.target.toString()), 0);
          });
        });
      });
    });
    describe("WHEN bob enqueue a swapTPforTP operation", function () {
      before(async function () {
        await baseSetup();
        await mocFunctions.swapTPforTP({ iFrom: 0, iTo: 1, from: bob, qTP: 3, execute: false });
      });
      describe("AND protocol is liquidated", function () {
        before(async function () {
          await liquidateProtocol();
        });
        describe("WHEN queue is executed", function () {
          it("THEN Operations fails with Unhandled Error", async function () {
            await expectLiquidatedEvent(mocMultiCollateralGuard.executeLiquidatedBucket(mocImpl.target.toString()));
            // tokens are returned
            assertPrec(await mocFunctions.tpBalanceOf(0, mocImpl.target.toString()), 0);
          });
        });
      });
    });
    describe("WHEN bob enqueue a swapTPforTC operation", function () {
      before(async function () {
        await baseSetup();
        await mocFunctions.swapTPforTC({ from: bob, qTP: 3, execute: false });
      });
      describe("AND protocol is liquidated", function () {
        before(async function () {
          await liquidateProtocol();
        });
        describe("WHEN queue is executed", function () {
          it("THEN Operations fails with Unhandled Error", async function () {
            await expectLiquidatedEvent(mocMultiCollateralGuard.executeLiquidatedBucket(mocImpl.target.toString()));
            // tokens are returned
            assertPrec(await mocFunctions.tpBalanceOf(0, mocImpl.target.toString()), 0);
          });
        });
      });
    });
    describe("WHEN alice enqueue a swapTCforTP operation", function () {
      before(async function () {
        await baseSetup();
        await mocFunctions.swapTCforTP({ from: alice, qTC: 10, execute: false });
      });
      describe("AND protocol is liquidated", function () {
        before(async function () {
          await liquidateProtocol();
        });
        describe("WHEN queue is executed", function () {
          it("THEN Operations fails with Unhandled Error", async function () {
            await expectLiquidatedEvent(mocMultiCollateralGuard.executeLiquidatedBucket(mocImpl.target.toString()));
            // tokens are returned
            assertPrec(await mocFunctions.tcBalanceOf(mocImpl.target.toString()), 0);
          });
        });
      });
    });
    describe("WHEN bob enqueue a redeemTCandTP operation", function () {
      before(async function () {
        await baseSetup();
        // give TCs to bob
        await mocCollateralToken.connect(await ethers.getSigner(alice)).transfer(bob, pEth(10));
        await mocFunctions.redeemTCandTP({ from: bob, qTC: 10, qTP: 1, execute: false });
      });
      describe("AND protocol is liquidated", function () {
        before(async function () {
          await liquidateProtocol();
        });
        describe("WHEN queue is executed", function () {
          it("THEN Operations fails with Unhandled Error", async function () {
            await expectLiquidatedEvent(mocMultiCollateralGuard.executeLiquidatedBucket(mocImpl.target.toString()));
            // tokens are returned
            assertPrec(await mocFunctions.tcBalanceOf(mocImpl.target.toString()), 0);
            assertPrec(await mocFunctions.tpBalanceOf(0, mocImpl.target.toString()), 0);
          });
        });
      });
    });
    describe("WHEN alice enqueue a mintTCandTP operation", function () {
      before(async function () {
        await baseSetup();
        await mocFunctions.mintTCandTP({ from: alice, qTP: 3, execute: false });
      });
      describe("AND protocol is liquidated", function () {
        before(async function () {
          await liquidateProtocol();
        });
        describe("WHEN queue is executed", function () {
          it("THEN Operations fails with Unhandled Error", async function () {
            await expectLiquidatedEvent(mocMultiCollateralGuard.executeLiquidatedBucket(mocImpl.target.toString()));
            // tokens are returned
            assertPrec(await mocImpl.qACLockedInPending(), 0);
          });
        });
      });
    });
  });
};

export { shouldBehaveLikeLiquidable };
