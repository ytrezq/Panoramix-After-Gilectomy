import hre, { getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/dist/types";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../helpers/assertHelper";
import {
  Balance,
  pEth,
  time,
  getNetworkDeployParams,
  finalFixturedDescribe,
  BaseSetupFunction,
  getArrayValueAt,
  mineNBlocks,
} from "../helpers/utils";
import { MocCACoinbase, MocCARC20 } from "../../typechain";

const successFeeBehavior = function (setup: BaseSetupFunction) {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let alice: Address;
  let nextSettlementTime: bigint;
  const TP_0 = 0;
  const TP_1 = 1;
  const TP_2 = 2;
  const { mocFeeFlowAddress, mocAppreciationBeneficiaryAddress } = getNetworkDeployParams(hre).mocAddresses;

  let mocPrevACBalance: Balance;
  let mocFeeFlowPrevACBalance: Balance;
  let mocApprecBenefPrevTPsBalance: Balance[];
  let initializeBeforeBalances: () => Promise<void>;

  describe("Feature: success fee distribution", function () {
    async function baseSetup() {
      ({ mocContracts, mocFunctions } = await loadFixture(setup));
      ({ mocImpl } = mocContracts);
      ({ alice } = await getNamedAccounts());
      initializeBeforeBalances = async function () {
        [mocPrevACBalance, mocFeeFlowPrevACBalance, ...mocApprecBenefPrevTPsBalance] = await Promise.all([
          mocFunctions.acBalanceOf(mocImpl.target.toString()),
          mocFunctions.acBalanceOf(mocFeeFlowAddress),
          ...[TP_0, TP_1, TP_2].map(i => mocFunctions.tpBalanceOf(i, mocAppreciationBeneficiaryAddress)),
        ]);
      };
    }
    describe("GIVEN alice has open positions", function () {
      /*
      nAC = 1000 + 100 + 20 + 10
      lckAC = 130
      */
      async function openPositionsSetup() {
        await loadFixture(baseSetup);
        await mocFunctions.mintTC({ from: alice, qTC: 1000 });
        await Promise.all(
          [23500, 105, 9345.8].map((qTP, i) => mocFunctions.mintTP({ i, from: alice, qTP, qACmax: qTP * 10 })),
        );
      }
      describe("AND settlement is executed without TP price variations", function () {
        let tx: ContractTransactionResponse;
        before(async function () {
          await loadFixture(openPositionsSetup);
          await initializeBeforeBalances();
          nextSettlementTime = await mocImpl.nextSettlementTime();
          await time.increaseTo(nextSettlementTime);
          tx = await mocImpl.execSettlement();
        });
        it("THEN TC price is still 1 because the TP prices had not changed", async function () {
          assertPrec(1, await mocImpl.getPTCac());
        });
        it("THEN Moc balance AC balance didn't change", async function () {
          const mocActualACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
          const diff = mocActualACBalance - mocPrevACBalance;
          assertPrec(0, diff);
        });
        it("THEN Moc appreciation beneficiary TP balance didn't change", async function () {
          const mocApprecBenefActualTPsBalance = await Promise.all(
            [TP_0, TP_1, TP_2].map(i => mocFunctions.tpBalanceOf(i, mocAppreciationBeneficiaryAddress)),
          );
          mocApprecBenefActualTPsBalance.forEach((value, i) => {
            const diff = value - mocApprecBenefPrevTPsBalance[i];
            assertPrec(0, diff);
          });
        });
        it("THEN Moc Fee Flow AC balance didn't change", async function () {
          const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
          const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
          assertPrec(0, diff);
        });
        it("THEN SuccessFeeDistributed event is emitted", async function () {
          // mocGain: 0
          // tpGain[i]: 0
          await expect(tx).to.emit(mocImpl, "SuccessFeeDistributed").withArgs(0, [0, 0, 0, 0, 0]);
        });
      });
      describe("AND TPs prices have changed +100%, +50% and -25% respectively", function () {
        /*
        nAC = 1000 + 100 + 20 + 10
        nTP0 = 23500 + 11750 = 35250
        nTP1 = 105 + 26.25 = 131.5
        nTP2 = 9345.8 + 0 = 9345.8
        lckAC = 75 + 16.69 + 13.33
        nACgain = (50 + 6.66 + 0) * 0.1 = 5.66
        pTCac = 1130 - 105.02 - 5.66 / 1000 = 1.019
        coverage = 1130 - 5.66 / 105.02 = 10.707
        */
        async function TPPricesChangedSetup() {
          await loadFixture(openPositionsSetup);
          await Promise.all([470, 7.875, 700.935].map((price, i) => mocFunctions.pokePrice(i, price)));
        }
        finalFixturedDescribe(TPPricesChangedSetup, "(Assertions)", function () {
          it("THEN TC price is 1.019", async function () {
            assertPrec("1.019333333333333333", await mocImpl.getPTCac());
          });
          it("THEN coverage is 10.707", async function () {
            assertPrec("10.707936507936507936", await mocImpl.getCglb());
          });
        });
        describe("AND settlement is executed having one TP price variations", function () {
          /*
          nAC = 1130 - 5.66
          lckAC = 75 + 16.69 + 13.33
          nACgain = 0
          pTCac = 1124.34 - 105.02 - 0 / 1000 = 1.023
          TP1 minted to appreciation beneficiary = 11750
          TP2 Minted to appreciation beneficiary = 26.25
          TP3 Minted to appreciation beneficiary = 0 => remains iuo = -3.33
          */
          let tx: ContractTransactionResponse;
          async function settlementExecutedSetup() {
            await loadFixture(TPPricesChangedSetup);
            nextSettlementTime = await mocImpl.nextSettlementTime();
            await time.increaseTo(nextSettlementTime);
            tx = await mocImpl.execSettlement();
          }
          finalFixturedDescribe(settlementExecutedSetup, "(Assertions)", function () {
            it("THEN TC price didn't change, it is 1.019", async function () {
              assertPrec("1.019333333333333333", await mocImpl.getPTCac());
            });
            it("THEN coverage didn`t change, it is 10.707", async function () {
              assertPrec("10.707936507936507936", await mocImpl.getCglb());
            });
            it("THEN Moc balance AC decrease 5.66 AC, 10% of mocGain", async function () {
              const mocActualACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
              const diff = mocPrevACBalance - mocActualACBalance;
              assertPrec("5.666666666666666666", diff);
            });
            it("THEN Moc appreciation beneficiary TP balance increase 50% for each TP devaluation", async function () {
              const mocApprecBenefActualTPsBalance = await Promise.all(
                [TP_0, TP_1, TP_2].map(i => mocFunctions.tpBalanceOf(i, mocAppreciationBeneficiaryAddress)),
              );
              [11750, "26.250000000000000001", 0].forEach((increment, i) => {
                const diff = mocApprecBenefActualTPsBalance[i] - mocApprecBenefPrevTPsBalance[i];
                assertPrec(increment, diff, `TP index ${i}`);
              });
            });
            it("THEN Moc Fee Flow AC balance increase 5.66 AC, 10% of mocGain", async function () {
              const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
              const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
              assertPrec("5.666666666666666666", diff);
            });
            it("THEN SuccessFeeDistributed event is emitted", async function () {
              // mocGain: 5.66
              // tpGain[0]: 11750
              // tpGain[1]: 26.25
              // tpGain[2]: 0
              // tpGain[3]: 0
              // tpGain[4]: 0
              await expect(tx)
                .to.emit(mocImpl, "SuccessFeeDistributed")
                .withArgs(pEth("5.666666666666666666"), [pEth(11750), pEth("26.250000000000000001"), 0, 0, 0]);
            });
          });
          describe("AND TPs prices have changed again +50%, -50% and +100% respectively", function () {
            /*
            nAC = 1124.34
            nTP0 = 35250 + 8812.5 = 44062.5
            nTP1 = 131.5 + 0 = 131.5
            nTP2 = 9345.8 + 2336.45 = 11682.25
            lckAC = 62.5 + 33.39 + 8.29
            nACgain = (25 + 0 + (-3.33 + 6.66)) * 0.1 = 2.83
            pTCac = 1124.34 - 104.18 - 2.83 / 1000 = 1.0173
            */
            before(async function () {
              await loadFixture(settlementExecutedSetup);
              await Promise.all([705, "3.9375", 1401.87].map((price, i) => mocFunctions.pokePrice(i, price)));
            });
            it("THEN TC price is 1.0173", async function () {
              assertPrec("1.017333333333333333", await mocImpl.getPTCac());
            });
          });
        });
        describe("AND TPs prices have changed again +50%, -50% and +100% respectively", function () {
          /*
          nAC = 1130
          nTP0 = 23500 + 23500 = 47000
          nTP1 = 105 + 0 = 105
          nTP2 = 9345.8 + 2336.45 = 11682.25
          lckAC = 66.66 + 26.66 + 8.29
          nACgain = (6.66 + 0 + 3.33) * 0.1 = 7
          pTCac = 1130 - 101.66 - 7 / 1000 = 1.0213
          coverage = 1130 - 7 / 101.66 = 11.04
          */
          async function TPPricesChangedAgainSetup() {
            await loadFixture(TPPricesChangedSetup);
            await Promise.all([705, "3.9375", 1401.87].map((price, i) => mocFunctions.pokePrice(i, price)));
          }
          finalFixturedDescribe(TPPricesChangedAgainSetup, "(Assertions)", function () {
            it("THEN TC price is 1.0213", async function () {
              assertPrec("1.021333333333333333", await mocImpl.getPTCac());
            });
            it("THEN coverage is 11.04", async function () {
              assertPrec("11.045901639344262295", await mocImpl.getCglb());
            });
          });
          describe("AND settlement is executed having two TP price variations", function () {
            /*
            nAC = 1130 - 7
            lckAC = 66.66 + 26.66 + 8.29            
            nACgain = 0
            pTCac = 1123 - 101.66 - 0 / 1000 = 1.023
            TP1 minted to appreciation beneficiary = 23500
            TP2 Minted to appreciation beneficiary = 0 => remains iuo = -6.666
            TP3 Minted to appreciation beneficiary = 2336.45
            */
            let tx: ContractTransactionResponse;
            before(async function () {
              await loadFixture(TPPricesChangedAgainSetup);
              nextSettlementTime = await mocImpl.nextSettlementTime();
              await time.increaseTo(nextSettlementTime);
              tx = await mocImpl.execSettlement();
            });
            it("THEN TC price didn't change, it is 1.0213", async function () {
              assertPrec("1.021333333333333333", await mocImpl.getPTCac());
            });
            it("THEN coverage didn't change, it is 11.04", async function () {
              assertPrec("11.045901639344262295", await mocImpl.getCglb());
            });
            it("THEN Moc balance AC decrease 7 AC, 10% of mocGain", async function () {
              const mocActualACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
              const diff = mocPrevACBalance - mocActualACBalance;
              assertPrec(7, diff);
            });
            it("THEN Moc appreciation beneficiary TP balance increase 50% for each TP devaluation", async function () {
              const mocApprecBenefActualTPsBalance = await Promise.all(
                [TP_0, TP_1, TP_2].map(i => mocFunctions.tpBalanceOf(i, mocAppreciationBeneficiaryAddress)),
              );
              ["23500.000000000000000117", 0, "2336.450000000000000467"].forEach((increment, i) => {
                const diff = mocApprecBenefActualTPsBalance[i] - mocApprecBenefPrevTPsBalance[i];
                assertPrec(increment, diff, `TP index ${i}`);
              });
            });
            it("THEN Moc Fee Flow AC balance increase 7 AC, 10% of mocGain", async function () {
              const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
              const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
              assertPrec(7, diff);
            });
            it("THEN SuccessFeeDistributed event is emitted", async function () {
              // mocGain: 7
              // tpGain[0]: 23500
              // tpGain[1]: 0
              // tpGain[2]: 2336.45
              // tpGain[3]: 0
              // tpGain[4]: 0
              await expect(tx)
                .to.emit(mocImpl, "SuccessFeeDistributed")
                .withArgs(pEth(7), [pEth("23500.000000000000000117"), 0, pEth("2336.450000000000000467"), 0, 0]);
            });
          });
        });
        describe("AND success fee and appreciation factor are set to 0%, disabling the feature", function () {
          describe("AND settlement is executed having one TP price variations", function () {
            let tx: ContractTransactionResponse;
            before(async function () {
              await loadFixture(TPPricesChangedSetup);
              await mocImpl.setSuccessFeeParams(0, 0, await mocImpl.mocAppreciationBeneficiaryAddress());
              await initializeBeforeBalances();
              nextSettlementTime = await mocImpl.nextSettlementTime();
              await time.increaseTo(nextSettlementTime);
              tx = await mocImpl.execSettlement();
            });
            /*
              nAC = 1000 + 100 + 20 + 10
              lckAC = 50 + 13.33 + 13.33
              nACgain = 0
              pTCac = 1130 - 76.66 / 1000 = 1.053
              coverage = 1130 / 76.66 = 14.73
              */
            it("THEN TC price is 1.053", async function () {
              assertPrec("1.053333333333333333", await mocImpl.getPTCac());
            });
            it("THEN coverage is 14.73", async function () {
              assertPrec("14.739130434782608695", await mocImpl.getCglb());
            });
            it("THEN Moc balance AC balance didn't change", async function () {
              const mocActualACBalance = await mocFunctions.acBalanceOf(mocImpl.target.toString());
              const diff = mocActualACBalance - mocPrevACBalance;
              assertPrec(0, diff);
            });
            it("THEN Moc appreciation beneficiary TP balance didn't change", async function () {
              const mocApprecBenefActualTPsBalance = await Promise.all(
                [TP_0, TP_1, TP_2].map(i => mocFunctions.tpBalanceOf(i, mocAppreciationBeneficiaryAddress)),
              );
              mocApprecBenefActualTPsBalance.forEach((value, i) => {
                const diff = value - mocApprecBenefPrevTPsBalance[i];
                assertPrec(0, diff);
              });
            });
            it("THEN Moc Fee Flow AC balance didn't change", async function () {
              const mocFeeFlowActualACBalance = await mocFunctions.acBalanceOf(mocFeeFlowAddress);
              const diff = mocFeeFlowActualACBalance - mocFeeFlowPrevACBalance;
              assertPrec(0, diff);
            });
            it("THEN SuccessFeeDistributed event is emitted", async function () {
              // mocGain: 0
              // tpGain[i]: 0
              await expect(tx).to.emit(mocImpl, "SuccessFeeDistributed").withArgs(0, [0, 0, 0, 0, 0]);
            });
            describe("AND successFee is later once again enabled", function () {
              before(async function () {
                await mocFunctions.pokePrice(TP_0, 42);
                await mocFunctions.pokePrice(TP_1, 43);
                await mocImpl.setSuccessFeeParams(pEth(0.1), 0, await mocImpl.mocAppreciationBeneficiaryAddress());
                nextSettlementTime = await mocImpl.nextSettlementTime();
                await time.increaseTo(nextSettlementTime);
                await mineNBlocks(10);
              });
              it("THEN pACtpLstop values get reset even without operations", async function () {
                const pACtpLstopSlot = 337;
                assertPrec(42, await getArrayValueAt(mocImpl.target.toString(), pACtpLstopSlot, 0));
                assertPrec(43, await getArrayValueAt(mocImpl.target.toString(), pACtpLstopSlot, 1));
              });
            });
          });
        });
      });
    });
  });
};

export { successFeeBehavior };
