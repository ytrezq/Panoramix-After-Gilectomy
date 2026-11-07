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
  time,
  pEth,
  getNetworkDeployParams,
  finalFixturedDescribe,
  BaseSetupFunction,
  noVendor,
} from "../helpers/utils";
import { MocCACoinbase, MocCARC20 } from "../../typechain";

const mintTPBehavior = function (setup: BaseSetupFunction) {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let deployer: Address;
  let alice: Address;
  let bob: Address;
  let vendor: Address;
  let expectEvent: any;
  let assertACResult: any;
  let tp0: Address;

  const TP_0 = 0;
  const TP_1 = 1;
  const TP_4 = 4;
  const {
    mocAddresses: { mocFeeFlowAddress },
    queueParams: {
      execCostParams: { tpMintExecCost },
    },
  } = getNetworkDeployParams(hre);

  // Available to mint formulas introduce rounding errors, so we tolerate some margin for it
  const availableToMintTolerance = 20000;

  describe("Feature: mint Pegged Token", function () {
    async function mintPeggedBaseSetup() {
      const a = await loadFixture(setup);
      mocContracts = a.mocContracts;
      mocFunctions = a.mocFunctions;
      ({ mocImpl } = mocContracts);
      ({ deployer, alice, bob, vendor } = await getNamedAccounts());
      expectEvent = expectEventFor(mocContracts, "TPMinted");
      assertACResult = mocFunctions.assertACResult(tpMintExecCost);
      tp0 = mocContracts.mocPeggedTokens[TP_0].target.toString();
    }
    finalFixturedDescribe(mintPeggedBaseSetup, "WHEN alice trie to mint 0 TP", function () {
      it("THEN tx reverts because the amount of TP is too low and out of precision", async function () {
        await expect(mocFunctions.mintTP({ from: alice, qTP: 0 })).to.be.revertedWithCustomError(
          mocImpl,
          ERRORS.QAC_NEEDED_MUST_BE_GREATER_ZERO,
        );
      });
    });
    finalFixturedDescribe(
      mintPeggedBaseSetup,
      "WHEN alice sends 100 Asset to mint 100 TP but there is not collateral in the protocol",
      function () {
        it("THEN tx reverts because there is not enough TP to mint", async function () {
          await expect(mocFunctions.mintTP({ from: alice, qTP: 100 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.INSUFFICIENT_TP_TO_MINT,
          );
        });
      },
    );
    describe("GIVEN 3000 Asset as collateral in the protocol", function () {
      /*  
        nAC = 3000    
        nTP = 0
        lckAC = 0
        ctargemaCA = 4 (because there are not any TP in the bucket)
        ctargemaTP = 5.54
        => TP available to mint = 169632.000000000000020000
        */
      async function collateralizedProtocolSetup() {
        await mintPeggedBaseSetup();
        await mocFunctions.mintTC({ from: deployer, qTC: 3000 });
      }
      describe("AND TP price provider is deprecated", function () {
        async function tpPriceProviderDeprecatedSetup() {
          await loadFixture(collateralizedProtocolSetup);
          await mocContracts.priceProviders[TP_0].deprecatePriceProvider();
        }
        finalFixturedDescribe(tpPriceProviderDeprecatedSetup, "WHEN alice tries to mint 23500 TP", function () {
          it("THEN tx reverts because invalid price provider", async function () {
            await expect(mocFunctions.mintTP({ from: alice, qTP: 23500 })).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.MISSING_PROVIDER_PRICE,
            );
          });
        });
      });
      finalFixturedDescribe(collateralizedProtocolSetup, "WHEN alice tries to mint a non-existent TP", function () {
        it("THEN tx reverts", async function () {
          await expect(mocFunctions.mintTP({ tp: alice, from: alice, qTP: 100 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.INVALID_ADDRESS,
          );
        });
      });
      finalFixturedDescribe(
        collateralizedProtocolSetup,
        "WHEN alice sends 100 Asset to mint 100 TP to the zero address",
        function () {
          it("THEN tx reverts because recipient is the zero address", async function () {
            await expect(mocFunctions.mintTP({ from: alice, to: CONSTANTS.ZERO_ADDRESS, qTP: 100 })).to.be.revertedWith(
              ERRORS.ERC20_MINT_TO_ZERO_ADDRESS,
            );
          });
        },
      );

      finalFixturedDescribe(
        collateralizedProtocolSetup,
        "WHEN alice sends 100 Asset to mint 100 TP to the zero address",
        function () {
          it("THEN tx reverts because recipient is the zero address", async function () {
            await expect(mocFunctions.mintTP({ from: alice, to: CONSTANTS.ZERO_ADDRESS, qTP: 100 })).to.be.revertedWith(
              ERRORS.ERC20_MINT_TO_ZERO_ADDRESS,
            );
          });
        },
      );
      finalFixturedDescribe(collateralizedProtocolSetup, "WHEN alice tries to mint 1 wei TP", function () {
        it("THEN tx reverts because the amount of TP is too low and out of precision", async function () {
          await expect(
            mocFunctions.mintTP({ from: alice, qTP: 1n, applyPrecision: false }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.QAC_NEEDED_MUST_BE_GREATER_ZERO);
        });
      });
      finalFixturedDescribe(collateralizedProtocolSetup, "WHEN alice sends 0.4 Asset to mint 100 TP", function () {
        // TP price: 235 => 100TP = 0.4255 Assets
        it("THEN tx reverts because the amount of AC is insufficient", async function () {
          await expect(mocFunctions.mintTP({ from: alice, qTP: 100, qACmax: 0.4 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.INSUFFICIENT_QAC_SENT,
          );
        });
      });
      describe("WHEN alice sends 105(exactly amount) Asset to mint 23500 TP", function () {
        let tx: ContractTransactionResponse;
        let alicePrevACBalance: Balance;
        let mocPrevACBalance: Balance;
        let mocFeeFlowPrevACBalance: Balance;
        async function mintTPWithExactAmountSetup() {
          await loadFixture(collateralizedProtocolSetup);
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          tx = await mocFunctions.mintTP({ from: alice, qTP: 23500, qACmax: 105 });
        }
        finalFixturedDescribe(mintTPWithExactAmountSetup, "(Assertions)", async function () {
          it("THEN nACcb and nTP matches with AC balance and total supply", async function () {
            assertPrec(await mocImpl.nACcb(), await mocFunctions.acBalanceOf(mocImpl.target.toString()));
            assertPrec((await mocImpl.pegContainer(TP_0))[0], await mocContracts.mocPeggedTokens[TP_0].totalSupply());
          });
          it("THEN alice receives 23500 TP", async function () {
            assertPrec(23500, await mocFunctions.tpBalanceOf(TP_0, alice));
          });
          it("THEN Moc balance increase 100 AC", async function () {
            const mocActualACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
            const diff = mocActualACBalance - mocPrevACBalance;
            assertPrec(100, diff);
          });
          it("THEN Moc Fee Flow balance increase 5% of 100 AC", async function () {
            const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
            const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
            assertPrec(100 * 0.05, diff);
          });
          it("THEN alice balance decrease 100 Asset + 5% for Moc Fee Flow", async function () {
            const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
            const diff = alicePrevACBalance - aliceActualACBalance;
            assertACResult(100 * 1.05, diff);
          });
          it("THEN a TPMinted event is emitted", async function () {
            // tp: 0
            // sender: alice
            // receiver: alice
            // qTP: 23500 TP
            // qAC: 100 AC + 5% for Moc Fee Flow
            // qACfee: 5% AC
            // qFeeToken: 0
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const args = [tp0, alice, alice, pEth(23500), pEth(100 * 1.05), pEth(100 * 0.05), 0, 0, 0, noVendor];
            await expectEvent(tx, args);
          });
          it("THEN a Pegged Token Transfer event is emitted", async function () {
            // from: Zero Address
            // to: alice
            // amount: 23500 TP
            await expect(tx)
              .to.emit(mocContracts.mocPeggedTokens[TP_0], "Transfer")
              .withArgs(CONSTANTS.ZERO_ADDRESS, alice, pEth(23500));
          });
          it("THEN now there are 131738.22 TP available to mint", async function () {
            assertPrec("131738.223809919415159579", await mocImpl.getTPAvailableToMint(tp0));
          });
          it("THEN tx reverts because there is not enough TP to mint if alice tries to mint 131738.23 TP more", async function () {
            /*  
            nAC = 3100    
            nTP = 23500
            lckAC = 100
            ctargemaCA = 5.54
            ctargemaTP = 5.54
            => TP available to mint = 131738.22
            */
            await expect(mocFunctions.mintTP({ from: alice, qTP: "131738.23" })).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.INSUFFICIENT_TP_TO_MINT,
            );
          });
        });
        async function maxTPMintedSetup() {
          await mintTPWithExactAmountSetup();
          await mocFunctions.mintTP({ from: deployer, qTP: "131738.223809919415159579" });
        }
        finalFixturedDescribe(maxTPMintedSetup, "AND max amount of TP 0 available are minted", async function () {
          it("THEN coverage is still above ctargemaCA", async function () {
            const actualCoverage = await mocImpl.getCglb();
            const actualCtargemaCA = await mocImpl.getCtargemaCA();
            expect(actualCoverage).to.be.greaterThanOrEqual(actualCtargemaCA);
          });
          it("THEN there are 0 TP 0 and TP 1 available to mint", async function () {
            assertPrec(0, await mocImpl.getTPAvailableToMint(tp0), "TP 0", availableToMintTolerance);
            const tp1 = mocContracts.mocPeggedTokens[TP_1].target.toString();
            assertPrec(0, await mocImpl.getTPAvailableToMint(tp1), "TP 1");
          });
        });
      });
      describe("AND alice sends 2350000(exceeded amount) Asset to mint 23500 TP", function () {
        /*  
            nAC = 3100    
            nTP = 23500
            lckAC = 100
            ctargemaTP = 5.54
            => TP available to mint = 131738.2238
          */
        let alicePrevACBalance: Balance;
        let alicePrevTPBalance: Balance;
        let mocPrevACBalance: Balance;
        let mocFeeFlowPrevACBalance: Balance;
        before(async function () {
          await loadFixture(collateralizedProtocolSetup);
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          alicePrevTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
          mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          await mocFunctions.mintTP({ from: alice, qTP: 23500 });
        });
        it("THEN alice receives 23500 TP", async function () {
          const aliceActualTPBalance = await mocFunctions.tpBalanceOf(TP_0, alice);
          const diff = aliceActualTPBalance - alicePrevTPBalance;
          assertPrec(23500, diff);
        });
        it("THEN Moc balance increase 100 AC", async function () {
          const mocActualACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          const diff = mocActualACBalance - mocPrevACBalance;
          assertPrec(100, diff);
        });
        it("THEN Moc Fee Flow balance increase 5% of 100 AC", async function () {
          const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
          assertPrec(100 * 0.05, diff);
        });
        it("THEN alice balance decrease 100 Asset + 5% for Moc Fee Flow", async function () {
          const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
          const diff = alicePrevACBalance - aliceActualACBalance;
          assertACResult(100 * 1.05, diff);
        });
      });
      describe("WHEN alice sends 105 Asset to mint 23500 TP to bob", function () {
        /*  
          nAC = 3100    
          nTP = 23500
          lckAC = 100
          ctargemaCA = 5.54
          ctargemaTP = 5.54
          => TP available to mint = 131738.22
        */
        let tx: ContractTransactionResponse;
        let alicePrevACBalance: Balance;
        let mocPrevACBalance: Balance;
        let mocFeeFlowPrevACBalance: Balance;
        before(async function () {
          await loadFixture(collateralizedProtocolSetup);
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          tx = await mocFunctions.mintTP({ from: alice, to: bob, qTP: 23500 });
        });
        it("THEN bob receives 23500 TP", async function () {
          assertPrec(23500, await mocFunctions.tpBalanceOf(TP_0, bob));
        });
        it("THEN Moc balance increase 100 AC", async function () {
          const mocActualACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          const diff = mocActualACBalance - mocPrevACBalance;
          assertPrec(100, diff);
        });
        it("THEN Moc Fee Flow balance increase 5% of 100 AC", async function () {
          const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
          assertPrec(100 * 0.05, diff);
        });
        it("THEN alice balance decrease 100 Asset + 5% for Moc Fee Flow", async function () {
          const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
          const diff = alicePrevACBalance - aliceActualACBalance;
          assertACResult(100 * 1.05, diff);
        });
        it("THEN a TPMinted event is emitted", async function () {
          // tp: 0
          // sender: alice
          // receiver: bob
          // qTP: 23500 TP
          // qAC: 100 AC + 5% for Moc Fee Flow
          // qACfee: 5% AC
          // qFeeToken: 0
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          const args = [tp0, alice, bob, pEth(23500), pEth(100 * 1.05), pEth(100 * 0.05), 0, 0, 0, noVendor];
          await expectEvent(tx, args);
        });
      });
      describe("WHEN alice mints 23500 TP via vendor", function () {
        let alicePrevACBalance: Balance;
        let vendorPrevACBalance: Balance;
        let tx: ContractTransactionResponse;
        before(async function () {
          await loadFixture(collateralizedProtocolSetup);
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          vendorPrevACBalance = await mocFunctions.acBalanceOf(vendor);
          tx = await mocFunctions.mintTP({ from: alice, qTP: 23500, vendor });
        });
        it("THEN alice AC balance decrease 115 Asset (100 qAC + 5% qACFee + 10% qACVendorMarkup)", async function () {
          const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
          const diff = alicePrevACBalance - aliceActualACBalance;
          assertACResult(115, diff);
        });
        it("THEN vendor AC balance increase 10 Asset", async function () {
          const vendorActualACBalance = await mocFunctions.acBalanceOf(vendor);
          const diff = vendorActualACBalance - vendorPrevACBalance;
          assertPrec(10, diff);
        });
        it("THEN a TPMinted event is emitted", async function () {
          // i : 0
          // sender: alice
          // receiver: alice
          // qTP: 23500
          // qAC: 100 AC + 5% for Moc Fee Flow + 10% for vendor
          // qACfee: 5% qAC
          // qFeeToken: 0
          // qACVendorMarkup: 10% qAC
          // qFeeTokenVendorMarkup: 0
          const args = [tp0, alice, alice, pEth(23500), pEth(100 * 1.15), pEth(100 * 0.05), 0, pEth(10), 0, vendor];
          await expectEvent(tx, args);
        });
      });
      describe("WHEN alice mints 23500 TP to bob via vendor", function () {
        let tx: ContractTransactionResponse;
        before(async function () {
          await loadFixture(collateralizedProtocolSetup);
          tx = await mocFunctions.mintTP({ from: alice, to: bob, qTP: 23500, vendor });
        });
        it("THEN a TPMinted event is emitted", async function () {
          // i : 0
          // sender: alice
          // receiver: bob
          // qTP: 2350 TP
          // qAC: 100 AC + 5% for Moc Fee Flow + 10% for vendor
          // qACfee: 5% qAC
          // qFeeToken: 0
          // qACVendorMarkup: 10% qAC
          // qFeeTokenVendorMarkup: 0
          const args = [tp0, alice, bob, pEth(23500), pEth(100 * 1.15), pEth(100 * 0.05), 0, pEth(10), 0, vendor];
          await expectEvent(tx, args);
        });
      });
      describe("AND 23500 TP0 are minted", function () {
        async function tp0MintedSetup() {
          await loadFixture(collateralizedProtocolSetup);

          await mocFunctions.mintTP({ from: deployer, qTP: 23500 });
        }
        describe("AND Pegged Token has been revaluated to 37.9", function () {
          /*  
            nAC = 3100    
            nTP = 23500
            lckAC = 620
            => coverage = 5 
          */
          before(async function () {
            await loadFixture(tp0MintedSetup);
            await mocFunctions.pokePrice(TP_0, "37.9");
          });
          it("THEN the coverage is 5", async function () {
            assertPrec("4.999574468085106382", await mocImpl.getCglb());
          });
          it("THEN the are -2.5 TP 0 available to mint", async function () {
            assertPrec("-2.5", await mocImpl.getTPAvailableToMint(tp0), undefined, availableToMintTolerance);
          });
          describe("WHEN Alice tries to mint 1 TP", function () {
            it("THEN tx reverts because coverage is below the target coverage adjusted by the moving average", async function () {
              await expect(mocFunctions.mintTP({ from: alice, qTP: 1 })).to.be.revertedWithCustomError(
                mocImpl,
                ERRORS.LOW_COVERAGE,
              );
            });
          });
        });
        describe("AND Pegged Token has been revaluated to 38, so there are 75 TP0 available to mint", function () {
          /*  
            nAC = 3100    
            nTP = 23500
            lckAC = 618
            ctargemaCA = 5
            ctargemaTP = 5
            => TP available to mint = 75
          */
          before(async function () {
            await loadFixture(tp0MintedSetup);
            await mocFunctions.pokePrice(TP_0, 38);
          });
          it("THEN there are 75 TP available to mint", async function () {
            assertPrec("75.000000000000000020", await mocImpl.getTPAvailableToMint(tp0));
          });
          describe("WHEN Alice tries to mint 75.1 TP", function () {
            it("THEN tx reverts because there is not enough TP to mint", async function () {
              await expect(mocFunctions.mintTP({ from: alice, qTP: 75.1 })).to.be.revertedWithCustomError(
                mocImpl,
                ERRORS.INSUFFICIENT_TP_TO_MINT,
              );
            });
          });
        });
        describe("AND Pegged Token has been devaluated to 300", function () {
          /*  
            nAC = 3100    
            nTP = 23500 + 3250(tp gain)
            lckAC = 78.33 + 10.835(tp gain)
            nACgain = 2.1666
            ctargemaCA = 7.07
            ctargemaTP = 7.07
            => TP available to mint = 121847.2421
            => coverage = 34.74
            => pTCac = 1.002
          */
          async function pokePriceSetup() {
            await loadFixture(tp0MintedSetup);
            await mocFunctions.pokePrice(TP_0, 300);
          }
          finalFixturedDescribe(pokePriceSetup, "(Assertions)", function () {
            it("THEN there are 121847.2421 TP available to mint", async function () {
              assertPrec("121847.242150377340925125", await mocImpl.getTPAvailableToMint(tp0));
            });
            it("THEN the coverage is 34.74", async function () {
              assertPrec("34.742056074766355140", await mocImpl.getCglb());
            });
            it("THEN TC price is 1.002", async function () {
              assertPrec("1.002888888888888888", await mocImpl.getPTCac());
            });
          });
          describe("AND EMA is updated", function () {
            /*
            ctargemaCA = 6.93
            ctargemaTP = 6.93
            => TP available to mint = 125449.0669
            */
            before(async function () {
              await loadFixture(pokePriceSetup);
              await time.increaseTo(await mocImpl.nextEmaCalculation());
              await mocImpl.updateEmas();
            });
            it("THEN there are 125449.0669 TP available to mint", async function () {
              assertPrec("125449.066971443529804161", await mocImpl.getTPAvailableToMint(tp0));
            });
          });
          describe("AND 3000 TP 0 are minted", function () {
            /*  
            nAC = 3110    
            nTP = 23500 + 3000
            iou = 21.66
            */
            let tx: ContractTransactionResponse;

            async function tp0MintedSetup() {
              await loadFixture(pokePriceSetup);
              tx = await mocFunctions.mintTP({ from: deployer, qTP: 3000 });
            }
            finalFixturedDescribe(tp0MintedSetup, "(Assertions)", async function () {
              it("THEN a TPMinted event is emitted", async function () {
                // tp: 0
                // sender: deployer
                // receiver: deployer
                // qTP: 3000 TP
                // qAC: 10 AC + 5% for Moc Fee Flow
                // qACfee: 5% AC
                // qFeeToken: 0
                // qACVendorMarkup: 0
                // qFeeTokenVendorMarkup: 0
                const args = [tp0, deployer, deployer, pEth(3000), pEth(10 * 1.05), pEth(10 * 0.05), 0, 0, 0, noVendor];
                await expectEvent(tx, args);
              });
            });
            describe("AND Pegged Token has been devaluated to 1000", function () {
              /*  
              nAC = 3110    
              nTP = 26500 + 41750(tp gain)
              lckAC = 26.5 + 41.75(tp gain)
              nACgain = 2.1666(iou) + 6.18(PnL)  
              ctargemaCA = 23.58
              ctargemaTP = 23.58
              => TP available to mint = 66087.4
              => coverage = 45.44
              => pTCac = 1.011
              */
              async function devaluatedTPSetup() {
                await loadFixture(tp0MintedSetup);
                await mocFunctions.pokePrice(TP_0, 1000);
              }
              finalFixturedDescribe(devaluatedTPSetup, "(Assertions)", async function () {
                it("THEN there are 66087.4 TP available to mint", async function () {
                  assertPrec("66087.407998395976575724", await mocImpl.getTPAvailableToMint(tp0));
                });
                it("THEN the coverage is 45.44", async function () {
                  assertPrec("45.445421245421245421", await mocImpl.getCglb());
                });
                it("THEN TC price is 1.011", async function () {
                  assertPrec("1.011133333333333333", await mocImpl.getPTCac());
                });
              });
              describe("AND EMA is updated", function () {
                /*
                ctargemaCA = 19.88
                ctargemaTP = 19.88
                => TP available to mint = 92369.57
                */
                before(async function () {
                  await loadFixture(devaluatedTPSetup);
                  await time.increaseTo(await mocImpl.nextEmaCalculation());
                  await mocImpl.updateEmas();
                });
                it("THEN there are 92369.57 TP available to mint", async function () {
                  assertPrec("92369.578979910128584434", await mocImpl.getTPAvailableToMint(tp0));
                });
              });
            });
            describe("AND Pegged Token has been revaluated to 250", function () {
              /*  
              nAC = 3110    
              nTP = 26500 + 500(tp gain)
              lckAC = 106 + 2(tp gain)
              nACgain = 2.1666(iou) - 1.76(PnL)  
              ctargemaCA = 5.89
              ctargemaTP = 5.89
              => TP available to mint = 126295.71
              => coverage = 28.79
              => pTCac = 1.000533 
              */
              async function revaluatedTPSetup() {
                await loadFixture(tp0MintedSetup);
                await mocFunctions.pokePrice(TP_0, 250);
              }
              finalFixturedDescribe(revaluatedTPSetup, "(Assertions)", async function () {
                it("THEN there are 126295.71 TP available to mint", async function () {
                  assertPrec("126295.710817372538465788", await mocImpl.getTPAvailableToMint(tp0));
                });
                it("THEN the coverage is 28.79", async function () {
                  assertPrec("28.792592592592592592", await mocImpl.getCglb());
                });
                it("THEN TC price is 1.000533", async function () {
                  assertPrec("1.000533333333333333", await mocImpl.getPTCac());
                });
              });
              describe("AND EMA is updated", function () {
                /*
                ctargemaCA = 5.84
                ctargemaTP = 5.84
                => TP available to mint = 127951.22
                */
                before(async function () {
                  await loadFixture(revaluatedTPSetup);
                  await time.increaseTo(await mocImpl.nextEmaCalculation());
                  await mocImpl.updateEmas();
                });
                it("THEN there are 127951.22 TP available to mint", async function () {
                  assertPrec("127951.224154539014099053", await mocImpl.getTPAvailableToMint(tp0));
                });
              });
            });
          });
        });

        describe("AND Pegged Token has been revaluated to 100", function () {
          /*
            nAC = 3100
            nTP = 23500 + 0(tp gain)
            lckAC = 235 + 0(tp gain)
            nACgain = 0
            ctargemaCA = 5
            ctargemaTP = 5
            => TP available to mint = 48125
            => coverage = 13.19
            => pTCac = 0.955
          */
          async function revaluatedTo100TPSetup() {
            await loadFixture(tp0MintedSetup);
            await mocFunctions.pokePrice(TP_0, 100);
          }
          finalFixturedDescribe(revaluatedTo100TPSetup, "(Assertions)", async function () {
            it("THEN there are 48125 TP available to mint", async function () {
              assertPrec(48125, await mocImpl.getTPAvailableToMint(tp0));
            });
            it("THEN the coverage is 13.19", async function () {
              assertPrec("13.191489361702127659", await mocImpl.getCglb());
            });
            it("THEN TC price is 0.955", async function () {
              assertPrec(0.955, await mocImpl.getPTCac());
            });
          });
          describe("AND EMA is updated", function () {
            /*
              ctargemaCA = 5
              ctargemaTP = 5
              => TP available to mint = 48125
              */
            before(async function () {
              await loadFixture(revaluatedTo100TPSetup);
              await time.increaseTo(await mocImpl.nextEmaCalculation());
              await mocImpl.updateEmas();
            });
            it("THEN there are 48125 TP available to mint", async function () {
              assertPrec(48125, await mocImpl.getTPAvailableToMint(tp0));
            });
          });
          describe("AND 1000 TP are minted", function () {
            /*
              nAC = 3110
            nTP = 23500 + 1000
            iou = -135
            */
            let tx: ContractTransactionResponse;
            async function tpMinted1000Setup() {
              await loadFixture(revaluatedTo100TPSetup);
              tx = await mocFunctions.mintTP({ from: deployer, qTP: 1000 });
            }
            finalFixturedDescribe(tpMinted1000Setup, "(Assertions)", async function () {
              it("THEN a TPMinted event is emitted", async function () {
                // tp: 0
                // sender: deployer
                // receiver: deployer
                // qTP: 1000 TP
                // qAC: 10 AC + 5% for Moc Fee Flow
                // qACfee: 5% AC
                // qFeeToken: 0
                // qACVendorMarkup: 0
                // qFeeTokenVendorMarkup: 0
                const args = [tp0, deployer, deployer, pEth(1000), pEth(10 * 1.05), pEth(10 * 0.05), 0, 0, 0, noVendor];
                await expectEvent(tx, args);
              });
            });
            describe("AND Pegged Token has been devaluated to 1000", function () {
              /*
              nAC = 3110
              nTP = 24500 + 4275(tp gain)
              lckAC = 24.5 + 42.75(tp gain)
              nACgain = -13.5(iou) + 22.05(PnL)
              ctargemaCA = 23.58
              ctargemaTP = 23.58
              => TP available to mint = 67122.83
              => coverage = 46.11
              => pTCac = 1.0114
              */
              async function devaluatedTPTo1000Setup() {
                await loadFixture(tpMinted1000Setup);
                await mocFunctions.pokePrice(TP_0, 1000);
              }
              finalFixturedDescribe(devaluatedTPTo1000Setup, "(Assertions)", async function () {
                it("THEN there are 67122.83 TP available to mint", async function () {
                  assertPrec("67122.836865805061029229", await mocImpl.getTPAvailableToMint(tp0));
                });
                it("THEN the coverage is 46.11", async function () {
                  assertPrec("46.118215613382899628", await mocImpl.getCglb());
                });
                it("THEN TC price is 1.0114", async function () {
                  assertPrec("1.0114", await mocImpl.getPTCac());
                });
              });
              describe("AND EMA is updated", function () {
                /*
                ctargemaCA = 19.88
                ctargemaTP = 19.88
                => TP available to mint = 93411.93
                */
                before(async function () {
                  await loadFixture(devaluatedTPTo1000Setup);
                  await time.increaseTo(await mocImpl.nextEmaCalculation());
                  await mocImpl.updateEmas();
                });
                it("THEN there are 93411.93 TP available to mint", async function () {
                  assertPrec("93411.939256558090641158", await mocImpl.getTPAvailableToMint(tp0));
                });
              });
            });
          });
        });

        describe("AND alice asks for mint TP 1, which ctargemaTP is smaller than ctargemaCA", function () {
          finalFixturedDescribe(tp0MintedSetup, "(Assertions)", async function () {
            it("THEN there are 4220.76 TP 1 available to mint", async function () {
              const tp1 = mocContracts.mocPeggedTokens[TP_1].target.toString();
              assertPrec("4220.766687516754535893", await mocImpl.getTPAvailableToMint(tp1));
            });
            describe("WHEN Alice tries to mint 4220.77 TP1", function () {
              /*
                nAC = 3100
                nTP0 = 23500
                nTP1 = 0
                lckAC = 100
                ctargmeaCA = 5.54
                ctargemaTP1 = 4.166
                => TP 1 available to mint = 4220.76
              */
              it("THEN tx reverts because there is not enough TP1 to mint", async function () {
                await expect(
                  mocFunctions.mintTP({ i: TP_1, from: alice, qTP: "4220.766687516754535894" }),
                ).to.be.revertedWithCustomError(mocImpl, ERRORS.INSUFFICIENT_TP_TO_MINT);
              });
            });
          });
          describe("WHEN Alice mints 4220.76 TP1", function () {
            /*
              nAC = 3100
              nTP0 = 23500
              nTP1 = 0
              lckAC = 100
              ctargmeaCA = 5.54
              ctargemaTP1 = 4.166
              => TP 1 available to mint = 4220.76
            */
            let alicePrevTPBalance: Balance;
            before(async function () {
              await loadFixture(tp0MintedSetup);
              alicePrevTPBalance = await mocFunctions.tpBalanceOf(TP_1, alice);
              await mocFunctions.mintTP({ i: TP_1, from: alice, qTP: "4220.766687516754535893" });
            });
            it("THEN alice receives 4220.76 TP1", async function () {
              const aliceActualTPBalance = await mocFunctions.tpBalanceOf(TP_1, alice);
              const diff = aliceActualTPBalance - alicePrevTPBalance;
              assertPrec("4220.766687516754535893", diff);
            });
            it("THEN coverage is still above ctargemaCA", async function () {
              const actualCoverage = await mocImpl.getCglb();
              const actualCtargemaCA = await mocImpl.getCtargemaCA();
              expect(actualCoverage).to.be.greaterThanOrEqual(actualCtargemaCA);
            });
            it("THEN there are 0 TP 0 and TP 1 available to mint", async function () {
              assertPrec(0, await mocImpl.getTPAvailableToMint(tp0), "TP 0", availableToMintTolerance);
              const tp1 = mocContracts.mocPeggedTokens[TP_1].target.toString();
              assertPrec(0, await mocImpl.getTPAvailableToMint(tp1), "TP 1", availableToMintTolerance);
            });
          });
          describe("WHEN alice mints 525 TP 1", function () {
            /*
              nAC = 3100
              nTP0 = 23500
              nTP1 = 0
              lckAC = 100
              ctargmeaCA = 5.54
              ctargemaTP1 = 4.166
              => TP 1 available to mint = 3914.123797
            */
            let tx: ContractTransactionResponse;
            let alicePrevACBalance: Balance;
            let mocPrevACBalance: Balance;
            let mocFeeFlowPrevACBalance: Balance;
            let tp1: Address;
            before(async function () {
              await loadFixture(tp0MintedSetup);
              alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
              mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
              mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
              tp1 = mocContracts.mocPeggedTokens[TP_1].target.toString();
              tx = await mocFunctions.mintTP({ i: TP_1, from: alice, qTP: 525, qACmax: 105 });
            });
            it("THEN alice receives 525 TP1", async function () {
              assertPrec(525, await mocFunctions.tpBalanceOf(TP_1, alice));
            });
            it("THEN Moc balance increase 100 AC", async function () {
              const mocActualACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
              const diff = mocActualACBalance - mocPrevACBalance;
              assertPrec(100, diff);
            });
            it("THEN Moc Fee Flow balance increase 0.1% of 100 AC", async function () {
              const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
              const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
              assertPrec(100 * 0.001, diff);
            });
            it("THEN alice balance decrease 100 Asset + 0.1% for Moc Fee Flow", async function () {
              const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
              const diff = alicePrevACBalance - aliceActualACBalance;
              assertACResult(100 * 1.001, diff);
            });
            it("THEN a TPMinted event is emitted", async function () {
              // tp: 1
              // sender: alice
              // receiver: alice
              // qTP: 525 TP
              // qAC: 100 AC + 0.1% for Moc Fee Flow
              // qACfee: 0.1% AC
              // qFeeToken: 0
              // qACVendorMarkup: 0
              // qFeeTokenVendorMarkup: 0
              const args = [tp1, alice, alice, pEth(525), pEth(100 * 1.001), pEth(100 * 0.001), 0, 0, 0, noVendor];
              await expectEvent(tx, args);
            });
          });
        });
        describe("AND alice asks for mint TP 4, which ctargemaTP is greater than ctargemaCA", function () {
          finalFixturedDescribe(tp0MintedSetup, "(Assertions)", function () {
            it("THEN there are 2545.85 TP 4 available to mint", async function () {
              const tp4 = mocContracts.mocPeggedTokens[TP_4].target.toString();
              assertPrec("2545.859271835502735400", await mocImpl.getTPAvailableToMint(tp4));
            });
            describe("WHEN Alice tries to mint 2545.86 TP4", function () {
              /*
              nAC = 3100
              nTP0 = 23500
              nTP1 = 0
              lckAC = 100
              ctargmeaCA = 5.54
              ctargemaTP4 = 6.25
              => TP 4 available to mint = 2545.85
              */
              it("THEN tx reverts because there is not enough TP4 to mint", async function () {
                await expect(
                  mocFunctions.mintTP({ i: TP_4, from: alice, qTP: "2545.859271835502735401" }),
                ).to.be.revertedWithCustomError(mocImpl, ERRORS.INSUFFICIENT_TP_TO_MINT);
              });
            });
          });
          describe("WHEN Alice mints 2545.85 TP4", function () {
            /*
              nAC = 3100
              nTP0 = 23500
              nTP1 = 0
              lckAC = 100
              ctargmeaCA = 5.54
              ctargemaTP4 = 6.25
              => TP 4 available to mint = 2545.85
            */
            let alicePrevTPBalance: Balance;
            before(async function () {
              await loadFixture(tp0MintedSetup);
              alicePrevTPBalance = await mocFunctions.tpBalanceOf(TP_4, alice);
              await mocFunctions.mintTP({ i: TP_4, from: alice, qTP: "2545.859271835502735400" });
            });
            it("THEN alice receives 2545.85 TP4", async function () {
              const aliceActualTPBalance = await mocFunctions.tpBalanceOf(TP_4, alice);
              const diff = aliceActualTPBalance - alicePrevTPBalance;
              assertPrec("2545.859271835502735400", diff);
            });
            it("THEN coverage is still above ctargemaCA", async function () {
              const actualCoverage = await mocImpl.getCglb();
              const actualCtargemaCA = await mocImpl.getCtargemaCA();
              expect(actualCoverage).to.be.greaterThanOrEqual(actualCtargemaCA);
            });
            it("THEN there are 0 TP 0 and TP 4 available to mint", async function () {
              assertPrec(0, await mocImpl.getTPAvailableToMint(tp0), "TP 0", availableToMintTolerance);
              const tp4 = mocContracts.mocPeggedTokens[TP_4].target.toString();
              assertPrec(0, await mocImpl.getTPAvailableToMint(tp4), "TP 4", availableToMintTolerance);
            });
          });
        });
        describe("AND Pegged Token has been revaluated making lckAC bigger than total AC in the protocol", function () {
          // this test is to check that tx doesn't fail because underflow doing totalACAvailable - lckAC
          before(async function () {
            await loadFixture(tp0MintedSetup);
            await mocFunctions.pokePrice(TP_0, "0.00000001");
          });
          it("THEN tx reverts because coverage is below the protected threshold", async function () {
            expect((await mocImpl.getCglb()) < pEth(1)); // check that lckAC > totalACAvailable
            await expect(mocFunctions.mintTP({ from: alice, qTP: 100 })).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.LOW_COVERAGE,
            );
          });
        });
      });
      describe("AND alice has FeeToken to pay fees", function () {
        let alicePrevACBalance: Balance;
        let alicePrevFeeTokenBalance: Balance;
        let mocFeeFlowPrevACBalance: Balance;
        let mocFeeFlowPrevFeeTokenBalance: Balance;
        let tx: ContractTransactionResponse;
        async function aliceHasFeeTokensSetup() {
          await loadFixture(collateralizedProtocolSetup);
          // mint FeeToken to alice
          await mocContracts.feeToken.mint(alice, pEth(50));
          await mocContracts.feeToken
            .connect(await ethers.getSigner(alice))
            .approve(mocImpl.target.toString(), pEth(50));

          // initialize previous balances
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          alicePrevFeeTokenBalance = await mocContracts.feeToken.balanceOf(alice);
          mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          mocFeeFlowPrevFeeTokenBalance = await mocContracts.feeToken.balanceOf(mocFeeFlowAddress);
        }
        describe("WHEN alice mints 23500 TP", function () {
          before(async function () {
            await loadFixture(aliceHasFeeTokensSetup);
            tx = await mocFunctions.mintTP({ from: alice, qTP: 23500 });
          });
          it("THEN alice AC balance decrease 100 Asset", async function () {
            const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
            const diff = alicePrevACBalance - aliceActualACBalance;
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
        describe("WHEN alice mints 23500 TP to bob", function () {
          before(async function () {
            await loadFixture(aliceHasFeeTokensSetup);
            tx = await mocFunctions.mintTP({ from: alice, to: bob, qTP: 23500 });
          });
          it("THEN alice AC balance decrease 100 Asset", async function () {
            const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
            const diff = alicePrevACBalance - aliceActualACBalance;
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
            // receiver: bob
            // qTP: 23500 TC
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

export { mintTPBehavior };
