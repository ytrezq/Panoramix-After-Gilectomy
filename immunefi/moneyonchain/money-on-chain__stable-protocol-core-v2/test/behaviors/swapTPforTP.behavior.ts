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
  BaseSetupFunction,
  finalFixturedDescribe,
  noVendor,
} from "../helpers/utils";
import { MocCACoinbase, MocCARC20, MocRC20 } from "../../typechain";

const swapTPforTPBehavior = function (setup: BaseSetupFunction) {
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
  let tps: Address[];
  const TP_0 = 0;
  const TP_1 = 1;
  const TP_4 = 4;
  const {
    mocAddresses: { mocFeeFlowAddress },
    queueParams: {
      execCostParams: { swapTPforTPExecCost },
    },
  } = getNetworkDeployParams(hre);

  let coverageBefore: bigint;
  let tx: ContractTransactionResponse;
  let alicePrevTP0Balance: Balance;
  let alicePrevACBalance: Balance;
  let mocPrevACBalance: Balance;
  let mocFeeFlowPrevACBalance: Balance;

  describe("Feature: swap Pegged Token for another Pegged Token", function () {
    async function baseSetup() {
      ({ mocContracts, mocFunctions } = await loadFixture(setup));
      ({ mocImpl, feeToken } = mocContracts);
      ({ deployer, alice, bob, vendor } = await getNamedAccounts());
      // add collateral
      await mocFunctions.mintTC({ from: deployer, qTC: 3000 });
      expectEvent = expectEventFor(mocContracts, "TPSwappedForTP");
      assertACResult = mocFunctions.assertACResult(swapTPforTPExecCost);
      tps = mocContracts.mocPeggedTokens.map((it: any) => it.target.toString());
    }

    describe("GIVEN alice has 23500 TP 0", function () {
      async function aliceHasTP0Setup() {
        await loadFixture(baseSetup);
        await mocFunctions.mintTP({ from: alice, qTP: 23500 });
      }
      finalFixturedDescribe(aliceHasTP0Setup, "WHEN alice tries to swap TP 0 for TP 0", function () {
        it("THEN tx reverts because invalid value", async function () {
          await expect(
            mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_0, from: alice, qTP: 23500 }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.INVALID_VALUE);
        });
      });
      finalFixturedDescribe(aliceHasTP0Setup, "WHEN alice tries to swap using a non-existent TP", function () {
        it("THEN tx reverts", async function () {
          const fakeTP = mocContracts.mocCollateralToken;
          await expect(
            mocFunctions.swapTPforTP({ tpFrom: fakeTP, iTo: TP_0, from: deployer, qTP: 100 }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.INVALID_ADDRESS);
        });
      });
      finalFixturedDescribe(aliceHasTP0Setup, "WHEN alice tries to swap TP 0 for a non-existent TP", function () {
        it("THEN tx reverts", async function () {
          const fakeTP = mocContracts.mocCollateralToken;
          await expect(
            mocFunctions.swapTPforTP({ iFrom: TP_0, tpTo: fakeTP, from: alice, qTP: 100 }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.INVALID_ADDRESS);
        });
      });
      finalFixturedDescribe(aliceHasTP0Setup, "WHEN alice tries to swap 0 TP 0", function () {
        it("THEN tx reverts because the amount of TP is too low and out of precision", async function () {
          await expect(
            mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 0 }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.QTP_BELOW_MINIMUM);
        });
      });
      finalFixturedDescribe(aliceHasTP0Setup, "WHEN alice tries to swap 1 TP 0 to the zero address", function () {
        it("THEN tx reverts because recipient is the zero address", async function () {
          await expect(
            mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, to: CONSTANTS.ZERO_ADDRESS, qTP: 23500 }),
          ).to.be.revertedWith("ERC20: mint to the zero address");
        });
      });
      finalFixturedDescribe(aliceHasTP0Setup, "WHEN alice tries to swap 1 wei TP 0", function () {
        it("THEN tx reverts because the amount of TP is too low and out of precision", async function () {
          await expect(
            mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 1n, applyPrecision: false }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.QTP_BELOW_MINIMUM);
        });
      });
      finalFixturedDescribe(aliceHasTP0Setup, "WHEN alice tries to swap 23501 TP 0", function () {
        it("THEN tx reverts because she has not balance", async function () {
          await expect(
            mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 23501 }),
          ).to.be.revertedWith(ERRORS.ERC20_TRANF_EXCEEDS_BALANCE);
        });
      });
      finalFixturedDescribe(aliceHasTP0Setup, "WHEN alice swap 23500 TP 0 sending 0.99 Asset for fees", function () {
        it("THEN tx reverts because Asset received is below the minimum required", async function () {
          await expect(
            mocFunctions.swapTPforTP({
              iFrom: TP_0,
              iTo: TP_1,
              from: alice,
              qTP: 23500,
              qACmax: "0.999999999999999999",
            }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.INSUFFICIENT_QAC_SENT);
        });
      });
      finalFixturedDescribe(
        aliceHasTP0Setup,
        "WHEN alice swap 23500 TP 0 expecting receive 526 TP 1 as minimum",
        function () {
          /*
            23500 TP 0 = 100 AC
            100 AC = 525 TP 1
          */
          it("THEN tx reverts because Asset received is below the minimum required", async function () {
            await expect(
              mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 23500, qTPmin: 526 }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.QTP_BELOW_MINIMUM);
          });
        },
      );
      finalFixturedDescribe(
        aliceHasTP0Setup,
        "WHEN alice tries to swap 23500 TP 0 for 525 TP 1 via vendor without sending the AC for the markup",
        function () {
          it("THEN tx reverts because AC received is below the minimum required", async function () {
            // qACmax = 1% for qACfee of 100AC
            await expect(
              mocFunctions.swapTPforTP({
                iFrom: TP_0,
                iTo: TP_1,
                from: alice,
                qTP: 23500,
                qTPmin: 525,
                qACmax: 1,
                vendor,
              }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.INSUFFICIENT_QAC_SENT);
          });
        },
      );

      describe("AND TP 0 price provider is deprecated", function () {
        before(async function () {
          await loadFixture(aliceHasTP0Setup);
          await mocContracts.priceProviders[TP_0].deprecatePriceProvider();
        });
        describe("WHEN alice tries to swap TP 0 for TP 1", function () {
          it("THEN tx reverts because invalid price provider", async function () {
            await expect(
              mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 23500 }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.MISSING_PROVIDER_PRICE);
          });
        });
      });
      describe("AND TP 1 price provider is deprecated", function () {
        before(async function () {
          await loadFixture(aliceHasTP0Setup);
          await mocContracts.priceProviders[TP_1].deprecatePriceProvider();
        });
        describe("WHEN alice tries to swap TP 0 for TP 1", function () {
          it("THEN tx reverts because invalid price provider", async function () {
            await expect(
              mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 23500 }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.MISSING_PROVIDER_PRICE);
          });
        });
      });
      describe("AND TP 1 revalues to 0.9", function () {
        before(async function () {
          await loadFixture(aliceHasTP0Setup);
          await mocFunctions.pokePrice(TP_1, 0.9);
        });
        describe("WHEN alice tries to swap 235 wei TP 0", function () {
          it("THEN tx reverts because the amount of TP is too low to swap for TP 1", async function () {
            await expect(
              mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 235n, applyPrecision: false }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.QTP_BELOW_MINIMUM);
          });
        });
      });
      describe("WHEN alice swap 23500(all balance) TP 0 for 525 TP 1", function () {
        /*
            23500 TP 0 = 100 AC
            100 AC = 525 TP 1

            swapTPforTPfee = 1%
          */
        before(async function () {
          await loadFixture(aliceHasTP0Setup);
          [coverageBefore, alicePrevACBalance, mocPrevACBalance, mocFeeFlowPrevACBalance] = await Promise.all([
            mocImpl.getCglb(),
            mocFunctions.assetBalanceOf(alice),
            mocFunctions.acBalanceOf(mocImpl.target.toString()),
            mocFunctions.acBalanceOf(mocFeeFlowAddress),
          ]);
          tx = await mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 23500, qTPmin: 525 });
        });
        it("THEN coverage didn't change", async function () {
          assertPrec(coverageBefore, await mocImpl.getCglb());
        });
        it("THEN nACcb and nTPs matches with AC balance and total supplies", async function () {
          assertPrec(await mocImpl.nACcb(), await mocFunctions.acBalanceOf(mocImpl.target.toString()));
          assertPrec((await mocImpl.pegContainer(TP_0))[0], await mocContracts.mocPeggedTokens[TP_0].totalSupply());
          assertPrec((await mocImpl.pegContainer(TP_1))[0], await mocContracts.mocPeggedTokens[TP_1].totalSupply());
        });
        it("THEN alice TP 0 balances is 0", async function () {
          assertPrec(0, await mocFunctions.tpBalanceOf(TP_0, alice));
        });
        it("THEN alice TP 1 balances is 525", async function () {
          assertPrec(525, await mocFunctions.tpBalanceOf(TP_1, alice));
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
        it("THEN a TPSwappedForTP event is emitted", async function () {
          // iFrom: 0
          // iTo: 1
          // sender: alice
          // receiver: alice
          // qTPfrom: 23500 TP
          // qTPto: 525 TP
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          await expectEvent(tx, [tps[0], tps[1], alice, alice, pEth(23500), pEth(525), pEth(1), 0, 0, 0, noVendor]);
        });
        it("THEN a Pegged Token 0 Transfer event is emitted", async function () {
          // from: Moc
          // to: Zero Address
          // amount: 23500 TP
          await expect(tx)
            .to.emit(mocContracts.mocPeggedTokens[TP_0], "Transfer")
            .withArgs(mocImpl.target.toString(), CONSTANTS.ZERO_ADDRESS, pEth(23500));
        });
        it("THEN a Pegged Token 1 Transfer event is emitted", async function () {
          // from: Zero Address
          // to: alice
          // amount: 525 TP
          await expect(tx)
            .to.emit(mocContracts.mocPeggedTokens[TP_1], "Transfer")
            .withArgs(CONSTANTS.ZERO_ADDRESS, alice, pEth(525));
        });
      });
      describe("WHEN alice swap 2350(10% of balance) TP 0 for 52.5 TP 1 to bob", function () {
        /*
            2350 TP 0 = 10 AC
            10 AC = 52.5 TP 1

            swapTPforTPfee = 1%
          */
        before(async function () {
          await loadFixture(aliceHasTP0Setup);
          coverageBefore = await mocImpl.getCglb();
          alicePrevTP0Balance = await mocFunctions.tpBalanceOf(TP_0, alice);
          mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          tx = await mocFunctions.swapTPforTP({
            iFrom: TP_0,
            iTo: TP_1,
            from: alice,
            to: bob,
            qTP: 2350,
            qTPmin: 5.25,
          });
        });
        it("THEN coverage didn't change", async function () {
          assertPrec(coverageBefore, await mocImpl.getCglb());
        });
        it("THEN alice TP 0 balances decrease 2350 TP", async function () {
          const aliceActualTP0Balance = await mocFunctions.tpBalanceOf(TP_0, alice);
          const diff = alicePrevTP0Balance - aliceActualTP0Balance;
          assertPrec(2350, diff);
        });
        it("THEN bob TP 1 balances is 52.5", async function () {
          assertPrec(52.5, await mocFunctions.tpBalanceOf(TP_1, bob));
        });
        it("THEN Moc balance didn't change", async function () {
          assertPrec(mocPrevACBalance, await mocFunctions.acBalanceOf(mocImpl.target.toString()));
        });
        it("THEN a TPSwappedForTP event is emitted", async function () {
          // iFrom: 0
          // iTo: 1
          // sender: alice
          // receiver: bob
          // qTPfrom: 2350 TP
          // qTPto: 52.5 TP
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          const args = [tps[0], tps[1], alice, bob, pEth(2350), pEth(52.5), pEth(10 * 0.01), 0, 0, 0, noVendor];
          await expectEvent(tx, args);
        });
      });
      describe("WHEN alice swaps 23500 TP 0 for 525 TP 1 via vendor", function () {
        let alicePrevACBalance: Balance;
        let vendorPrevACBalance: Balance;
        let tx: ContractTransactionResponse;
        before(async function () {
          await loadFixture(aliceHasTP0Setup);
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          vendorPrevACBalance = await mocFunctions.acBalanceOf(vendor);
          tx = await mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 23500, qTPmin: 525, vendor });
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
        it("THEN a TPSwappedForTP event is emitted", async function () {
          // iFrom: 0
          // iTo: 1
          // sender: alice
          // receiver: alice
          // qTPfrom: 23500 TP
          // qTPto: 525 TP
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 10% AC
          // qFeeTokenVendorMarkup: 0
          const args = [tps[0], tps[1], alice, alice, pEth(23500), pEth(525), pEth(1), 0, pEth(10), 0, vendor];
          await expectEvent(tx, args);
        });
      });
      describe("WHEN alice swaps 23500 TP 0 for 525 TP 1 to bob via vendor", function () {
        let tx: ContractTransactionResponse;
        before(async function () {
          await loadFixture(aliceHasTP0Setup);
          tx = await mocFunctions.swapTPforTP({
            iFrom: TP_0,
            iTo: TP_1,
            from: alice,
            to: bob,
            qTP: 23500,
            qTPmin: 525,
            vendor,
          });
        });
        it("THEN a TPSwappedForTP event is emitted", async function () {
          // iFrom: 0
          // iTo: 1
          // sender: alice
          // receiver: bob
          // qTPfrom: 23500 TP
          // qTPto: 525 TP
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 10% AC
          // qFeeTokenVendorMarkup: 0
          const args = [tps[0], tps[1], alice, bob, pEth(23500), pEth(525), pEth(1), 0, pEth(10), 0, vendor];
          await expectEvent(tx, args);
        });
      });
      describe("WHEN alice swap 2350 TP 0 for 52.5 TP 4. ctargemaTP 4 > ctargemaTP 0, so coverage is checked", function () {
        /*
          ctargemaTP0 = 5
          ctargemaTP4 = 6
        */
        before(async function () {
          await loadFixture(aliceHasTP0Setup);
          coverageBefore = await mocImpl.getCglb();
          mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          tx = await mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_4, from: alice, qTP: 2350, qTPmin: 52.5 });
        });
        it("THEN coverage didn't change", async function () {
          assertPrec(coverageBefore, await mocImpl.getCglb());
        });
        it("THEN Moc balance didn't change", async function () {
          assertPrec(mocPrevACBalance, await mocFunctions.acBalanceOf(mocImpl.target.toString()));
        });
        it("THEN a TPSwappedForTP event is emitted", async function () {
          // iFrom: 0
          // iTo: 4
          // sender: alice
          // receiver: alice
          // qTPfrom: 2350 TP
          // qTPto: 52.5 TP
          // qACfee: 1% AC
          // qFeeToken: 0
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          const args = [tps[0], tps[4], alice, alice, pEth(2350), pEth(52.5), pEth(10 * 0.01), 0, 0, 0, noVendor];
          await expectEvent(tx, args);
        });
      });
      describe("AND 2500 TP 4 are minted", function () {
        before(async function () {
          await loadFixture(aliceHasTP0Setup);
          await mocFunctions.mintTP({ i: TP_4, from: deployer, qTP: 2500 });
        });
        it("THEN tx reverts because there is not enough TP 4 to mint", async function () {
          await expect(
            mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_4, from: alice, qTP: 2350, qTPmin: 52.5 }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.INSUFFICIENT_TP_TO_MINT);
        });
      });
      describe("AND TP 0 revalues to 10.5", function () {
        /*
          nAC = 3100    
          nTP = 23500
          lckAC = 2238.09
          coverage = 1.38
        */
        async function TP0RevaluesSetup() {
          await loadFixture(aliceHasTP0Setup);
          await mocFunctions.pokePrice(TP_0, 10.5);
        }
        describe("WHEN alice swap 2350 TP 0 for 1175 TP 1", function () {
          /*
            ctargemaTP0 = 5
            ctargemaTP1 = 4
          */
          before(async function () {
            await loadFixture(TP0RevaluesSetup);
            coverageBefore = await mocImpl.getCglb();
            mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
            tx = await mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 2350, qTPmin: 1175 });
          });
          it("THEN coverage didn't change", async function () {
            assertPrec(coverageBefore, await mocImpl.getCglb());
          });
          it("THEN Moc balance didn't change", async function () {
            assertPrec(mocPrevACBalance, await mocFunctions.acBalanceOf(mocImpl.target.toString()));
          });
          it("THEN a TPSwappedForTP event is emitted", async function () {
            // iFrom: 0
            // iTo: 1
            // sender: alice
            // receiver: alice
            // qTPfrom: 2350 TP
            // qTPto: 1175 TP
            // qACfee: 1% AC
            // qFeeToken: 0
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const qACfee = pEth("2.238095238095238095");
            await expectEvent(tx, [tps[0], tps[1], alice, alice, pEth(2350), pEth(1175), qACfee, 0, 0, 0, noVendor]);
          });
        });
        finalFixturedDescribe(
          TP0RevaluesSetup,
          "WHEN alice swap 2350 TP 0 for 1175 TP 4. ctargemaTP 4 > ctargemaTP 0, so coverage is checked",
          function () {
            /*
            ctargemaTP0 = 5
            ctargemaTP4 = 6
          */
            it("THEN tx reverts because low coverage", async function () {
              await expect(
                mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_4, from: alice, qTP: 2350, qTPmin: 1175 }),
              ).to.be.revertedWithCustomError(mocImpl, ERRORS.LOW_COVERAGE);
            });
          },
        );
      });
      describe("AND TP 0 devalues to 470", function () {
        /*
          nAC = 3100    
          nTP = 23500 + 11750
          lckAC = 50 + 25
          nACgain = 5
          coverage = 121.37
        */
        async function TP0DevaluesSetup() {
          await loadFixture(aliceHasTP0Setup);
          await mocFunctions.pokePrice(TP_0, 470);
        }
        describe("WHEN alice swap 23500 TP 0 for 262.5 TP 1", function () {
          /*
            ctargemaTP0 = 5
            ctargemaTP1 = 4
          */
          before(async function () {
            await loadFixture(TP0DevaluesSetup);
            coverageBefore = await mocImpl.getCglb();
            mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
            tx = await mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 23500, qTPmin: 262.5 });
          });
          it("THEN coverage didn't change", async function () {
            assertPrec(coverageBefore, await mocImpl.getCglb());
          });
          it("THEN Moc balance didn't change", async function () {
            assertPrec(mocPrevACBalance, await mocFunctions.acBalanceOf(mocImpl.target.toString()));
          });
          it("THEN a TPSwappedForTP event is emitted", async function () {
            // iFrom: 0
            // iTo: 1
            // sender: alice
            // receiver: alice
            // qTPfrom: 23500 TP
            // qTPto: 262.5 TP
            // qACfee: 1% AC
            // qFeeToken: 0
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const args = [tps[0], tps[1], alice, alice, pEth(23500), pEth(262.5), pEth(50 * 0.01), 0, 0, 0, noVendor];
            await expectEvent(tx, args);
          });
        });
      });
      describe("AND alice has FeeToken to pay fees", function () {
        let alicePrevACBalance: Balance;
        let alicePrevFeeTokenBalance: Balance;
        let mocFeeFlowPrevACBalance: Balance;
        let mocFeeFlowPrevFeeTokenBalance: Balance;
        let tx: ContractTransactionResponse;
        async function aliceHasFeeTokenSetup() {
          await loadFixture(aliceHasTP0Setup);
          // mint FeeToken to alice
          await feeToken.mint(alice, pEth(50));
          await feeToken.connect(await ethers.getSigner(alice)).approve(mocImpl.target.toString(), pEth(50));

          // initialize previous balances
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          alicePrevFeeTokenBalance = await feeToken.balanceOf(alice);
          mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          mocFeeFlowPrevFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
        }
        describe("WHEN alice swaps 23500 TP 0 for 525 TP 1", function () {
          before(async function () {
            await loadFixture(aliceHasFeeTokenSetup);
            tx = await mocFunctions.swapTPforTP({ iFrom: TP_0, iTo: TP_1, from: alice, qTP: 23500, qTPmin: 525 });
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
            // iFrom: 0
            // iTo: 0
            // sender: alice
            // receiver: alice
            // qTPfrom: 23500 TP
            // qTPto: 525 TP
            // qACfee: 0
            // qFeeToken: 100 (1% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const args = [tps[0], tps[1], alice, alice, pEth(23500), pEth(525), 0, pEth(0.5), 0, 0, noVendor];
            await expectEvent(tx, args);
          });
        });
        describe("WHEN alice swaps 23500 TP 0 for 525 TP 1", function () {
          before(async function () {
            await loadFixture(aliceHasFeeTokenSetup);
            tx = await mocFunctions.swapTPforTP({
              iFrom: TP_0,
              iTo: TP_1,
              from: alice,
              to: bob,
              qTP: 23500,
              qTPmin: 525,
            });
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
            // iFrom: 0
            // iTo: 1
            // sender: alice
            // receiver: bob
            // qTPfrom: 23500 TP
            // qTPto: 525 TP
            // qACfee: 0
            // qFeeToken: 100 (1% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const args = [tps[0], tps[1], alice, bob, pEth(23500), pEth(525), 0, pEth(0.5), 0, 0, noVendor];
            await expectEvent(tx, args);
          });
        });
      });
    });
  });
};
export { swapTPforTPBehavior };
