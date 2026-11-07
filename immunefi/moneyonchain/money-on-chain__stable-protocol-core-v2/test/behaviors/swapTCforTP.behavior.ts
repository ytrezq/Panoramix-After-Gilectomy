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
import { MocCACoinbase, MocCARC20, MocRC20 } from "../../typechain";

const swapTCforTPBehavior = function (setup: BaseSetupFunction) {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let feeToken: MocRC20;
  let deployer: Address;
  let alice: Address;
  let bob: Address;
  let vendor: Address;
  let expectEvent: any;
  let assertACResult: any;
  let tp0: Address;
  const TP_0 = 0;
  const {
    mocAddresses: { mocFeeFlowAddress },
    queueParams: {
      execCostParams: { swapTCforTPExecCost },
    },
  } = getNetworkDeployParams(hre);

  let tx: ContractTransactionResponse;
  let alicePrevTCBalance: Balance;
  let alicePrevACBalance: Balance;
  let mocPrevACBalance: Balance;
  let mocFeeFlowPrevACBalance: Balance;

  describe("Feature: swap Collateral Token for Pegged Token", function () {
    async function baseSetup() {
      ({ mocContracts, mocFunctions } = await loadFixture(setup));
      ({ mocImpl, feeToken } = mocContracts);
      ({ deployer, alice, bob, vendor } = await getNamedAccounts());
      expectEvent = expectEventFor(mocContracts, "TCSwappedForTP");
      assertACResult = mocFunctions.assertACResult(swapTCforTPExecCost);
      tp0 = mocContracts.mocPeggedTokens[0].target.toString();
    }

    describe("GIVEN alice has 3000 TC", function () {
      async function aliceHasTCSetup() {
        await loadFixture(baseSetup);
        await mocFunctions.mintTC({ from: alice, qTC: 3000 });
      }

      finalFixturedDescribe(aliceHasTCSetup, "WHEN alice tries to swap 0 TC", function () {
        it("THEN tx reverts because the amount of TC is too low and out of precision", async function () {
          await expect(mocFunctions.swapTCforTP({ from: alice, qTC: 0 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.QAC_NEEDED_MUST_BE_GREATER_ZERO,
          );
        });
      });
      finalFixturedDescribe(aliceHasTCSetup, "WHEN alice tries to swap using a non-existent TP", function () {
        it("THEN tx reverts", async function () {
          const fakeTP = mocContracts.mocCollateralToken.target.toString();
          await expect(mocFunctions.swapTCforTP({ tp: fakeTP, from: alice, qTC: 100 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.INVALID_ADDRESS,
          );
        });
      });
      finalFixturedDescribe(
        aliceHasTCSetup,
        "WHEN alice swap 100 TC sending 0.99(less amount) AC for fees",
        function () {
          it("THEN tx reverts because AC received is below the minimum required", async function () {
            await expect(
              mocFunctions.swapTCforTP({ from: alice, qTC: 100, qACmax: "0.999999999999999999" }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.INSUFFICIENT_QAC_SENT);
          });
        },
      );
      finalFixturedDescribe(
        aliceHasTCSetup,
        "WHEN alice swap 100 TC expecting to receive 23501 TP as minimum",
        function () {
          /*
        100 TC = 100 AC
        100 AC = 23500 TP 0
        */
          it("THEN tx reverts because TP received is below the minimum required", async function () {
            await expect(
              mocFunctions.swapTCforTP({ from: alice, qTC: 100, qTPmin: 23501 }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.QTP_BELOW_MINIMUM);
          });
        },
      );
      finalFixturedDescribe(aliceHasTCSetup, "WHEN alice tries to swap 722 TC", function () {
        /*
        722 TC = 722 AC
        100 AC = 169670 TP 0

        nAC = 3000    
        nTP = 0
        lckAC = 0
        ctargemaTP = 5.54
        ctargemaCA = 4
        => TP available to mint = 169632
        */
        it("THEN tx reverts because there is not enough TP to mint", async function () {
          await expect(mocFunctions.swapTCforTP({ from: alice, qTC: 722 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.INSUFFICIENT_TP_TO_MINT,
          );
        });
      });
      describe("WHEN alice swaps 100 TC for 23500 TP 0", function () {
        /*
        100 TC = 100 AC
        100 AC = 23500 TP 0
            
        nAC = 3000  
        nTP = 23500
        lckAC = 100
        => coverage = 30

        swapTCforTPfee = 1%
        */
        before(async function () {
          await loadFixture(aliceHasTCSetup);
          [alicePrevTCBalance, alicePrevACBalance, mocPrevACBalance, mocFeeFlowPrevACBalance] = await Promise.all([
            mocFunctions.tcBalanceOf(alice),
            mocFunctions.assetBalanceOf(alice),
            mocFunctions.acBalanceOf(mocImpl.target.toString()),
            mocFunctions.acBalanceOf(mocFeeFlowAddress),
          ]);
          tx = await mocFunctions.swapTCforTP({ from: alice, qTC: 100, qTPmin: 23500 });
        });
        it("THEN coverage decrease to 30 value", async function () {
          assertPrec(30, await mocImpl.getCglb());
        });
        it("THEN alice TP 0 balance is 23500", async function () {
          assertPrec(23500, await mocFunctions.tpBalanceOf(TP_0, alice));
        });
        it("THEN nACcb, nTCcb and nTP matches with AC balance and total supplies", async function () {
          assertPrec(await mocImpl.nACcb(), await mocFunctions.acBalanceOf(mocImpl.target.toString()));
          assertPrec(await mocImpl.nTCcb(), await mocContracts.mocCollateralToken.totalSupply());
          assertPrec((await mocImpl.pegContainer(TP_0))[0], await mocContracts.mocPeggedTokens[TP_0].totalSupply());
        });
        it("THEN alice TC balance decrease 100", async function () {
          const aliceActualTCBalance = await mocFunctions.tcBalanceOf(alice);
          const diff = alicePrevTCBalance - aliceActualTCBalance;
          assertPrec(100, diff);
        });
        it("THEN Moc balance didn't change", async function () {
          assertPrec(mocPrevACBalance, await mocFunctions.acBalanceOf(mocImpl.target.toString()));
        });
        it("THEN Moc Fee Flow balance increase 1% of 100 AC", async function () {
          const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
          assertPrec(100 * 0.01, diff);
        });
        it("THEN alice balance decrease 1% for Moc Fee Flow of 100 AC", async function () {
          const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
          const diff = alicePrevACBalance - aliceActualACBalance;
          assertACResult(1, diff);
        });
        it("THEN a TCSwappedForTP event is emitted", async function () {
          // i: 0
          // sender: alice
          // receiver: alice
          // qTC: 100 TC
          // qTP: 23500 TP
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          await expectEvent(tx, [tp0, alice, alice, pEth(100), pEth(23500), pEth(100 * 0.01), 0, 0, 0, noVendor]);
        });
        it("THEN a Collateral Token Transfer event is emitted", async function () {
          // from: Moc
          // to: Zero Address
          // amount: 100 TC
          await expect(tx)
            .to.emit(mocContracts.mocCollateralToken, "Transfer")
            .withArgs(mocImpl.target.toString(), CONSTANTS.ZERO_ADDRESS, pEth(100));
        });
        it("THEN a Pegged Token 0 Transfer event is emitted", async function () {
          // from: Zero Address
          // to: alice
          // amount: 23500 TP
          await expect(tx)
            .to.emit(mocContracts.mocPeggedTokens[TP_0], "Transfer")
            .withArgs(CONSTANTS.ZERO_ADDRESS, alice, pEth(23500));
        });
      });
      describe("WHEN alice swaps 100 TC for 23500 TP 0 to bob", function () {
        /*
        100 TC = 100 AC
        100 AC = 23500 TP 0
            
        nAC = 3000  
        nTP = 23500
        lckAC = 100
        => coverage = 30

        swapTCforTPfee = 1%
        */
        before(async function () {
          await loadFixture(aliceHasTCSetup);
          [alicePrevTCBalance, alicePrevACBalance] = await Promise.all([
            mocFunctions.tcBalanceOf(alice),
            mocFunctions.assetBalanceOf(alice),
          ]);
          tx = await mocFunctions.swapTCforTP({ from: alice, to: bob, qTC: 100 });
        });
        it("THEN bob TP 0 balance is 23500", async function () {
          assertPrec(23500, await mocFunctions.tpBalanceOf(TP_0, bob));
        });
        it("THEN alice TC balance decrease 100", async function () {
          const aliceActualTCBalance = await mocFunctions.tcBalanceOf(alice);
          const diff = alicePrevTCBalance - aliceActualTCBalance;
          assertPrec(100, diff);
        });
        it("THEN alice balance decrease 1% for Moc Fee Flow of 100 AC", async function () {
          const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
          const diff = alicePrevACBalance - aliceActualACBalance;
          assertACResult(1, diff);
        });
        it("THEN a TCSwappedForTP event is emitted", async function () {
          // i: 0
          // sender: alice
          // receiver: bob
          // qTC: 100 TC
          // qTP: 23500 TP
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          await expectEvent(tx, [tp0, alice, bob, pEth(100), pEth(23500), pEth(100 * 0.01), 0, 0, 0, noVendor]);
        });
      });
      finalFixturedDescribe(
        aliceHasTCSetup,
        "WHEN alice tries to swap 100 TC for 23500 TP 0 via vendor without sending the AC for the markup",
        function () {
          it("THEN tx reverts because AC received is below the minimum required", async function () {
            // qACmax = 1% for qACfee of 100AC
            await expect(
              mocFunctions.swapTCforTP({ from: alice, qTC: 100, qACmax: 1, vendor }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.INSUFFICIENT_QAC_SENT);
          });
        },
      );
      describe("WHEN alice swaps 100 TC for 23500 TP 0 via vendor", function () {
        let alicePrevACBalance: Balance;
        let vendorPrevACBalance: Balance;
        let tx: ContractTransactionResponse;
        before(async function () {
          await loadFixture(aliceHasTCSetup);
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          vendorPrevACBalance = await mocFunctions.acBalanceOf(vendor);
          tx = await mocFunctions.swapTCforTP({ from: alice, qTC: 100, vendor });
        });
        it("THEN alice AC balance decrease 11 Asset (1% qACFee + 10% qACVendorMarkup of 100 qAC)", async function () {
          const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
          const diff = alicePrevACBalance - aliceActualACBalance;
          assertACResult(11, diff);
        });
        it("THEN vendor AC balance increase 10 Asset", async function () {
          const vendorActualACBalance = await mocFunctions.acBalanceOf(vendor);
          const diff = vendorActualACBalance - vendorPrevACBalance;
          assertPrec(10, diff);
        });
        it("THEN a TCSwappedForTP event is emitted", async function () {
          // i: 0
          // sender: alice
          // receiver: alice
          // qTC: 100 TC
          // qTP: 23500 TP
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 10% AC
          // qFeeTokenVendorMarkup: 0
          await expectEvent(tx, [tp0, alice, alice, pEth(100), pEth(23500), pEth(1), 0, pEth(10), 0, vendor]);
        });
      });
      describe("WHEN alice swaps 100 TC for 23500 TP 0 to bob via vendor", function () {
        let tx: ContractTransactionResponse;
        before(async function () {
          await loadFixture(aliceHasTCSetup);
          tx = await mocFunctions.swapTCforTP({ from: alice, to: bob, qTC: 100, vendor });
        });
        it("THEN a TCSwappedForTP event is emitted", async function () {
          // i: 0
          // sender: alice
          // receiver: bob
          // qTC: 100 TC
          // qTP: 23500 TP
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 10% AC
          // qFeeTokenVendorMarkup: 0
          await expectEvent(tx, [tp0, alice, bob, pEth(100), pEth(23500), pEth(1), 0, pEth(10), 0, vendor]);
        });
      });
      describe("AND there are 100000 TC more in the protocol", function () {
        async function protocolWith100000TCSetup() {
          await loadFixture(aliceHasTCSetup);
          await mocFunctions.mintTC({ from: deployer, qTC: 100000 });
        }
        finalFixturedDescribe(protocolWith100000TCSetup, "WHEN alice tries to swap 3000.1 TC", function () {
          it("THEN tx reverts because alice doesn't have that much TC", async function () {
            const qTC = "3000.000000000000000001";
            await expect(mocFunctions.swapTCforTP({ from: alice, qTC, qACmax: 30000 })).to.be.revertedWith(
              ERRORS.ERC20_TRANF_EXCEEDS_BALANCE,
            );
          });
        });
        describe("WHEN alice swaps 3000(all balance) TC for 705000 TP 0", function () {
          /*
            3000 TC = 3000 AC
            3000 AC = 705000 TP 0
            */
          before(async function () {
            await loadFixture(protocolWith100000TCSetup);
            tx = await mocFunctions.swapTCforTP({ from: alice, qTC: 3000 });
          });
          it("THEN a TCSwappedForTP event is emitted", async function () {
            // i: 0
            // sender: alice
            // receiver: alice
            // qTC: 3000 TC
            // qTP: 705000 TP
            // qACfee: 1% AC
            // qFeeToken: 0
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            await expectEvent(tx, [tp0, alice, alice, pEth(3000), pEth(705000), pEth(30), 0, 0, 0, noVendor]);
          });
        });
      });
      describe("AND 23500 TP0 are minted", function () {
        async function TP0MintedSetup() {
          await loadFixture(aliceHasTCSetup);
          await mocFunctions.mintTP({ from: deployer, qTP: 23500 });
        }
        describe("AND TP 0 has been devaluated to 470 making TC price rices", function () {
          /*  
            nAC = 3100    
            nTP = 23500 + 11750
            lckAC = 50 + 25
            nACgain = 5
            => pTCac = 1.0066
            */
          async function TP0DevaluesSetup() {
            await loadFixture(TP0MintedSetup);
            await mocFunctions.pokePrice(TP_0, 470);
          }
          describe("WHEN alice swaps 10 TC for 4731.02 TP 0", function () {
            /*
            10 TC = 10.066 AC
            10.066AC = 4731.33 TP 0
            */
            before(async function () {
              await loadFixture(TP0DevaluesSetup);
              tx = await mocFunctions.swapTCforTP({ from: alice, qTC: 10 });
            });
            it("THEN a TCSwappedForTP event is emitted", async function () {
              // i: 0
              // sender: alice
              // receiver: alice
              // qTC: 10 TC
              // qTP: 4731.02 TP
              // qACfee: 1% AC
              // qFeeToken: 0
              // qACVendorMarkup: 0
              // qFeeTokenVendorMarkup: 0
              const qTP = pEth("4731.333333333333333333");
              const qACfee = pEth("0.100666666666666666");
              await expectEvent(tx, [tp0, alice, alice, pEth(10), qTP, qACfee, 0, 0, 0, noVendor]);
            });
          });
        });
        describe("AND TP 0 has been revaluated to 37.9", function () {
          /*  
            nAC = 3100    
            nTP = 23500
            lckAC = 620
            => coverage = 5 
        */
          before(async function () {
            await loadFixture(TP0MintedSetup);
            await mocFunctions.pokePrice(TP_0, "37.9");
          });
          describe("WHEN alice tries to swap 1 TC for TP", function () {
            it("THEN tx reverts because coverage is below the target coverage adjusted by the moving average", async function () {
              await expect(mocFunctions.swapTCforTP({ from: alice, qTC: 1 })).to.be.revertedWithCustomError(
                mocImpl,
                ERRORS.LOW_COVERAGE,
              );
            });
          });
        });
        describe("AND TP 0 has been revaluated to 100 making TC price falls", function () {
          /*  
          nAC = 3100 
          nTP = 23500
          lckAC = 235
          => pTCac = 0.955
          */
          async function TP0RevaluesSetup() {
            await loadFixture(TP0MintedSetup);
            await mocFunctions.pokePrice(TP_0, 100);
          }
          finalFixturedDescribe(TP0RevaluesSetup, "WHEN alice tries to swap 1 wei TC for TP", function () {
            it("THEN tx reverts because the amount of TC is too low and out of precision", async function () {
              await expect(
                mocFunctions.swapTCforTP({ from: alice, qTC: 1n, applyPrecision: false }),
              ).to.be.revertedWithCustomError(mocImpl, ERRORS.QAC_NEEDED_MUST_BE_GREATER_ZERO);
            });
          });
          describe("WHEN alice swaps 10 TC for 955 TP 0", function () {
            /*
            10 TC = 0.955 AC
            0.955 AC = 955 TP 0
            */
            before(async function () {
              await loadFixture(TP0RevaluesSetup);
              tx = await mocFunctions.swapTCforTP({ from: alice, qTC: 10 });
            });
            it("THEN a TCSwappedForTP event is emitted", async function () {
              // i: 0
              // sender: alice
              // receiver: alice
              // qTC: 10 TC
              // qTP: 955 TP
              // qACfee: 1% AC
              // qFeeToken: 0
              // qACVendorMarkup: 0
              // qFeeTokenVendorMarkup: 0
              const args = [tp0, alice, alice, pEth(10), pEth(955), pEth("0.0955"), 0, 0, 0, noVendor];
              await expectEvent(tx, args);
            });
          });
        });
        describe("AND Pegged Token has been revaluated making lckAC bigger than total AC in the protocol", function () {
          // this test is to check that tx doesn't fail because underflow doing totalACAvailable - lckAC
          before(async function () {
            await loadFixture(TP0MintedSetup);
            await mocFunctions.pokePrice(TP_0, "0.00000001");
          });
          it("THEN tx reverts because coverage is below the protected threshold", async function () {
            expect((await mocImpl.getCglb()) < pEth(1)); // check that lckAC > totalACAvailable
            await expect(mocFunctions.swapTCforTP({ from: alice, qTC: 100 })).to.be.revertedWithCustomError(
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
          await loadFixture(aliceHasTCSetup);
          // mint FeeToken to alice
          await feeToken.mint(alice, pEth(50));
          await feeToken.connect(await ethers.getSigner(alice)).approve(mocImpl.target.toString(), pEth(50));

          // initialize previous balances
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          alicePrevFeeTokenBalance = await feeToken.balanceOf(alice);
          mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          mocFeeFlowPrevFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
        }
        describe("WHEN alice swaps 100 TC for 23500 TP 0", function () {
          before(async function () {
            await loadFixture(aliceHasFeeTokensSetup);
            tx = await mocFunctions.swapTCforTP({ from: alice, qTC: 100 });
          });
          it("THEN alice AC balance doesn't change", async function () {
            const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
            const diff = alicePrevACBalance - aliceActualACBalance;
            assertACResult(0, diff);
          });
          it("THEN alice Fee Token balance decrease 0.5 (100 * 1% * 50%)", async function () {
            const aliceActualFeeTokenBalance = await feeToken.balanceOf(alice);
            const diff = alicePrevFeeTokenBalance - aliceActualFeeTokenBalance;
            assertPrec(0.5, diff);
          });
          it("THEN Moc Fee Flow AC balance doesn't change", async function () {
            const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
            assertPrec(mocFeeFlowActualACBalance, mocFeeFlowPrevACBalance);
          });
          it("THEN Moc Fee Flow Fee Token balance increase 0.5 (100 * 1% * 50%)", async function () {
            const mocFeeFlowActualFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
            const diff = mocFeeFlowActualFeeTokenBalance - mocFeeFlowPrevFeeTokenBalance;
            assertPrec(0.5, diff);
          });
          it("THEN Fee Token is used as fee payment method", async function () {
            // i: 0
            // sender: alice
            // receiver: alice
            // qTC: 100 TC
            // qTP: 23500 TP
            // qACfee: 0
            // qFeeToken: 100 (1% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            await expectEvent(tx, [tp0, alice, alice, pEth(100), pEth(23500), 0, pEth(0.5), 0, 0, noVendor]);
          });
        });
        describe("WHEN alice swaps 100 TC for 23500 TP 0", function () {
          before(async function () {
            await loadFixture(aliceHasFeeTokensSetup);
            tx = await mocFunctions.swapTCforTP({ from: alice, to: bob, qTC: 100 });
          });
          it("THEN alice AC balance doesn't change", async function () {
            const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
            const diff = alicePrevACBalance - aliceActualACBalance;
            assertACResult(0, diff);
          });
          it("THEN alice Fee Token balance decrease 0.5 (100 * 1% * 50%)", async function () {
            const aliceActualFeeTokenBalance = await feeToken.balanceOf(alice);
            const diff = alicePrevFeeTokenBalance - aliceActualFeeTokenBalance;
            assertPrec(0.5, diff);
          });
          it("THEN Moc Fee Flow AC balance doesn't change", async function () {
            const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
            assertPrec(mocFeeFlowActualACBalance, mocFeeFlowPrevACBalance);
          });
          it("THEN Moc Fee Flow Fee Token balance increase 0.5 (100 * 1% * 50%)", async function () {
            const mocFeeFlowActualFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
            const diff = mocFeeFlowActualFeeTokenBalance - mocFeeFlowPrevFeeTokenBalance;
            assertPrec(0.5, diff);
          });
          it("THEN Fee Token is used as fee payment method", async function () {
            // i: 0
            // sender: alice
            // receiver: bob
            // qTC: 100 TC
            // qTP: 23500 TP
            // qACfee: 0
            // qFeeToken: 100 (1% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            await expectEvent(tx, [tp0, alice, bob, pEth(100), pEth(23500), 0, pEth(0.5), 0, 0, noVendor]);
          });
        });
      });
    });
  });
};

export { swapTCforTPBehavior };
