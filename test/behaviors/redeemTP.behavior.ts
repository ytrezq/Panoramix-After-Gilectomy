import hre, { getNamedAccounts, ethers } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/dist/types";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../helpers/assertHelper";
import {
  Balance,
  CONSTANTS,
  ERRORS,
  expectEventFor,
  pEth,
  getNetworkDeployParams,
  finalFixturedDescribe,
  BaseSetupFunction,
  noVendor,
} from "../helpers/utils";
import { MocCACoinbase, MocCARC20 } from "../../typechain";

const redeemTPBehavior = function (setup: BaseSetupFunction) {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let alice: Address;
  let bob: Address;
  let vendor: Address;
  let expectEvent: any;
  let assertACResult: any;
  let tp0: Address;
  const TP_0 = 0;
  const TP_2 = 2;
  const {
    mocAddresses: { mocFeeFlowAddress },
    queueParams: {
      execCostParams: { tpRedeemExecCost },
    },
  } = getNetworkDeployParams(hre);

  describe("Feature: redeem Pegged Token", function () {
    async function baseSetup() {
      ({ mocContracts, mocFunctions } = await loadFixture(setup));
      ({ mocImpl } = mocContracts);
      ({ alice, bob, vendor } = await getNamedAccounts());
      expectEvent = expectEventFor(mocContracts, "TPRedeemed");
      assertACResult = mocFunctions.assertACResult(-tpRedeemExecCost);
      tp0 = mocContracts.mocPeggedTokens[TP_0].target.toString();
    }

    describe("GIVEN alice has 3000 TC, 23500 TP 0 and 93458 TP 2", function () {
      async function aliceHasDifferentTokeensSetup() {
        await loadFixture(baseSetup);
        await mocFunctions.mintTC({ from: alice, qTC: 3000 });
        await mocFunctions.mintTP({ i: TP_0, from: alice, qTP: 23500 });
        await mocFunctions.mintTP({ i: TP_2, from: alice, qTP: 93458 });
      }
      describe("AND TP price provider is deprecated", function () {
        before(async function () {
          await loadFixture(aliceHasDifferentTokeensSetup);
          await mocContracts.priceProviders[TP_0].deprecatePriceProvider();
        });
        describe("WHEN alice tries to redeem 23500 TP", function () {
          it("THEN tx reverts because invalid price provider", async function () {
            await expect(mocFunctions.redeemTP({ from: alice, qTP: 23500 })).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.MISSING_PROVIDER_PRICE,
            );
          });
        });
      });
      finalFixturedDescribe(aliceHasDifferentTokeensSetup, "WHEN alice tries to redeem a non-existent TP", function () {
        it("THEN tx reverts with invalid address", async function () {
          const fakeTP = mocContracts.mocCollateralToken;
          await expect(mocFunctions.redeemTP({ tp: fakeTP, from: alice, qTP: 100 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.INVALID_ADDRESS,
          );
        });
      });
      finalFixturedDescribe(aliceHasDifferentTokeensSetup, "WHEN alice tries to redeem 0 TP", function () {
        it("THEN tx reverts because the amount of TP is too low and out of precision", async function () {
          await expect(mocFunctions.redeemTP({ from: alice, qTP: 0 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.QAC_NEEDED_MUST_BE_GREATER_ZERO,
          );
        });
      });
      finalFixturedDescribe(
        aliceHasDifferentTokeensSetup,
        "WHEN alice tries to redeem 1 TP to the zero address",
        function () {
          it("THEN tx reverts because recipient is the zero address", async function () {
            await expect(mocFunctions.redeemTP({ from: alice, to: CONSTANTS.ZERO_ADDRESS, qTP: 1 })).to.be.reverted;
          });
        },
      );
      finalFixturedDescribe(aliceHasDifferentTokeensSetup, "WHEN alice tries to redeem 1 wei TP", function () {
        it("THEN tx reverts because the amount of TP is too low and out of precision", async function () {
          await expect(
            mocFunctions.redeemTP({ from: alice, qTP: 1n, applyPrecision: false }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.QAC_NEEDED_MUST_BE_GREATER_ZERO);
        });
      });
      finalFixturedDescribe(aliceHasDifferentTokeensSetup, "WHEN alice tries to redeem 23501 TP", function () {
        it("THEN tx reverts because there is not enough TP available to redeem", async function () {
          await expect(mocFunctions.redeemTP({ from: alice, qTP: 23501 })).to.be.reverted;
        });
      });
      describe("AND alice transfers 23400 TP to bob", function () {
        before(async function () {
          await loadFixture(aliceHasDifferentTokeensSetup);
          await mocFunctions.tpTransfer({ from: alice, to: bob, amount: 23400 });
        });
        describe("WHEN alice tries to redeem 101 TP", function () {
          it("THEN tx reverts because alice doesn't have that much TP", async function () {
            await expect(mocFunctions.redeemTP({ from: alice, qTP: 101 })).to.be.reverted;
          });
        });
      });
      finalFixturedDescribe(
        aliceHasDifferentTokeensSetup,
        "WHEN alice redeems 23500 TP expecting 101 Asset",
        function () {
          it("THEN tx reverts because Asset received is below the minimum required", async function () {
            await expect(mocFunctions.redeemTP({ from: alice, qTP: 23500, qACmin: 101 })).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.QAC_BELOW_MINIMUM,
            );
          });
        },
      );
      describe("WHEN alice redeems 23500 TP", function () {
        /*  
        nAC = 3100    
        nTP = 23500
        lckAC = 100
        ctarg = 5.54
        => TP available to redeem = 23500
        */
        let tx: ContractTransactionResponse;
        let alicePrevACBalance: Balance;
        let mocPrevACBalance: Balance;
        let mocFeeFlowPrevACBalance: Balance;
        before(async function () {
          await loadFixture(aliceHasDifferentTokeensSetup);
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          tx = await mocFunctions.redeemTP({ from: alice, qTP: 23500 });
        });
        it("THEN nACcb and nTP matches with AC balance and total supply", async function () {
          assertPrec(await mocImpl.nACcb(), await mocFunctions.acBalanceOf(mocImpl.target.toString()));
          assertPrec((await mocImpl.pegContainer(TP_0))[0], await mocContracts.mocPeggedTokens[TP_0].totalSupply());
        });
        it("THEN alice has 0 TP", async function () {
          assertPrec(0, await mocFunctions.tpBalanceOf(TP_0, alice));
        });
        it("THEN Moc balance decrease 100 AC", async function () {
          const mocActualACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          const diff = mocPrevACBalance - mocActualACBalance;
          assertPrec(100, diff);
        });
        it("THEN Moc Fee Flow balance increase 5% of 100 AC", async function () {
          const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
          assertPrec(100 * 0.05, diff);
        });
        it("THEN alice balance increase 100 Asset - 5% for Moc Fee Flow", async function () {
          const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
          const diff = aliceActualACBalance - alicePrevACBalance;
          assertACResult(95, diff);
        });
        it("THEN a TPRedeemed event is emitted", async function () {
          // i: 0
          // sender: alice
          // receiver: alice
          // qTP: 23500 TP
          // qAC: 100 AC - 5% for Moc Fee Flow
          // qACfee: 5% AC
          // qFeeToken: 0
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          const args = [tp0, alice, alice, pEth(23500), pEth(95), pEth(100 * 0.05), 0, 0, 0, noVendor];
          await expectEvent(tx, args);
        });
        it("THEN a Pegged Token Transfer event is emitted", async function () {
          // from: Moc
          // to: Zero Address
          // amount: 23500 TP
          await expect(tx)
            .to.emit(mocContracts.mocPeggedTokens[TP_0], "Transfer")
            .withArgs(mocImpl.target.toString(), CONSTANTS.ZERO_ADDRESS, pEth(23500));
        });
      });
      describe("WHEN alice redeems 2350 TP to bob", function () {
        /*  
        nAC = 3100    
        nTP = 2350
        lckAC = 100
        ctarg = 5.54
        => TP available to redeem = 23500
        */
        let tx: ContractTransactionResponse;
        let alicePrevTP0Balance: Balance;
        let bobPrevACBalance: Balance;
        let mocPrevACBalance: Balance;
        let mocFeeFlowPrevACBalance: Balance;
        before(async function () {
          await loadFixture(aliceHasDifferentTokeensSetup);
          alicePrevTP0Balance = await mocFunctions.tpBalanceOf(TP_0, alice);
          bobPrevACBalance = await mocFunctions.assetBalanceOf(bob);
          mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          tx = await mocFunctions.redeemTP({ from: alice, to: bob, qTP: 2350 });
        });
        it("THEN alice TP 0 balances decrease 2350 TP", async function () {
          const aliceActualTP0Balance = await mocFunctions.tpBalanceOf(TP_0, alice);
          const diff = alicePrevTP0Balance - aliceActualTP0Balance;
          assertPrec(2350, diff);
        });
        it("THEN Moc balance decrease 10 AC", async function () {
          const mocActualACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          const diff = mocPrevACBalance - mocActualACBalance;
          assertPrec(10, diff);
        });
        it("THEN Moc Fee Flow balance increase 5% of 10 AC", async function () {
          const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
          assertPrec(10 * 0.05, diff);
        });
        it("THEN bob balance increase 100 Asset - 5% for Moc Fee Flow", async function () {
          const bobActualACBalance = await mocFunctions.assetBalanceOf(bob);
          const diff = bobActualACBalance - bobPrevACBalance;
          assertPrec(9.5, diff);
        });
        it("THEN a TPRedeemed event is emitted", async function () {
          // i: 0
          // sender: alice
          // receiver: bob
          // qTP: 2350 TP
          // qAC: 10 AC - 5% for Moc Fee Flow
          // qACfee: 5% AC
          // qFeeToken: 0
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          const args = [tp0, alice, bob, pEth(2350), pEth(9.5), pEth(10 * 0.05), 0, 0, 0, noVendor];
          await expectEvent(tx, args);
        });
      });
      describe("WHEN alice redeems 23500 TP via vendor", function () {
        let alicePrevACBalance: Balance;
        let vendorPrevACBalance: Balance;
        let tx: ContractTransactionResponse;
        before(async function () {
          await loadFixture(aliceHasDifferentTokeensSetup);
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          vendorPrevACBalance = await mocFunctions.acBalanceOf(vendor);
          tx = await mocFunctions.redeemTP({ from: alice, qTP: 23500, vendor });
        });
        it("THEN alice AC balance increase 85 Asset (100 qAC - 5% qACFee - 10% qACVendorMarkup)", async function () {
          const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
          const diff = aliceActualACBalance - alicePrevACBalance;
          assertACResult(85, diff);
        });
        it("THEN vendor AC balance increase 10 Asset", async function () {
          const vendorActualACBalance = await mocFunctions.acBalanceOf(vendor);
          const diff = vendorActualACBalance - vendorPrevACBalance;
          assertPrec(10, diff);
        });
        it("THEN a TPRedeemed event is emitted", async function () {
          // i: 0
          // sender: alice
          // receiver: alice
          // qTP: 23500 TP
          // qAC: 100 AC - 5% for Moc Fee Flow - 10% for vendor
          // qACfee: 5% AC
          // qFeeToken: 0
          // qACVendorMarkup: 10% AC
          // qFeeTokenVendorMarkup: 0
          const args = [tp0, alice, alice, pEth(23500), pEth(85), pEth(5), 0, pEth(10), 0, vendor];
          await expectEvent(tx, args);
        });
      });
      describe("WHEN alice redeems 23500 TP to bob via vendor", function () {
        let tx: ContractTransactionResponse;
        before(async function () {
          await loadFixture(aliceHasDifferentTokeensSetup);
          tx = await mocFunctions.redeemTP({ from: alice, to: bob, qTP: 23500, vendor });
        });
        it("THEN a TPRedeemed event is emitted", async function () {
          // i: 0
          // sender: alice
          // receiver: bob
          // qTP: 23500 TP
          // qAC: 100 AC - 5% for Moc Fee Flow - 10% for vendor
          // qACfee: 5% AC
          // qFeeToken: 0
          // qACVendorMarkup: 10% AC
          // qFeeTokenVendorMarkup: 0
          const args = [tp0, alice, bob, pEth(23500), pEth(85), pEth(100 * 0.05), 0, pEth(100 * 0.1), 0, vendor];
          await expectEvent(tx, args);
        });
      });
      describe("AND TP 0 has been revaluated to 15.1", function () {
        /*  
        nAC = 3200    
        nTP0 = 23500
        nTP1 = 93458
        lckAC = 1556.29 + 100
        => coverage = 1.93 
        */
        before(async function () {
          await loadFixture(aliceHasDifferentTokeensSetup);
          await mocFunctions.pokePrice(TP_0, "15.1");
        });
        it("THEN the coverage is 1.93", async function () {
          assertPrec("1.932027189124350259", await mocImpl.getCglb());
        });
        describe("WHEN Alice tries to redeem 100 TP", function () {
          it("THEN tx reverts because coverage is below the protected threshold", async function () {
            await expect(mocFunctions.redeemTP({ from: alice, qTP: 100 })).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.LOW_COVERAGE,
            );
          });
        });
      });
      describe("AND TP 0 has been devaluated to 300", function () {
        /*  
          nAC = 3200    
          nTP0 = 23500 + 3250(tp gain)
          nTP1 = 93458
          lckAC = 78.33(tp 0) + 100(tp 1) + 10.835(tp gain)
          nACgain = 2.1666
          => coverage = 16.9
          => pTCac = 1.002
        */
        async function TP0DevaluatedTo300Setup() {
          await loadFixture(aliceHasDifferentTokeensSetup);
          await mocFunctions.pokePrice(TP_0, 300);
        }
        finalFixturedDescribe(TP0DevaluatedTo300Setup, "(Assertions)", function () {
          it("THEN the coverage is 16.9", async function () {
            assertPrec("16.904845814977973568", await mocImpl.getCglb());
          });
          it("THEN TC price is 1.002", async function () {
            assertPrec("1.002888888888888888", await mocImpl.getPTCac());
          });
        });
        describe("AND 3000 TP 0 are redeemed", function () {
          /*  
          nAC = 3190
          nTP0 = 23500 - 3000
          nTP1 = 93458
          iou = 21.66
          */
          let tx: ContractTransactionResponse;
          async function TP0RedeemedSetup() {
            await loadFixture(TP0DevaluatedTo300Setup);
            tx = await mocFunctions.redeemTP({ from: alice, qTP: 3000 });
          }
          finalFixturedDescribe(TP0RedeemedSetup, "(Assertions)", function () {
            it("THEN a TPRedeemed event is emitted", async function () {
              // i: 0
              // sender: alice
              // receiver: alice
              // qTP: 3000 TP
              // qAC: 10 AC - 5% for Moc Fee Flow
              // qACfee: 5% AC
              // qFeeToken: 0
              // qACVendorMarkup: 0
              // qFeeTokenVendorMarkup: 0
              const args = [tp0, alice, alice, pEth(3000), pEth(9.5), pEth(10 * 0.05), 0, 0, 0, noVendor];
              await expectEvent(tx, args);
            });
          });
          describe("AND Pegged Token has been devaluated to 1000", function () {
            /*  
            nAC = 3190    
            nTP = 20500 + 34750(tp gain)
            lckAC = 20.5(tp 0) + 100(tp 1) + 34.75(tp gain)
            nACgain = 2.1666(iou) + 4.7833(PnL)  
            => coverage = 20.5
            => pTCac = 1.0092
            */
            before(async function () {
              await loadFixture(TP0RedeemedSetup);
              await mocFunctions.pokePrice(TP_0, 1000);
            });
            it("THEN the coverage is 20.5", async function () {
              assertPrec("20.502737520128824476", await mocImpl.getCglb());
            });
            it("THEN TC price is 1.0092", async function () {
              assertPrec("1.009266666666666666", await mocImpl.getPTCac());
            });
          });
          describe("AND Pegged Token has been revaluated to 250", function () {
            /*  
            nAC = 3190    
            nTP = 20500 + 1000(tp gain)
            lckAC = 82(tp 0) + 100(tp 1) + 4(tp gain)
            nACgain = 2.1666(iou) - 1.36(PnL)  
            => coverage = 17.14
            => pTCac = 1.00106
            */
            before(async function () {
              await loadFixture(TP0RedeemedSetup);
              await mocFunctions.pokePrice(TP_0, 250);
            });
            it("THEN the coverage is 17.14", async function () {
              assertPrec("17.146236559139784946", await mocImpl.getCglb());
            });
            it("THEN TC price is 1.00106", async function () {
              assertPrec("1.001066666666666666", await mocImpl.getPTCac());
            });
          });
        });
      });
      describe("AND TP 0 has been revaluated to 100", function () {
        /*  
          nAC = 3200    
          nTP0 = 23500 + 0(tp gain)
          nTP1 = 93458
          lckAC = 235(tp 0) + 100(tp 1) + 0(tp gain)          
          nACgain = 0
          => coverage = 9.55
          => pTCac = 0.955
        */
        async function revaluatedTPTo100Setup() {
          await loadFixture(aliceHasDifferentTokeensSetup);
          await mocFunctions.pokePrice(TP_0, 100);
        }
        finalFixturedDescribe(revaluatedTPTo100Setup, "(Assertions)", function () {
          it("THEN the coverage is 9.55", async function () {
            assertPrec("9.552238805970149253", await mocImpl.getCglb());
          });
          it("THEN TC price is 0.955", async function () {
            assertPrec(0.955, await mocImpl.getPTCac());
          });
        });
        describe("AND 1000 TP 0 are redeemed", function () {
          /*  
          nAC = 3190    
          nTP0 = 22500 - 1000
          nTP1 = 93458
          iou = -135
          */
          let tx: ContractTransactionResponse;
          async function TP0RedeemedSetup() {
            await loadFixture(revaluatedTPTo100Setup);
            tx = await mocFunctions.redeemTP({ from: alice, qTP: 1000 });
          }
          finalFixturedDescribe(TP0RedeemedSetup, "(Assertions)", function () {
            it("THEN a TPRedeemed event is emitted", async function () {
              // i: 0
              // sender: alice
              // receiver: alice
              // qTP: 1000 TP
              // qAC: 10 AC - 5% for Moc Fee Flow
              // qACfee: 5% AC
              // qFeeToken: 0
              // qACVendorMarkup: 0
              // qFeeTokenVendorMarkup: 0
              const args = [tp0, alice, alice, pEth(1000), pEth(9.5), pEth(10 * 0.05), 0, 0, 0, noVendor];
              await expectEvent(tx, args);
            });
          });
          describe("AND Pegged Token has been devaluated to 1000", function () {
            /*  
            nAC = 3190    
            nTP0 = 22500 + 3375(tp gain)
            nTP1 = 93458
            lckAC = 22.5(tp 0) + 100(tp 1) + 33.75(tp gain)          
            nACgain = -13.5(iou) + 20.25(PnL)  
            => coverage = 20.37
            => pTCac = 1.009
            */
            before(async function () {
              await loadFixture(TP0RedeemedSetup);
              await mocFunctions.pokePrice(TP_0, 1000);
            });
            it("THEN the coverage is 20.37", async function () {
              assertPrec("20.372800000000000000", await mocImpl.getCglb());
            });
            it("THEN TC price is 1.009", async function () {
              assertPrec("1.009", await mocImpl.getPTCac());
            });
          });
        });
      });
      describe("AND Pegged Token has been revaluated making lckAC bigger than total AC in the protocol", function () {
        // this test is to check that tx doesn't fail because underflow doing totalACAvailable - lckAC
        before(async function () {
          await loadFixture(aliceHasDifferentTokeensSetup);
          await mocFunctions.pokePrice(TP_0, "0.00000001");
        });
        it("THEN tx reverts because coverage is below the protected threshold", async function () {
          expect((await mocImpl.getCglb()) < pEth(1)); // check that lckAC > totalACAvailable
          await expect(mocFunctions.redeemTP({ from: alice, qTP: 100 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.LOW_COVERAGE,
          );
        });
      });
      describe("AND alice has FeeToken to pay fees", function () {
        let alicePrevFeeTokenBalance: Balance;
        let mocFeeFlowPrevACBalance: Balance;
        let mocFeeFlowPrevFeeTokenBalance: Balance;
        let tx: ContractTransactionResponse;
        async function aliceHasTokenFeesSetup() {
          await loadFixture(aliceHasDifferentTokeensSetup);
          // mint FeeToken to alice
          await mocContracts.feeToken.mint(alice, pEth(50));
          await mocContracts.feeToken
            .connect(await ethers.getSigner(alice))
            .approve(mocImpl.target.toString(), pEth(50));

          // initialize previous balances
          alicePrevFeeTokenBalance = await mocContracts.feeToken.balanceOf(alice);
          mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          mocFeeFlowPrevFeeTokenBalance = await mocContracts.feeToken.balanceOf(mocFeeFlowAddress);
        }
        describe("WHEN alice redeems 23500 TP", function () {
          let alicePrevACBalance: Balance;
          before(async function () {
            await loadFixture(aliceHasTokenFeesSetup);
            alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
            tx = await mocFunctions.redeemTP({ from: alice, qTP: 23500 });
          });
          it("THEN alice AC balance increase 100 Asset", async function () {
            const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
            const diff = aliceActualACBalance - alicePrevACBalance;
            assertACResult(100, diff);
          });
          it("THEN alice Fee Token balance decrease 2.5 (100 * 5% * 50%)", async function () {
            const aliceActualFeeTokenBalance = await mocContracts.feeToken.balanceOf(alice);
            const diff = alicePrevFeeTokenBalance - aliceActualFeeTokenBalance;
            assertPrec(2.5, diff);
          });
          it("THEN Moc Fee Flow AC balance doesn't change", async function () {
            const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
            assertPrec(mocFeeFlowActualACBalance, mocFeeFlowPrevACBalance);
          });
          it("THEN Moc Fee Flow Fee Token balance increase 2.5 (100 * 5% * 50%)", async function () {
            const mocFeeFlowActualFeeTokenBalance = await mocContracts.feeToken.balanceOf(mocFeeFlowAddress);
            const diff = mocFeeFlowActualFeeTokenBalance - mocFeeFlowPrevFeeTokenBalance;
            assertPrec(2.5, diff);
          });
          it("THEN Fee Token is used as fee payment method", async function () {
            // i: 0
            // sender: alice
            // receiver: alice
            // qTP: 23500 TP
            // qAC: 100 AC
            // qACfee: 0 AC
            // qFeeToken: 100 (5% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const args = [tp0, alice, alice, pEth(23500), pEth(100), 0, pEth(100 * 0.05 * 0.5), 0, 0, noVendor];
            await expectEvent(tx, args);
          });
        });
        describe("WHEN alice redeems 23500 TP to bob", function () {
          let bobPrevACBalance: Balance;
          before(async function () {
            await loadFixture(aliceHasTokenFeesSetup);
            bobPrevACBalance = await mocFunctions.assetBalanceOf(bob);
            tx = await mocFunctions.redeemTP({ from: alice, to: bob, qTP: 23500 });
          });
          it("THEN bob AC balance increase 100 Asset", async function () {
            const bobActualACBalance = await mocFunctions.assetBalanceOf(bob);
            const diff = bobActualACBalance - bobPrevACBalance;
            assertPrec(100, diff);
          });
          it("THEN alice Fee Token balance decrease 2.5 (100 * 5% * 50%)", async function () {
            const aliceActualFeeTokenBalance = await mocContracts.feeToken.balanceOf(alice);
            const diff = alicePrevFeeTokenBalance - aliceActualFeeTokenBalance;
            assertPrec(2.5, diff);
          });
          it("THEN Moc Fee Flow AC balance doesn't change", async function () {
            const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
            assertPrec(mocFeeFlowActualACBalance, mocFeeFlowPrevACBalance);
          });
          it("THEN Moc Fee Flow Fee Token balance increase 2.5 (100 * 5% * 50%)", async function () {
            const mocFeeFlowActualFeeTokenBalance = await mocContracts.feeToken.balanceOf(mocFeeFlowAddress);
            const diff = mocFeeFlowActualFeeTokenBalance - mocFeeFlowPrevFeeTokenBalance;
            assertPrec(2.5, diff);
          });
          it("THEN Fee Token is used as fee payment method", async function () {
            // 0
            // sender: alice
            // receiver: bob
            // qTP: 23500 TP
            // qAC: 100 AC
            // qACfee: 0 AC
            // qFeeToken: 100 (5% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const args = [tp0, alice, bob, pEth(23500), pEth(100), 0, pEth(100 * 0.05 * 0.5), 0, 0, noVendor];
            await expectEvent(tx, args);
          });
        });
      });
    });
  });
};

export { redeemTPBehavior };
