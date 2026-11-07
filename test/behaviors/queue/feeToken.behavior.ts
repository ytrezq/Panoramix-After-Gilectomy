import { getNamedAccounts, ethers } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { expect } from "chai";
import { Address } from "hardhat-deploy/dist/types";
import { assertPrec } from "../../helpers/assertHelper";
import { Balance, ERRORS, expectEventFor, noVendor, OperType, pEth } from "../../helpers/utils";
import { ERC20Mock, MocCACoinbase, MocCARC20, MocQueue, PriceProviderMock } from "../../../typechain";

const feeTokenBehavior = function () {
  let mocImpl: MocCACoinbase | MocCARC20;
  let mocQueue: MocQueue;
  let feeToken: ERC20Mock;
  let feeTokenPriceProvider: PriceProviderMock;
  let mocContracts: any;
  let mocFunctions: any;
  let alice: Address;
  let vendor: Address;
  let operator: Address;
  let spender: Address;
  let tx: ContractTransactionResponse;
  let expectTCMinted: any;
  let expectTCRedeemed: any;

  describe("Feature: Fee Token as fee payment method", function () {
    beforeEach(async function () {
      mocContracts = this.mocContracts;
      mocFunctions = this.mocFunctions;
      ({ alice, vendor } = await getNamedAccounts());
      ({ feeToken, feeTokenPriceProvider, mocImpl, mocQueue } = mocContracts);
      operator = alice;
      spender = mocImpl.target.toString();
      // give some TC to alice
      await mocFunctions.mintTC({ from: alice, qTC: 1000 });
      expectTCMinted = expectEventFor(mocContracts, "TCMinted");
      expectTCRedeemed = expectEventFor(mocContracts, "TCRedeemed");
    });
    describe("GIVEN alice has 50 Fee Token", function () {
      beforeEach(async function () {
        await feeToken.mint(alice, pEth(50));
      });
      describe("WHEN alice mints 100 TC without sending Fee Token approval", function () {
        beforeEach(async function () {
          tx = await mocFunctions.mintTC({ from: alice, qTC: 100 });
        });
        it("THEN a AC is used as fee payment method", async function () {
          // sender: alice
          // receiver: alice
          // qTC: 100 TC
          // qAC: 100 AC + 5% for Moc Fee Flow
          // qACfee: %5 AC
          // qFeeToken: 0
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          await expectTCMinted(tx, [operator, alice, pEth(100), pEth(105), pEth(5), 0, 0, 0, noVendor]);
        });
      });
      describe("AND alice approves 25 Fee Token to Moc Core", function () {
        beforeEach(async function () {
          await feeToken.connect(await ethers.getSigner(alice)).approve(spender, pEth(25));
        });
        describe("WHEN alice mints 10000 TC and doesn't have enough Fee Token allowance", function () {
          beforeEach(async function () {
            await feeToken.mint(alice, pEth(10000));
            tx = await mocFunctions.mintTC({ from: alice, qTC: 10000 });
          });
          it("THEN a AC is used as fee payment method", async function () {
            // sender: alice
            // receiver: alice
            // qTC: 10000 TC
            // qAC: 10000 AC + 5% for Moc Fee Flow
            // qACfee: %5 AC
            // qFeeToken: 0
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const args = [operator, alice, pEth(10000), pEth(10000 * 1.05), pEth(10000 * 0.05), 0, 0, 0, noVendor];
            await expectTCMinted(tx, args);
          });
        });
        describe("WHEN alice mints 10000 TC and doesn't have enough Fee Token balance", function () {
          beforeEach(async function () {
            await feeToken.connect(await ethers.getSigner(alice)).approve(spender, pEth(10000));
            tx = await mocFunctions.mintTC({ from: alice, qTC: 10000 });
          });
          it("THEN a AC is used as fee payment method", async function () {
            // sender: alice
            // receiver: alice
            // qTC: 10000 TC
            // qAC: 10000 AC + 5% for Moc Fee Flow
            // qACfee: %5 AC
            // qFeeToken: 0
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const args = [operator, alice, pEth(10000), pEth(10000 * 1.05), pEth(10000 * 0.05), 0, 0, 0, noVendor];
            await expectTCMinted(tx, args);
          });
        });
        describe("AND Fee Token price provider doesn't have a valid price", function () {
          beforeEach(async function () {
            await feeTokenPriceProvider.deprecatePriceProvider();
          });
          describe("WHEN alice mints 100 TC", function () {
            beforeEach(async function () {
              tx = await mocFunctions.mintTC({ from: alice, qTC: 100 });
            });
            it("THEN a AC is used as fee payment method", async function () {
              // sender: alice
              // receiver: alice
              // qTC: 100 TC
              // qAC: 100 AC + 5% for Moc Fee Flow
              // qACfee: %5 AC
              // qFeeToken: 0
              // qACVendorMarkup: 0
              // qFeeTokenVendorMarkup: 0
              const args = [operator, alice, pEth(100), pEth(100 * 1.05), pEth(100 * 0.05), 0, 0, 0, noVendor];
              await expectTCMinted(tx, args);
            });
          });
        });
        describe("WHEN alice mints 100 TC", function () {
          beforeEach(async function () {
            tx = await mocFunctions.mintTC({ from: alice, qTC: 100 });
          });
          it("THEN Fee Token is used as fee payment method", async function () {
            // sender: alice
            // receiver: alice
            // qTC: 100 TC
            // qAC: 100 AC
            // qACfee: 0 AC
            // qFeeToken: 100 AC (5% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const args = [operator, alice, pEth(100), pEth(100), 0, pEth(100 * 0.05 * 0.5), 0, 0, noVendor];
            await expectTCMinted(tx, args);
          });
        });
        describe("WHEN alice redeems 100 TC", function () {
          beforeEach(async function () {
            tx = await mocFunctions.redeemTC({ from: alice, qTC: 100 });
          });
          it("THEN Fee Token is used as fee payment method", async function () {
            // sender: alice
            // receiver: alice
            // qTC: 100 TC
            // qAC: 100 AC
            // qACfee: 0 AC
            // qFeeToken: 100 AC (5% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 0
            const args = [operator, operator, pEth(100), pEth(100), 0, pEth(100 * 0.05 * 0.5), 0, 0, noVendor];
            await expectTCRedeemed(tx, args);
          });
        });
        describe("WHEN alice mints 100 TC via vendor", function () {
          let alicePrevFeeTokenBalance: Balance;
          let vendorPrevFeeTokenBalance: Balance;
          beforeEach(async function () {
            alicePrevFeeTokenBalance = await feeToken.balanceOf(alice);
            vendorPrevFeeTokenBalance = await feeToken.balanceOf(vendor);
            tx = await mocFunctions.mintTC({ from: alice, qTC: 100, vendor });
          });
          it("THEN alice Fee Token balance decrease 12.5 (100 qAC + 2.5% qFeeToken + 10% qFeeTokenVendorMarkup)", async function () {
            const aliceActualVendorBalance = await feeToken.balanceOf(alice);
            const diff = alicePrevFeeTokenBalance - aliceActualVendorBalance;
            assertPrec(12.5, diff);
          });
          it("THEN vendor Fee Token balance increase 10", async function () {
            const vendorActualVendorBalance = await feeToken.balanceOf(vendor);
            const diff = vendorActualVendorBalance - vendorPrevFeeTokenBalance;
            assertPrec(10, diff);
          });
          it("THEN a TCMinted event is emitted", async function () {
            // sender: alice
            // receiver: alice
            // qTC: 100 TC
            // qAC: 100 AC
            // qACfee: 0
            // qFeeToken: 100 AC (5% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 10% qAC
            const args = [operator, alice, pEth(100), pEth(100), 0, pEth(100 * 0.05 * 0.5), 0, pEth(10), vendor];
            await expectTCMinted(tx, args);
          });
        });
        describe("WHEN alice redeems 100 TC via vendor", function () {
          let alicePrevFeeTokenBalance: Balance;
          let vendorPrevFeeTokenBalance: Balance;
          beforeEach(async function () {
            alicePrevFeeTokenBalance = await feeToken.balanceOf(alice);
            vendorPrevFeeTokenBalance = await feeToken.balanceOf(vendor);
            tx = await mocFunctions.redeemTC({ from: alice, qTC: 100, vendor });
          });
          it("THEN alice Fee Token balance decrease 12.5 (100 qAC + 2.5% qFeeToken + 10% qFeeTokenVendorMarkup)", async function () {
            const aliceActualVendorBalance = await feeToken.balanceOf(alice);
            const diff = alicePrevFeeTokenBalance - aliceActualVendorBalance;
            assertPrec(12.5, diff);
          });
          it("THEN vendor Fee Token balance increase 10", async function () {
            const vendorActualVendorBalance = await feeToken.balanceOf(vendor);
            const diff = vendorActualVendorBalance - vendorPrevFeeTokenBalance;
            assertPrec(10, diff);
          });
          it("THEN a TCRedeemed event is emitted", async function () {
            // sender: alice
            // receiver: alice
            // qTC: 100 TC
            // qAC: 100 AC
            // qACfee: 0
            // qFeeToken: 100 AC (5% * 50%)
            // qACVendorMarkup: 0
            // qFeeTokenVendorMarkup: 10% qAC
            const args = [operator, operator, pEth(100), pEth(100), 0, pEth(100 * 0.05 * 0.5), 0, pEth(10), vendor];
            await expectTCRedeemed(tx, args);
          });
        });
        describe("AND Fee Token price falls 10 times AC price", function () {
          // 1 Fee Token = 0.1 Assets
          beforeEach(async function () {
            await feeTokenPriceProvider.poke(pEth(0.1));
          });
          describe("WHEN alice mints 100 TC", function () {
            beforeEach(async function () {
              tx = await mocFunctions.mintTC({ from: alice, qTC: 100 });
            });
            it("THEN 25 Fee Token are spent instead of 2.5", async function () {
              // sender: alice
              // receiver: alice
              // qTC: 100 TC
              // qAC: 100 AC
              // qACfee: 0 AC
              // qFeeToken: 100 AC (5% * 50%) / 0.1
              // qACVendorMarkup: 0
              // qFeeTokenVendorMarkup: 0
              const args = [operator, alice, pEth(100), pEth(100), 0, pEth(1000 * 0.05 * 0.5), 0, 0, noVendor];
              await expectTCMinted(tx, args);
            });
          });
          describe("WHEN alice redeems 100 TC", function () {
            beforeEach(async function () {
              tx = await mocFunctions.redeemTC({ from: alice, qTC: 100 });
            });
            it("THEN 25 Fee Token are spent instead of 2.5", async function () {
              // sender: alice
              // receiver: alice
              // qTC: 100 TC
              // qAC: 100 AC
              // qACfee: 0 AC
              // qFeeToken: 100 AC (5% * 50%) / 0.1
              // qACVendorMarkup: 0
              // qFeeTokenVendorMarkup: 0
              const args = [operator, operator, pEth(100), pEth(100), 0, pEth(1000 * 0.05 * 0.5), 0, 0, noVendor];
              await expectTCRedeemed(tx, args);
            });
          });
        });
        describe("AND Fee Token price rises 10 times AC price", function () {
          // 1 Fee Token = 10 Assets
          beforeEach(async function () {
            await feeTokenPriceProvider.poke(pEth(10));
          });
          describe("WHEN alice mints 100 TC", function () {
            beforeEach(async function () {
              tx = await mocFunctions.mintTC({ from: alice, qTC: 100 });
            });
            it("THEN 0.25 Fee Token are spent instead of 2.5", async function () {
              // sender: alice
              // receiver: alice
              // qTC: 100 TC
              // qAC: 100 AC
              // qACfee: 0 AC
              // qFeeToken: 100 AC (5% * 50%) / 10
              // qACVendorMarkup: 0
              // qFeeTokenVendorMarkup: 0
              const args = [operator, alice, pEth(100), pEth(100), 0, pEth(10 * 0.05 * 0.5), 0, 0, noVendor];
              await expectTCMinted(tx, args);
            });
          });
          describe("WHEN alice redeems 100 TC", function () {
            beforeEach(async function () {
              tx = await mocFunctions.redeemTC({ from: alice, qTC: 100 });
            });
            it("THEN 0.25 Fee Token are spent instead of 2.5", async function () {
              // sender: alice
              // receiver: alice
              // qTC: 100 TC
              // qAC: 100 AC
              // qACfee: 0 AC
              // qFeeToken: 100 AC (5% * 50%) / 10
              // qACVendorMarkup: 0
              // qFeeTokenVendorMarkup: 0
              const args = [operator, operator, pEth(100), pEth(100), 0, pEth(10 * 0.05 * 0.5), 0, 0, noVendor];
              await expectTCRedeemed(tx, args);
            });
          });
        });
      });
    });
    describe("GIVEN Alice has only enough AC to cover Operation, but not platform fee\n", function () {
      beforeEach(async function () {
        const execFee = await mocQueue.execCost(OperType.mintTC);
        const aliceACBalance = await mocFunctions.acBalanceOf(alice);
        // Empty Alice AC balance except for the strictly needed for mintTC
        mocFunctions.acTransfer({
          from: alice,
          to: vendor,
          amount: aliceACBalance - pEth(10) - execFee,
          applyPrecision: false,
        });
      });
      describe("AND she has enough feeToken and allowance at queuing time", function () {
        describe("BUT transfer it after she registers a mint 10 TC Operation", function () {
          beforeEach(async function () {
            await feeToken.mint(alice, pEth(100));
            await feeToken.connect(await ethers.getSigner(alice)).approve(spender, pEth(100));
            await mocFunctions.mintTC({ from: alice, qTC: 10, qACmax: 10, execute: false });
            await feeToken.connect(await ethers.getSigner(alice)).transfer(vendor, pEth(100));
          });
          it("THEN execution emits OperationError as it fallbacks to AC, and there is not enough", async function () {
            await expect(mocFunctions.executeQueue()).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.INSUFFICIENT_QAC_SENT,
            );
          });
        });
      });
    });
    describe("GIVEN Alice has none feeToken at queuing time", function () {
      describe("BUT she does after she registers a mint 10 TC Operation", function () {
        beforeEach(async function () {
          await mocFunctions.mintTC({ from: alice, qTC: 100, execute: false });
          await feeToken.mint(alice, pEth(100));
          await feeToken.connect(await ethers.getSigner(alice)).approve(spender, pEth(100));
        });
        it("THEN Fee Token is used as platform fee payment method", async function () {
          // sender: alice
          // receiver: alice
          // qTC: 100 TC
          // qAC: 100 AC
          // qACfee: 0 AC
          // qFeeToken: 100 AC (5% * 50%)
          // qACVendorMarkup: 0
          // qFeeTokenVendorMarkup: 0
          const execTx = mocFunctions.executeQueue();
          const args = [operator, alice, pEth(100), pEth(100), 0, pEth(100 * 0.05 * 0.5), 0, 0, noVendor];
          await expectTCMinted(execTx, args);
        });
      });
    });
  });
};

export { feeTokenBehavior };
