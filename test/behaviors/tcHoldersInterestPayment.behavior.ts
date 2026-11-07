import { getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/dist/types";
import { expect } from "chai";
import { assertPrec } from "../helpers/assertHelper";
import { Balance, ERRORS, time, pEth } from "../helpers/utils";
import { MocCACoinbase, MocCARC20 } from "../../typechain";

const tcHoldersInterestPaymentBehavior = function () {
  let mocImpl: MocCACoinbase | MocCARC20;
  let mocContracts: any;
  let mocFunctions: any;
  let alice: Address;
  let tcInterestCollector: Address;
  let tx: ContractTransactionResponse;

  describe("Feature: TC holders interest payment", function () {
    before(async function () {
      mocContracts = this.mocContracts;
      mocFunctions = this.mocFunctions;
      ({ alice, otherUser: tcInterestCollector } = await getNamedAccounts());
      ({ mocImpl } = mocContracts);
      await mocImpl.setTCInterestParams(
        tcInterestCollector,
        await mocImpl.tcInterestRate(),
        await mocImpl.tcInterestPaymentTimeSpan(),
      );
    });
    describe("GIVEN there are 105000 AC in the protocol", function () {
      before(async function () {
        await mocFunctions.mintTC({ from: alice, qTC: 100000 });
        await mocFunctions.mintTP({ from: alice, qTP: 1175000 });
        // assert MocCore balance
        assertPrec(await mocFunctions.acBalanceOf(mocImpl.target.toString()), 105000);
      });
      describe("WHEN tries to execute TC holders interest payment before the corresponding time", function () {
        before(async function () {
          await time.increaseTo((await mocImpl.nextTCInterestPayment()) - 2n);
        });
        it("THEN tx fails because needed time to TC interest payment has not passed", async function () {
          await expect(mocImpl.tcHoldersInterestPayment()).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.MISSING_TIME_TO_TC_INTEREST_PAYMENT,
          );
        });
      });
      describe("WHEN TC holders interest payment is executed", function () {
        let mocPrevACBalance: Balance;
        let tcInterestCollectorPrevACBalance: Balance;
        before(async function () {
          mocPrevACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          tcInterestCollectorPrevACBalance = await mocFunctions.acBalanceOf(tcInterestCollector);
          await time.increaseTo(await mocImpl.nextTCInterestPayment());
          tx = await mocImpl.tcHoldersInterestPayment();
        });
        it("THEN MoC balance decrease 0.005% of 105000 AC", async function () {
          const mocActualACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          const diff = mocPrevACBalance - mocActualACBalance;
          assertPrec(diff, 5.25);
        });
        it("THEN TC interest collector balance increase 0.005% of 105000 AC", async function () {
          const tcInterestCollectorActualACBalance = await mocFunctions.acBalanceOf(tcInterestCollector);
          const diff = tcInterestCollectorActualACBalance - tcInterestCollectorPrevACBalance;
          assertPrec(diff, 5.25);
        });
        it("THEN nACcb matches with AC balance", async function () {
          assertPrec(await mocImpl.nACcb(), await mocFunctions.acBalanceOf(mocImpl.target.toString()));
        });
        it("THEN a TCInterestPayment event is emitted", async function () {
          // interestAmount: 5.25 AC
          await expect(tx).to.emit(mocImpl, "TCInterestPayment").withArgs(pEth(5.25));
        });
        it("THEN next time to TC interest payment is updated", async function () {
          assertPrec(
            await mocImpl.nextTCInterestPayment(),
            (await mocImpl.tcInterestPaymentTimeSpan()) + BigInt(await time.latest()),
          );
        });
        describe("WHEN tries to execute TC holders interest payment again", function () {
          it("THEN tx fails because needed time to TC interest payment has not passed", async function () {
            await expect(mocImpl.tcHoldersInterestPayment()).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.MISSING_TIME_TO_TC_INTEREST_PAYMENT,
            );
          });
        });
        describe("AND TP price increase making protocol below coverage", function () {
          before(async function () {
            await mocFunctions.pokePrice(0, 2.35);
            // assert coverage
            assertPrec(await mocImpl.getCglb(), "0.209989500000000000");
          });
          describe("WHEN TC holders interest payment is executed", function () {
            before(async function () {
              await time.increaseTo(await mocImpl.nextTCInterestPayment());
              tx = await mocImpl.tcHoldersInterestPayment();
            });
            it("THEN a TCInterestPayment event is emitted", async function () {
              // interestAmount: 0.005%(105000 - 5.25 AC) = 5.249 AC
              await expect(tx).to.emit(mocImpl, "TCInterestPayment").withArgs(pEth("5.249737500000000000"));
            });
          });
        });
      });
      describe("WHEN TC interest rate is updated with a value grater than 1%", function () {
        it("THEN tx fails by invalidValue", async function () {
          await expect(
            mocImpl.setTCInterestParams(
              await mocImpl.tcInterestCollectorAddress(),
              pEth(0.011),
              await mocImpl.tcInterestPaymentTimeSpan(),
            ),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.INVALID_VALUE);
        });
      });
      describe("AND TC interest payment is disabled setting tcInterestRate in 0", function () {
        before(async function () {
          await mocImpl.setTCInterestParams(
            await mocImpl.tcInterestCollectorAddress(),
            0,
            await mocImpl.tcInterestPaymentTimeSpan(),
          );
        });
        describe("WHEN TC holders interest payment is executed", function () {
          before(async function () {
            await time.increaseTo(await mocImpl.nextTCInterestPayment());
            tx = await mocImpl.tcHoldersInterestPayment();
          });
          it("THEN a TCInterestPayment event is emitted", async function () {
            // interestAmount: 0 AC
            await expect(tx).to.emit(mocImpl, "TCInterestPayment").withArgs(0);
          });
          it("THEN next time to TC interest payment is updated", async function () {
            assertPrec(
              await mocImpl.nextTCInterestPayment(),
              (await mocImpl.tcInterestPaymentTimeSpan()) + BigInt(await time.latest()),
            );
          });
        });
      });
    });
  });
};

export { tcHoldersInterestPaymentBehavior };
