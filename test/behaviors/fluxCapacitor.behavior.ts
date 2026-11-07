import { getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/dist/types";
import { expect } from "chai";
import { assertPrec } from "../helpers/assertHelper";
import {
  BaseSetupFunction,
  ERRORS,
  finalFixturedDescribe,
  pEth,
  time,
  mine,
  loadFixture,
  CONSTANTS,
} from "../helpers/utils";
import { MocCACoinbase, MocCARC20 } from "../../typechain";

const fluxCapacitorBehavior = function (setup: BaseSetupFunction) {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let alice: Address;
  let lastOperationTimeStamp: bigint;
  const TP_1 = 1;

  async function baseSetup() {
    ({ mocContracts, mocFunctions } = await loadFixture(setup));
    ({ mocImpl } = mocContracts);
    ({ alice } = await getNamedAccounts());
    // add collateral
    await mocFunctions.mintTC({ from: alice, qTC: 200000000 });
    // initialize alice with some TP0
    await mocFunctions.mintTP({ from: alice, qTP: 23500000 });
    // reset accumulators
    await mine(1000, { interval: 30 });
    // initialize alice with some TP1
    await mocFunctions.mintTP({ i: TP_1, from: alice, qTP: 525000 });
    // reset accumulators
    await mine(3000, { interval: 30 });

    await mocContracts.maxAbsoluteOpProvider.poke(pEth(10000));
    await mocContracts.maxOpDiffProvider.poke(pEth(5000));
  }
  describe("Feature: flux capacitor", function () {
    finalFixturedDescribe(baseSetup, "WHEN 10001 AC are used to mint TC and TP", function () {
      describe("WHEN 10001 AC are used to mint TP0", function () {
        it("THEN fails because max absolute operation was reached", async function () {
          await expect(mocFunctions.mintTP({ from: alice, qTP: 2350235 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.INVALID_FLUX_CAPACITOR_OPERATION,
          );
        });
      });
      describe("WHEN 10001 AC are used to redeem TC and TP0", function () {
        it("THEN fails because max absolute operation was reached", async function () {
          await expect(
            mocFunctions.redeemTCandTP({ from: alice, qTC: "11766024.902394024462400000", qTP: 2350235 }),
          ).to.be.revertedWithCustomError(mocImpl, ERRORS.INVALID_FLUX_CAPACITOR_OPERATION);
        });
      });
      describe("WHEN 10001 AC are redeemed from TP0", function () {
        it("THEN fails because max absolute operation was reached", async function () {
          // 10001 AC / 0.95(5% fees) * 235 pACtp = 2473931
          await expect(mocFunctions.redeemTP({ from: alice, qTP: 2473931 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.INVALID_FLUX_CAPACITOR_OPERATION,
          );
        });
      });
      describe("WHEN 10001 AC are used to swap TP0 for TC", function () {
        it("THEN fails because max absolute operation was reached", async function () {
          await expect(mocFunctions.swapTPforTC({ from: alice, qTP: 2350235 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.INVALID_FLUX_CAPACITOR_OPERATION,
          );
        });
      });
      describe("WHEN 10001 AC are used to swap TC for TP0", function () {
        it("THEN fails because max absolute operation was reached", async function () {
          await expect(mocFunctions.swapTCforTP({ from: alice, qTC: 10001 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.INVALID_FLUX_CAPACITOR_OPERATION,
          );
        });
      });
      describe("WHEN 10001 AC are used to mint TC and TP", function () {
        it("THEN fails because max absolute operation was reached", async function () {
          await expect(mocFunctions.mintTCandTP({ from: alice, qTP: 2350235 })).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.INVALID_FLUX_CAPACITOR_OPERATION,
          );
        });
      });
    });
    describe("WHEN 10000 AC are used to swap TP0 for TC", function () {
      before(async () => {
        await loadFixture(baseSetup);
        await mocFunctions.swapTPforTC({ from: alice, qTP: 2350000 });
      });
      it("THEN absolute accumulator is 10000 and differential accumulator is -10000", async () => {
        assertPrec(await mocImpl.absoluteAccumulator(), 10000);
        assertPrec(await mocImpl.differentialAccumulator(), -10000);
      });
    });
    describe("WHEN 10000 AC are used to swap TC for TP0", function () {
      before(async function () {
        await loadFixture(baseSetup);
        await mocFunctions.swapTCforTP({ from: alice, qTC: 10000 });
      });
      it("THEN absolute and differential accumulators are in 10000", async function () {
        assertPrec(await mocImpl.absoluteAccumulator(), 10000);
        assertPrec(await mocImpl.differentialAccumulator(), 10000);
      });
    });
    describe("WHEN 10000 AC are used to mint TC and TP", function () {
      before(async function () {
        await loadFixture(baseSetup);
        await mocFunctions.mintTCandTP({ from: alice, qTP: 2350000 });
      });
      it("THEN absolute and differential accumulators are in 10000", async function () {
        assertPrec(await mocImpl.absoluteAccumulator(), 10000);
        assertPrec(await mocImpl.differentialAccumulator(), 10000);
      });
    });
    describe("WHEN 10000 AC are used to redeem TC and TP0", function () {
      before(async function () {
        await loadFixture(baseSetup);
        await mocFunctions.redeemTCandTP({ from: alice, qTC: "11764848.417552269235530000", qTP: 2350001 });
      });
      it("THEN absolute and differential accumulators are in 10000", async function () {
        assertPrec(await mocImpl.absoluteAccumulator(), 10000);
        assertPrec(await mocImpl.differentialAccumulator(), -10000);
      });
    });
    describe("WHEN maxAbsoluteOpProviders is deprecated", function () {
      before(async function () {
        await loadFixture(baseSetup);
        await mocContracts.maxAbsoluteOpProvider.deprecateDataProvider();
      });
      it("THEN mint TP fails because there is not a max absolute operation provider", async function () {
        await expect(mocFunctions.mintTP({ from: alice, qTP: 23500 })).to.be.revertedWithCustomError(
          mocImpl,
          ERRORS.MISSING_PROVIDER_DATA,
        );
      });
    });
    describe("WHEN maxOpDiffProviders is deprecated", function () {
      before(async function () {
        await loadFixture(baseSetup);
        await mocContracts.maxOpDiffProvider.deprecateDataProvider();
      });
      it("THEN mint TP fails because there is not a max operation difference provider", async function () {
        await expect(mocFunctions.mintTP({ from: alice, qTP: 23500 })).to.be.revertedWithCustomError(
          mocImpl,
          ERRORS.MISSING_PROVIDER_DATA,
        );
      });
    });
    describe("WHEN 6000 AC are used to mint TP0 on one block", function () {
      async function mintTP0Setup() {
        await loadFixture(baseSetup);
        const latest = await time.latest();
        await time.increaseTo(latest + 15); // 15 second increase as it's the half block equivalent
        await mocFunctions.mintTP({ from: alice, qTP: 1410000, execute: false });
        await time.increaseTo(latest + 30); // 30 second increase as it's the 1 block equivalent
        await mocFunctions.executeQueue();
        lastOperationTimeStamp = await mocImpl.lastOperationTimeStamp();
      }
      describe("AND maxAbsoluteOpProviders is set to 2000 AC, below actual accumulators value", function () {
        before(async function () {
          await loadFixture(mintTP0Setup);
          await mocContracts.maxAbsoluteOpProvider.poke(pEth(2000));
        });
        it("THEN there are 0 AC allowed to mint or redeem TP", async function () {
          assertPrec(await mocImpl.maxQACToMintTP(30), 0);
          assertPrec(await mocImpl.maxQACToRedeemTP(30), 0);
        });
      });
      describe("AND 10% of the decay factor time passes by since last Operation", function () {
        let tenPercTimestamp: bigint = 0n;
        async function mine10PercentDecaySetup() {
          await loadFixture(mintTP0Setup);
          const decayTimeSpan = await mocImpl.decayTimeSpan();
          tenPercTimestamp = lastOperationTimeStamp + decayTimeSpan / 10n;
        }
        describe("WHEN 2000 AC are redeemed from TP0 at that time", function () {
          async function redeemedTP0Setup() {
            await loadFixture(mine10PercentDecaySetup);
            // 2000 AC / 0.95(5% fees) * 235 pACtp = 494736.84
            await mocFunctions.redeemTP({ from: alice, qTP: "494736.842105263157894700", execute: false });
            await time.setNextBlockTimestamp(tenPercTimestamp);
            await mocFunctions.executeQueue();
          }
          finalFixturedDescribe(redeemedTP0Setup, "(Assertions)", async function () {
            it("THEN absolute accumulator is 7400 and differential accumulator is 3400", async function () {
              // absolute = (6000 * 0.9) + 2000
              // differential = (6000 * 0.9) - 2000
              assertPrec(await mocImpl.absoluteAccumulator(), 7400);
              assertPrec(await mocImpl.differentialAccumulator(), 3400);
            });
            it("THEN there are 2602 AC allowed to mint TP and 500 AC allowed to redeem TP", async function () {
              assertPrec(await mocImpl.maxQACToMintTP(30), "2602.569444444444442800");
              assertPrec(await mocImpl.maxQACToRedeemTP(30), "500.694444444444444000");
            });
          });
          describe("AND maxOpDiffProviders is set to 2000 AC, below actual accumulators value", function () {
            before(async function () {
              await loadFixture(redeemedTP0Setup);
              await mocContracts.maxOpDiffProvider.poke(pEth(2000));
            });
            it("THEN there are 0 AC allowed to mint or redeem TP", async function () {
              assertPrec(await mocImpl.maxQACToMintTP(30), 0);
              assertPrec(await mocImpl.maxQACToRedeemTP(30), 0);
            });
          });
        });
      });
      describe("AND 100% of the decay factor time passes by since last Operation", function () {
        let fullDecayTimestamp = 0n;
        async function mine100PercentDecaySetup() {
          await loadFixture(mintTP0Setup);
          await loadFixture(mintTP0Setup);
          const decayTimeSpan = await mocImpl.decayTimeSpan();
          fullDecayTimestamp = lastOperationTimeStamp + decayTimeSpan;
        }
        finalFixturedDescribe(mine100PercentDecaySetup, "(Assertions)", async function () {
          it("THEN absolute and differential accumulators were reset", async function () {
            await time.increaseTo(fullDecayTimestamp);
            await mine();
            assertPrec(await mocImpl.maxQACToMintTP(30), 10000);
            assertPrec(await mocImpl.maxQACToRedeemTP(30), 10000);
          });
        });
        describe("WHEN 2000 AC are redeemed from TP0 at that time", function () {
          before(async function () {
            await loadFixture(mine100PercentDecaySetup);
            // 2000 AC / 0.95(5% fees) * 235 pACtp = 494736.84
            await mocFunctions.redeemTP({ from: alice, qTP: "494736.842105263157894700", execute: false });
            await time.increaseTo(fullDecayTimestamp);
            await mocFunctions.executeQueue();
          });
          it("THEN absolute accumulator is 2000 and differential accumulator is -2000", async function () {
            assertPrec(await mocImpl.absoluteAccumulator(), 2000);
            assertPrec(await mocImpl.differentialAccumulator(), -2000);
          });
          it("THEN there are 8000 AC allowed to mint or redeem TP", async function () {
            assertPrec(await mocImpl.maxQACToMintTP(30), "8000.694444444444444000");
            assertPrec(await mocImpl.maxQACToRedeemTP(30), "8000.694444444444444000");
          });
        });
        describe("WHEN 3000 AC are redeemed from TP1", function () {
          before(async function () {
            await loadFixture(mine100PercentDecaySetup);
            // 3000 AC / 0.95(5% fees) * 5.25 pACtp = 16578.94
            await mocFunctions.redeemTP({ i: TP_1, from: alice, qTP: "16578.947368421052631578", execute: false });
            await time.increaseTo(fullDecayTimestamp);
            await mocFunctions.executeQueue();
          });
          it("THEN absolute accumulator is 3000 and differential accumulator is -3000", async function () {
            assertPrec(await mocImpl.absoluteAccumulator(), 3000);
            assertPrec(await mocImpl.differentialAccumulator(), -3000);
          });
          it("THEN there are 2500 AC allowed to mint TP and 7000 AC to redeem TP", async function () {
            assertPrec(await mocImpl.maxQACToMintTP(30), 2500);
            assertPrec(await mocImpl.maxQACToRedeemTP(30), "7001.041666666666666000");
          });
        });
      });
      finalFixturedDescribe(mintTP0Setup, "(Assertions)", async function () {
        it("THEN absolute and differential accumulators are in 6000", async function () {
          assertPrec(await mocImpl.absoluteAccumulator(), 6000);
          assertPrec(await mocImpl.differentialAccumulator(), 6000);
        });
        it("THEN last operation time is update", async function () {
          expect(await mocImpl.lastOperationTimeStamp()).to.be.equal(lastOperationTimeStamp);
        });
        it("THEN there are 4002 AC allowed to mint TP and 2500 AC allowed to redeem TP", async function () {
          assertPrec(await mocImpl.maxQACToMintTP(30), "4002.083333333333332000");
          assertPrec(await mocImpl.maxQACToRedeemTP(30), 2500);
        });
        describe("WHEN 4003 AC are used to mint TP0", function () {
          it("THEN fails because max absolute operation was reached", async function () {
            await expect(mocFunctions.mintTP({ from: alice, qTP: 940705 })).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.MAX_FLUX_CAPACITOR_REACHED,
            );
          });
        });
        describe("WHEN 4003 AC are used to mint TP1", function () {
          it("THEN fails because max absolute operation was reached", async function () {
            await expect(
              mocFunctions.mintTP({ i: TP_1, from: alice, qTP: 21015.75, qACmax: 210200 }),
            ).to.be.revertedWithCustomError(mocImpl, ERRORS.MAX_FLUX_CAPACITOR_REACHED);
          });
        });
        describe("WHEN 2501 AC are redeemed from TP0", function () {
          it("THEN fails because max operational difference was reached", async function () {
            // 2501 AC / 0.95(5% fees) * 235 pACtp = 618668
            await expect(mocFunctions.redeemTP({ from: alice, qTP: 618668 })).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.MAX_FLUX_CAPACITOR_REACHED,
            );
          });
        });
        describe("WHEN 2501 AC are redeemed from TP1", function () {
          it("THEN fails because max operational difference was reached", async function () {
            // 2501 AC / 0.95(5% fees) * 5.25 pACtp = 13821
            await expect(mocFunctions.redeemTP({ i: TP_1, from: alice, qTP: 13821 })).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.MAX_FLUX_CAPACITOR_REACHED,
            );
          });
        });
      });
    });

    describe("WHEN decayTimeSpan is set to zero", function () {
      let prevAbsoluteAccumulator: bigint;
      let prevDifferentialAccumulator: bigint;
      before(async function () {
        await loadFixture(baseSetup);
        prevAbsoluteAccumulator = await mocImpl.absoluteAccumulator();
        prevDifferentialAccumulator = await mocImpl.differentialAccumulator();
        await mocImpl.setFluxCapacitorParams(
          await mocImpl.maxAbsoluteOpProvider(),
          await mocImpl.maxOpDiffProvider(),
          0,
        );
        await mine(10, { interval: 30 });
      });
      it("THEN absolute accumulator and differential accumulator are not affected", async function () {
        assertPrec(await mocImpl.absoluteAccumulator(), prevAbsoluteAccumulator);
        assertPrec(await mocImpl.differentialAccumulator(), prevDifferentialAccumulator);
      });
      it("THEN AC allowed to mint TP and redeem TP are not restricted", async function () {
        assertPrec(await mocImpl.maxQACToMintTP(30), CONSTANTS.MAX_UINT256);
        assertPrec(await mocImpl.maxQACToRedeemTP(30), CONSTANTS.MAX_UINT256);
      });
      describe("WHEN after a long time decayTimeSpan is set to 1 day again", function () {
        before(async function () {
          await mine(1000, { interval: 30 });
          await mocImpl.setFluxCapacitorParams(
            await mocImpl.maxAbsoluteOpProvider(),
            await mocImpl.maxOpDiffProvider(),
            time.duration.days(1),
          );
        });
        it("THEN absolute accumulator and differential accumulator are not affected until an Operation", async function () {
          assertPrec(await mocImpl.absoluteAccumulator(), prevAbsoluteAccumulator);
          assertPrec(await mocImpl.differentialAccumulator(), prevDifferentialAccumulator);
        });
        it("THEN AC allowed to mint TP and redeem TP are reset", async function () {
          assertPrec(await mocImpl.maxQACToMintTP(30), 10000);
          assertPrec(await mocImpl.maxQACToRedeemTP(30), 10000);
        });
        describe("THEN a user mints TP", function () {
          before(async function () {
            await mocFunctions.mintTP({ from: alice, qTP: 1410000 });
          });
          it("THEN absolute accumulator and differential accumulator are affected accordingly", async function () {
            assertPrec(await mocImpl.absoluteAccumulator(), 6000);
            assertPrec(await mocImpl.differentialAccumulator(), 6000);
          });
        });
      });
    });
  });
};

export { fluxCapacitorBehavior };
