import hre, { getNamedAccounts, ethers } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/dist/types";
import { expect } from "chai";
import { assertPrec } from "../helpers/assertHelper";
import { Balance, CONSTANTS, ERRORS, pEth, expectEventFor, getNetworkDeployParams, noVendor } from "../helpers/utils";
import { MocCACoinbase, MocCARC20 } from "../../typechain";

const mintTCBehavior = function () {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let deployer: Address;
  let alice: Address;
  let bob: Address;
  let vendor: Address;
  let expectTCMinted: any;
  let assertACResult: any;
  const TP_0 = 0;
  const {
    mocAddresses: { mocFeeFlowAddress },
    feeParams,
    queueParams: {
      execCostParams: { tcMintExecCost },
    },
  } = getNetworkDeployParams(hre);

  describe("Feature: mint Collateral Token", function () {
    beforeEach(async function () {
      mocContracts = this.mocContracts;
      mocFunctions = this.mocFunctions;
      ({ mocImpl } = mocContracts);
      ({ deployer, alice, bob, vendor } = await getNamedAccounts());
      expectTCMinted = expectEventFor(mocContracts, "TCMinted");
      assertACResult = mocFunctions.assertACResult(tcMintExecCost);
    });
    describe("WHEN alice tries to mint 0 TC", function () {
      it("THEN tx reverts because the amount of TC is too low and out of precision", async function () {
        await expect(mocFunctions.mintTC({ from: alice, qTC: 0 })).to.be.revertedWithCustomError(
          mocImpl,
          ERRORS.QAC_NEEDED_MUST_BE_GREATER_ZERO,
        );
      });
    });
    describe("WHEN alice sends 10 Asset to mint 100 TC", function () {
      it("THEN tx reverts because the amount of AC is insufficient", async function () {
        await expect(mocFunctions.mintTC({ from: alice, qTC: 100, qACmax: 10 })).to.be.revertedWithCustomError(
          mocImpl,
          ERRORS.INSUFFICIENT_QAC_SENT,
        );
      });
    });
    describe("WHEN alice sends 100 Asset to mint 100 TC to the zero address", function () {
      it("THEN tx reverts because recipient is the zero address", async function () {
        await expect(mocFunctions.mintTC({ from: alice, to: CONSTANTS.ZERO_ADDRESS, qTC: 100 })).to.be.revertedWith(
          ERRORS.ERC20_MINT_TO_ZERO_ADDRESS,
        );
      });
    });
    describe("WHEN alice sends 105(exactly amount) Asset to mint 100 TC", function () {
      let tx: ContractTransactionResponse;
      let alicePrevACBalance: Balance;
      beforeEach(async function () {
        alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
        tx = await mocFunctions.mintTC({ from: alice, qTC: 100, qACmax: 105 });
      });
      it("THEN alice receives 100 TC", async function () {
        assertPrec(100, await mocFunctions.tcBalanceOf(alice));
      });
      it("THEN Moc balance increase 100 AC", async function () {
        assertPrec(100, await mocFunctions.acBalanceOf(mocImpl.target.toString()));
      });
      it("THEN nACcb and nTCcb matches with AC balance and total supply", async function () {
        assertPrec(await mocImpl.nACcb(), await mocFunctions.acBalanceOf(mocImpl.target.toString()));
        assertPrec(await mocImpl.nTCcb(), await mocContracts.mocCollateralToken.totalSupply());
      });
      it("THEN Moc Fee Flow balance increase 5% of 100 AC", async function () {
        assertPrec(100 * 0.05, await mocFunctions.acBalanceOf(mocFeeFlowAddress));
      });
      it("THEN alice balance decrease 100 Asset + 5% for Moc Fee Flow", async function () {
        const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
        const diff = alicePrevACBalance - aliceActualACBalance;
        assertACResult(100 * 1.05, diff);
      });
      it("THEN a TCMinted event is emitted", async function () {
        // sender: alice
        // receiver: alice
        // qTC: 100 TC
        // qAC: 100 AC + 5% for Moc Fee Flow
        // qACfee: %5 AC
        // qFeeToken: 0
        // qACVendorMarkup: 0
        // qFeeTokenVendorMarkup: 0
        const args = [alice, alice, pEth(100), pEth(100 * 1.05), pEth(100 * 0.05), 0, 0, 0, noVendor];
        await expectTCMinted(tx, args);
      });
      it("THEN a Collateral Token Transfer event is emitted", async function () {
        // from: Zero Address
        // to: alice
        // amount: 100 TC
        await expect(tx)
          .to.emit(mocContracts.mocCollateralToken, "Transfer")
          .withArgs(CONSTANTS.ZERO_ADDRESS, alice, pEth(100));
      });
      describe("AND alice sends 1000(exceeded amount) Asset to mint 100 TC", function () {
        let alicePrevACBalance: Balance;
        let alicePrevTCBalance: Balance;
        let mocPrevACBalance: Balance;
        let mocFeeFlowPrevACBalance: Balance;
        beforeEach(async function () {
          alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
          alicePrevTCBalance = await mocFunctions.tcBalanceOf(alice);
          mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          await mocFunctions.mintTC({ from: alice, qTC: 100 });
        });
        it("THEN alice receives 100 TC", async function () {
          const aliceActualTCBalance = await mocFunctions.tcBalanceOf(alice);
          const diff = aliceActualTCBalance - alicePrevTCBalance;
          assertPrec(100, diff);
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
    });
    describe("WHEN alice mints 100 TC via vendor", function () {
      let alicePrevACBalance: Balance;
      let vendorPrevACBalance: Balance;
      let tx: ContractTransactionResponse;
      beforeEach(async function () {
        alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
        vendorPrevACBalance = await mocFunctions.acBalanceOf(vendor);
        tx = await mocFunctions.mintTC({ from: alice, qTC: 100, vendor });
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
      it("THEN a TCMinted event is emitted", async function () {
        // sender: alice
        // receiver: alice
        // qTC: 100 TC
        // qAC: 100 AC + 5% for Moc Fee Flow + 10% for vendor
        // qACfee: 5% qAC
        // qFeeToken: 0
        // qACVendorMarkup: 10% qAC
        // qFeeTokenVendorMarkup: 0
        const args = [alice, alice, pEth(100), pEth(100 * 1.15), pEth(100 * 0.05), 0, pEth(100 * 0.1), 0, vendor];
        await expectTCMinted(tx, args);
      });
    });
    describe("WHEN alice mints 100 TC to bob via vendor", function () {
      let tx: ContractTransactionResponse;
      beforeEach(async function () {
        tx = await mocFunctions.mintTC({ from: alice, to: bob, qTC: 100, vendor });
      });
      it("THEN a TCMinted event is emitted", async function () {
        // sender: alice
        // receiver: bob
        // qTC: 100 TC
        // qAC: 100 AC + 5% for Moc Fee Flow + 10% for vendor
        // qACfee: 5% qAC
        // qFeeToken: 0
        // qACVendorMarkup: 10% qAC
        // qFeeTokenVendorMarkup: 0
        const args = [alice, bob, pEth(100), pEth(100 * 1.15), pEth(100 * 0.05), 0, pEth(100 * 0.1), 0, vendor];
        await expectTCMinted(tx, args);
      });
    });
    describe("WHEN feeRetainer is set to 20% AND alice sends 105 Asset to mint 100 TC to bob", function () {
      let tx: ContractTransactionResponse;
      let alicePrevACBalance: Balance;
      beforeEach(async function () {
        alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
        await mocImpl.setOperationsFee({ ...feeParams, feeRetainer: pEth(0.2) }); // 20%
        tx = await mocFunctions.mintTC({ from: alice, to: bob, qTC: 100 });
      });
      it("THEN bob receives 100 TC", async function () {
        assertPrec(100, await mocFunctions.tcBalanceOf(bob));
      });
      it("THEN Moc balance increase 101 AC", async function () {
        assertPrec(101, await mocFunctions.acBalanceOf(mocImpl.target.toString()));
      });
      it("THEN Moc Fee Flow balance increase 4% of 100 AC", async function () {
        assertPrec(100 * 0.04, await mocFunctions.acBalanceOf(mocFeeFlowAddress));
      });
      it("THEN alice balance decrease 100 Asset + 5% for Moc Fee Flow", async function () {
        const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
        const diff = alicePrevACBalance - aliceActualACBalance;
        assertACResult(100 * 1.05, diff);
      });
      it("THEN a TCMinted event is emitted", async function () {
        // sender: alice
        // receiver: bob
        // qTC: 100 TC
        // qAC: 100 AC + 5% for Moc Fee Flow
        // qACfee: %5 AC
        // qFeeToken: 0
        // qACVendorMarkup: 0
        // qFeeTokenVendorMarkup: 0
        const args = [alice, bob, pEth(100), pEth(100 * 1.05), pEth(100 * 0.05), 0, 0, 0, noVendor];
        await expectTCMinted(tx, args);
      });
    });
    describe("GIVEN 3000 TC and 100 TP are minted", function () {
      beforeEach(async function () {
        await mocFunctions.mintTC({ from: deployer, qTC: 3000 });
        await mocFunctions.mintTP({ from: deployer, qTP: 100 });
      });
      describe("AND Collateral Asset relation with Pegged Token price falls to 1 making TC price falls too", function () {
        /*  
        nAC = 3000.425    
        nTP = 100
        lckAC = 100
        => pTCac = 0.9668
        */
        beforeEach(async function () {
          await mocFunctions.pokePrice(TP_0, 1);
        });
        describe("WHEN alice tries to mint 1 wei TC", function () {
          it("THEN tx reverts because the amount of TC is too low and out of precision", async function () {
            await expect(
              mocFunctions.mintTC({ from: alice, qTC: 1n, applyPrecision: false }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.QAC_NEEDED_MUST_BE_GREATER_ZERO);
          });
        });
        describe("WHEN alice mints 100 TC", function () {
          let alicePrevACBalance: Balance;
          beforeEach(async function () {
            alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
            await mocFunctions.mintTC({ from: alice, qTC: 100 });
          });
          it("THEN alice spends 101.51 assets instead of 105", async function () {
            const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
            const diff = alicePrevACBalance - aliceActualACBalance;
            assertACResult("101.51489361702127656", diff);
          });
        });
      });
      describe("AND Collateral Asset relation with Pegged Token price falls to 1/15.5", function () {
        beforeEach(async function () {
          await mocFunctions.pokePrice(TP_0, "0.064516129032258064");
        });
        describe("WHEN Alice tries to mint 100 TC", function () {
          /*  
            nAC = 3100    
            nTP = 100
            lckAC = 1550
            => coverage = 2 
        */
          it("THEN tx reverts because coverage is below the protected threshold", async function () {
            await expect(mocFunctions.mintTC({ from: alice, qTC: 100 })).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.LOW_COVERAGE,
            );
          });
        });
      });
      describe("AND Pegged Token has been devaluated to 500 making TC price rices", function () {
        /*  
        nAC = 3000.425    
        nTP = 100 + 56.3829
        lckAC = 0.3127
        nACgain = 0.02255
        => pTCac = 1.00003
        => coverage = 9593.12
        */
        beforeEach(async function () {
          await mocFunctions.pokePrice(TP_0, 500);
        });
        it("THEN TC price is 1.00003", async function () {
          assertPrec("1.000030070921985815", await mocImpl.getPTCac());
        });
        it("THEN coverage is 9593.12", async function () {
          assertPrec("9593.125170068027230461", await mocImpl.getCglb());
        });
        describe("WHEN alice mints 100 TC", function () {
          let alicePrevACBalance: Balance;
          beforeEach(async function () {
            alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
            await mocFunctions.mintTC({ from: alice, qTC: 100 });
          });
          it("THEN alice spends 105.003 assets instead of 105", async function () {
            const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
            const diff = alicePrevACBalance - aliceActualACBalance;
            assertACResult("105.003157446808510575", diff);
          });
        });
      });
      describe("AND Pegged Token has been revaluated to 100 making TC price falls", function () {
        /*  
        nAC = 3000.425    
        nTP = 100
        lckAC = 1
        nACgain = -0.3446
        => pTCac = 0.9998
        => coverage = 3000.425
        */
        beforeEach(async function () {
          await mocFunctions.pokePrice(TP_0, 100);
        });
        it("THEN TC price is 0.9998", async function () {
          assertPrec("0.999808510638297872", await mocImpl.getPTCac());
        });
        it("THEN coverage is 3000.425", async function () {
          assertPrec("3000.425531914893617021", await mocImpl.getCglb());
        });
        describe("WHEN alice mints 100 TC", function () {
          let alicePrevACBalance: Balance;
          beforeEach(async function () {
            alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
            await mocFunctions.mintTC({ from: alice, qTC: 100 });
          });
          it("THEN alice spends 104.979 assets instead of 105", async function () {
            const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
            const diff = alicePrevACBalance - aliceActualACBalance;
            assertACResult("104.979893617021276560", diff);
          });
        });
      });
      describe("AND Pegged Token has been revaluated making lckAC bigger than total AC in the protocol", function () {
        // this test is to check that tx doesn't fail because underflow doing totalACAvailable - lckAC
        beforeEach(async function () {
          await mocFunctions.pokePrice(TP_0, "0.00000001");
        });
        it("THEN tx reverts because coverage is below the protected threshold", async function () {
          expect((await mocImpl.getCglb()) < pEth(1)); // check that lckAC > totalACAvailable
          await expect(mocFunctions.mintTC({ from: alice, qTC: 100 })).to.be.revertedWithCustomError(
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
      beforeEach(async function () {
        // mint FeeToken to alice
        await mocContracts.feeToken.mint(alice, pEth(50));
        await mocContracts.feeToken.connect(await ethers.getSigner(alice)).approve(mocImpl.target.toString(), pEth(50));

        // initialize previous balances
        alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
        alicePrevFeeTokenBalance = await mocContracts.feeToken.balanceOf(alice);
        mocFeeFlowPrevACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
        mocFeeFlowPrevFeeTokenBalance = await mocContracts.feeToken.balanceOf(mocFeeFlowAddress);
      });
      describe("WHEN alice mints 100 TC", function () {
        beforeEach(async function () {
          tx = await mocFunctions.mintTC({ from: alice, qTC: 100 });
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
          // sender: alice
          // receiver: alice
          // qTC: 100 TC
          // qAC: 100 AC
          // qACfee: 0 AC
          // qFeeToken: 100 (5% * 50%)
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          const args = [alice, alice, pEth(100), pEth(100), 0, pEth(100 * 0.05 * 0.5), 0, 0, noVendor];
          await expectTCMinted(tx, args);
        });
      });
      describe("WHEN alice mints 100 TC to bob", function () {
        beforeEach(async function () {
          tx = await mocFunctions.mintTC({ from: alice, to: bob, qTC: 100 });
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
          // sender: alice
          // receiver: bob
          // qTC: 100 TC
          // qAC: 100 AC
          // qACfee: 0 AC
          // qFeeToken: 100 (5% * 50%)
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          const args = [alice, bob, pEth(100), pEth(100), 0, pEth(100 * 0.05 * 0.5), 0, 0, noVendor];
          await expectTCMinted(tx, args);
        });
      });
    });
  });
};

export { mintTCBehavior };
