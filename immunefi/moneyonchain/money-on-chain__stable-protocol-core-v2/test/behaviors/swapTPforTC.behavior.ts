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

const swapTPforTCBehavior = function (setup: BaseSetupFunction) {
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
  let tp0: Address[];
  const TP_0 = 0;
  const {
    mocAddresses: { mocFeeFlowAddress },
    queueParams: {
      execCostParams: { swapTPforTCExecCost },
    },
  } = getNetworkDeployParams(hre);

  let tx: ContractTransactionResponse;
  let alicePrevTP0Balance: Balance;
  let alicePrevACBalance: Balance;
  let mocPrevACBalance: Balance;
  let mocFeeFlowPrevACBalance: Balance;

  describe("Feature: swap Pegged Token for Collateral Token", function () {
    async function baseSetup() {
      ({ mocContracts, mocFunctions } = await loadFixture(setup));
      ({ mocImpl, feeToken } = mocContracts);
      ({ deployer, alice, bob, vendor } = await getNamedAccounts());
      // add collateral
      await mocFunctions.mintTC({ from: deployer, qTC: 3000 });
      expectEvent = expectEventFor(mocContracts, "TPSwappedForTC");
      assertACResult = mocFunctions.assertACResult(swapTPforTCExecCost);
      tp0 = mocContracts.mocPeggedTokens[0].target.toString();
    }
    describe("GIVEN alice has 23500 TP 0", function () {
      async function collateralizedProtocolSetup() {
        await loadFixture(baseSetup);
        await mocFunctions.mintTP({ from: alice, qTP: 23500 });
      }
      finalFixturedDescribe(collateralizedProtocolSetup, "WHEN alice tries to swap 0 TP 0", function () {
        it("THEN tx reverts because the amount of TP is too low and out of precision", async function () {
          await expect(mocFunctions.swapTPforTC({ from: alice, qTP: 0 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.QTC_BELOW_MINIMUM,
          );
        });
      });
      finalFixturedDescribe(collateralizedProtocolSetup, "WHEN alice tries to swap 1 wei TP 0", function () {
        it("THEN tx reverts because the amount of TP is too low and out of precision", async function () {
          await expect(
            mocFunctions.swapTPforTC({ from: alice, qTP: 1n, applyPrecision: false }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.QTC_BELOW_MINIMUM);
        });
      });
      finalFixturedDescribe(
        collateralizedProtocolSetup,
        "WHEN alice swap 23500 TP 0 sending 0.99(less amount) Asset for fees",
        function () {
          it("THEN tx reverts because Asset received is below the minimum required", async function () {
            await expect(
              mocFunctions.swapTPforTC({ from: alice, qTP: 23500, qACmax: "0.999999999999999999" }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.INSUFFICIENT_QAC_SENT);
          });
        },
      );
      finalFixturedDescribe(
        collateralizedProtocolSetup,
        "WHEN alice tries to swap using a non-existent TP",
        function () {
          it("THEN tx reverts", async function () {
            const fakeTP = mocContracts.mocCollateralToken;
            await expect(
              mocFunctions.swapTPforTC({ tp: fakeTP, from: deployer, qTP: 100 }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.INVALID_ADDRESS);
          });
        },
      );
      finalFixturedDescribe(
        collateralizedProtocolSetup,
        "WHEN alice swap 23500 TP 0 expecting to receive 101 TC as minimum",
        function () {
          /*
            23500 TP 0 = 100 AC
            100 AC = 100 TC
          */
          it("THEN tx reverts because TC received is below the minimum required", async function () {
            await expect(
              mocFunctions.swapTPforTC({ from: alice, qTP: 23500, qTCmin: 101 }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.QTC_BELOW_MINIMUM);
          });
        },
      );
      describe("WHEN alice swaps 23500(all balance) TP 0 for 100 TC", function () {
        /*
            23500 TP 0 = 100 AC
            100 AC = 100 TC
            
            nAC = 3100  
            nTP = 0
            lckAC = 0
            => coverage = MAX_UINT256

            swapTPforTCfee = 1%
          */
        before(async function () {
          await loadFixture(collateralizedProtocolSetup);
          [alicePrevACBalance, mocPrevACBalance, mocFeeFlowPrevACBalance] = await Promise.all([
            mocFunctions.assetBalanceOf(alice),
            mocFunctions.acBalanceOf(mocImpl.target.toString()),
            mocFunctions.acBalanceOf(mocFeeFlowAddress),
          ]);
          tx = await mocFunctions.swapTPforTC({ from: alice, qTP: 23500, qTCmin: 100 });
        });
        it("THEN coverage increase to max value", async function () {
          assertPrec(CONSTANTS.MAX_UINT256, await mocImpl.getCglb());
        });
        it("THEN alice TP 0 balance is 0", async function () {
          assertPrec(0, await mocFunctions.tpBalanceOf(TP_0, alice));
        });
        it("THEN nACcb, nTCcb and nTP matches with AC balance and total supplies", async function () {
          assertPrec(await mocImpl.nACcb(), await mocFunctions.acBalanceOf(mocImpl.target.toString()));
          assertPrec(await mocImpl.nTCcb(), await mocContracts.mocCollateralToken.totalSupply());
          assertPrec((await mocImpl.pegContainer(TP_0))[0], await mocContracts.mocPeggedTokens[TP_0].totalSupply());
        });
        it("THEN alice TC balance is 100", async function () {
          assertPrec(100, await mocFunctions.tcBalanceOf(alice));
        });
        it("THEN Moc balance didn't change", async function () {
          assertPrec(mocPrevACBalance, await mocFunctions.acBalanceOf(mocImpl.target.toString()));
        });
        it("THEN Moc Fee Flow balance increase 1% of 100 AC", async function () {
          const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
          assertPrec(100 * 0.01, diff);
        });
        it("THEN alice balance decrease 1% for Moc Fee Flow of 100 Asset", async function () {
          const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
          const diff = alicePrevACBalance - aliceActualACBalance;
          assertACResult(1, diff);
        });
        it("THEN a TPSwappedForTC event is emitted", async function () {
          // iFrom: 0
          // iTo: 1
          // sender: alice
          // receiver: alice
          // qTP: 23500 TP
          // qTC: 100 TC
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          await expectEvent(tx, [tp0, alice, alice, pEth(23500), pEth(100), pEth(1), 0, 0, 0, noVendor]);
        });
        it("THEN a Pegged Token 0 Transfer event is emitted", async function () {
          // from: Moc
          // to: Zero Address
          // amount: 23500 TP
          await expect(tx)
            .to.emit(mocContracts.mocPeggedTokens[TP_0], "Transfer")
            .withArgs(mocImpl.target.toString(), CONSTANTS.ZERO_ADDRESS, pEth(23500));
        });
        it("THEN a Collateral Token Transfer event is emitted", async function () {
          // from: Zero Address
          // to: alice
          // amount: 100 TC
          await expect(tx)
            .to.emit(mocContracts.mocCollateralToken, "Transfer")
            .withArgs(CONSTANTS.ZERO_ADDRESS, alice, pEth(100));
        });
      });
      describe("WHEN alice swaps 2350(10% of balance) TP 0 for 10 TC to bob", function () {
        /*
            2350 TP 0 = 10 AC
            10 AC = 10 TC

            nAC = 3100  
            nTP = 21150
            lckAC = 90
            => coverage = 34.44

            swapTPforTCfee = 1%
          */
        before(async function () {
          await loadFixture(collateralizedProtocolSetup);
          alicePrevTP0Balance = await mocFunctions.tpBalanceOf(TP_0, alice);
          mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          tx = await mocFunctions.swapTPforTC({
            i: TP_0,
            from: alice,
            to: bob,
            qTP: 2350,
            qTCmin: 10,
          });
        });
        it("THEN coverage increase to 34.44", async function () {
          assertPrec("34.444444444444444444", await mocImpl.getCglb());
        });
        it("THEN alice TP 0 balances decrease 2350 TP", async function () {
          const aliceActualTP0Balance = await mocFunctions.tpBalanceOf(TP_0, alice);
          const diff = alicePrevTP0Balance - aliceActualTP0Balance;
          assertPrec(2350, diff);
        });
        it("THEN bob TC balances is 10", async function () {
          assertPrec(10, await mocFunctions.tcBalanceOf(bob));
        });
        it("THEN Moc balance didn't change", async function () {
          assertPrec(mocPrevACBalance, await mocFunctions.acBalanceOf(mocImpl.target.toString()));
        });
        it("THEN a TPSwappedForTC event is emitted", async function () {
          // iFrom: 0
          // iTo: 1
          // sender: alice
          // receiver: bob
          // qTP: 2350 TP
          // qTC: 10 TC
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup : 0
          await expectEvent(tx, [tp0, alice, bob, pEth(2350), pEth(10), pEth(10 * 0.01), 0, 0, 0, noVendor]);
        });
      });
      finalFixturedDescribe(
        collateralizedProtocolSetup,
        "WHEN alice tries to swap 23500 TP 0 for 100 TC via vendor without sending the AC for the markup",
        function () {
          it("THEN tx reverts because AC received is below the minimum required", async function () {
            // qACmax = 1% for qACfee of 100AC
            await expect(
              mocFunctions.swapTPforTC({ from: alice, qTP: 23500, qACmax: 1, vendor }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.INSUFFICIENT_QAC_SENT);
          });
        },
      );
      describe("WHEN alice swaps 23500 TP 0 for 100 TC via vendor", function () {
        let alicePrevACBalance: Balance;
        let vendorPrevACBalance: Balance;
        let tx: ContractTransactionResponse;
        before(async function () {
          await loadFixture(collateralizedProtocolSetup);
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          vendorPrevACBalance = await mocFunctions.acBalanceOf(vendor);
          tx = await mocFunctions.swapTPforTC({ from: alice, qTP: 23500, vendor });
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
        it("THEN a TPSwappedForTC event is emitted", async function () {
          // iFrom: 0
          // iTo: 1
          // sender: alice
          // receiver: alice
          // qTP: 23500 TP
          // qTC: 100 TC
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 10% AC
          // qFeeTokenVendorMarkup: 0
          await expectEvent(tx, [tp0, alice, alice, pEth(23500), pEth(100), pEth(1), 0, pEth(10), 0, vendor]);
        });
      });
      describe("WHEN alice swaps 23500 TP 0 for 100 TC to bob via vendor", function () {
        let tx: ContractTransactionResponse;
        before(async function () {
          await loadFixture(collateralizedProtocolSetup);
          tx = await mocFunctions.swapTPforTC({ from: alice, to: bob, qTP: 23500, vendor });
        });
        it("THEN a TPSwappedForTC event is emitted", async function () {
          // iFrom: 0
          // iTo: 1
          // sender: alice
          // receiver: bob
          // qTP: 23500 TP
          // qTC: 100 TC
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 10% AC
          // qFeeTokenVendorMarkup: 0
          await expectEvent(tx, [tp0, alice, bob, pEth(23500), pEth(100), pEth(1), 0, pEth(10), 0, vendor]);
        });
      });
      describe("AND TP 0 has been revaluated to 15.1", function () {
        /*  
        nAC = 3100    
        nTP0 = 23500
        lckAC = 1556.29
        => coverage = 1.99 
        */
        before(async function () {
          await loadFixture(collateralizedProtocolSetup);
          await mocFunctions.pokePrice(TP_0, "15.1");
        });
        describe("WHEN Alice tries to swap 100 TP for TC", function () {
          it("THEN tx reverts because coverage is below the protected threshold", async function () {
            await expect(mocFunctions.swapTPforTC({ from: alice, qTP: 100 })).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.LOW_COVERAGE,
            );
          });
        });
      });
      describe("AND TP 0 has been devaluated to 470 making TC price rices", function () {
        /*  
        nAC = 3100    
        nTP = 23500 + 11750
        lckAC = 50 + 25
        nACgain = 5
        => pTCac = 1.0066

        4700 TP 0 = 10 AC
        10 AC = 9.933 TC
        */
        async function TP0DevaluatesSetup() {
          await loadFixture(collateralizedProtocolSetup);
          await mocFunctions.pokePrice(TP_0, 470);
        }
        describe("WHEN alice swaps 4700 TP for 9.933 TC", function () {
          before(async function () {
            await loadFixture(TP0DevaluatesSetup);
            tx = await mocFunctions.swapTPforTC({ from: alice, qTP: 4700 });
          });
          it("THEN a TPSwappedForTC event is emitted", async function () {
            // iFrom: 0
            // iTo: 1
            // sender: alice
            // receiver: alice
            // qTP: 4700 TP
            // qTC: 9.933 TC
            // qACfee: 1% AC
            // qFeeToken: 0
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const qTC = pEth("9.933774834437086092");
            await expectEvent(tx, [tp0, alice, alice, pEth(4700), qTC, pEth(10 * 0.01), 0, 0, 0, noVendor]);
          });
        });
      });
      describe("AND TP 0 has been revaluated to 100 making TC price falls", function () {
        /*  
        nAC = 3100 
        nTP = 23500
        lckAC = 235
        => pTCac = 0.955

        1000 TP 0 = 10 AC
        10 AC = 10.471 TC
        */
        async function TP0RevaluesSetup() {
          await loadFixture(collateralizedProtocolSetup);
          await mocFunctions.pokePrice(TP_0, 100);
        }
        describe("WHEN alice swaps 1000 TP for 10.471 TC", function () {
          before(async function () {
            await loadFixture(TP0RevaluesSetup);
            tx = await mocFunctions.swapTPforTC({ from: alice, qTP: 1000 });
          });
          it("THEN a TPSwappedForTC event is emitted", async function () {
            // iFrom: 0
            // iTo: 1
            // sender: alice
            // receiver: alice
            // qTP: 1000 TP
            // qTC: 10.471 TC
            // qACfee: 1% AC
            // qFeeToken: 0
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const qTC = pEth("10.471204188481675392");
            await expectEvent(tx, [tp0, alice, alice, pEth(1000), qTC, pEth(10 * 0.01), 0, 0, 0, noVendor]);
          });
        });
      });
      describe("AND Pegged Token has been revaluated making lckAC bigger than total AC in the protocol", function () {
        // this test is to check that tx doesn't fail because underflow doing totalACAvailable - lckAC
        before(async function () {
          await loadFixture(collateralizedProtocolSetup);
          await mocFunctions.pokePrice(TP_0, "0.00000001");
        });
        it("THEN tx reverts because coverage is below the protected threshold", async function () {
          expect((await mocImpl.getCglb()) < pEth(1)); // check that lckAC > totalACAvailable
          await expect(mocFunctions.swapTPforTC({ from: alice, qTP: 100 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.LOW_COVERAGE,
          );
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
          await feeToken.mint(alice, pEth(50));
          await feeToken.connect(await ethers.getSigner(alice)).approve(mocImpl.target.toString(), pEth(50));

          // initialize previous balances
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          alicePrevFeeTokenBalance = await feeToken.balanceOf(alice);
          mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          mocFeeFlowPrevFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
        }
        describe("WHEN alice swaps 23500 TP 0 for 100 TC", function () {
          before(async function () {
            await loadFixture(aliceHasFeeTokensSetup);
            tx = await mocFunctions.swapTPforTC({ from: alice, qTP: 23500, qTCmin: 100 });
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
            // qTP: 23500 TP
            // qTC: 100 TC
            // qACfee: 0
            // qFeeToken: 100 (1% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            await expectEvent(tx, [tp0, alice, alice, pEth(23500), pEth(100), 0, pEth(0.5), 0, 0, noVendor]);
          });
        });
        describe("WHEN alice swaps 23500 TP 0 for 100 TC", function () {
          before(async function () {
            await loadFixture(aliceHasFeeTokensSetup);
            tx = await mocFunctions.swapTPforTC({ from: alice, to: bob, qTP: 23500, qTCmin: 100 });
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
            // qTP: 23500 TP
            // qTC: 100 TC
            // qACfee: 0
            // qFeeToken: 100 (1% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            await expectEvent(tx, [tp0, alice, bob, pEth(23500), pEth(100), 0, pEth(0.5), 0, 0, noVendor]);
          });
        });
      });
    });
  });
};
export { swapTPforTCBehavior };
