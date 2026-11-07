import { getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/dist/types";
import { assertPrec } from "../helpers/assertHelper";
import { Balance } from "../helpers/utils";
import { MocCACoinbase, MocCARC20 } from "../../typechain";

const mintTCBehavior = function () {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCACoinbase | MocCARC20;
  let deployer: Address;
  let alice: Address;
  const TP_0 = 0;

  describe("Feature: mint Collateral Token", function () {
    beforeEach(async function () {
      mocContracts = this.mocContracts;
      mocFunctions = this.mocFunctions;
      ({ mocImpl } = mocContracts);
      ({ deployer, alice } = await getNamedAccounts());
    });
    describe("GIVEN 3000 TC and 100 TP are minted", function () {
      beforeEach(async function () {
        await mocFunctions.mintTC({ from: deployer, qTC: 3000 });
        await mocFunctions.mintTP({ from: deployer, qTP: 100 });
      });
      describe("AND Pegged Token has been devaluated to 500 making TC price rises", function () {
        beforeEach(async function () {
          await mocFunctions.pokePrice(TP_0, 500);
        });
        it("THEN TC price is 1.00007", async function () {
          assertPrec("1.000075177304964539", await mocImpl.getPTCac());
        });
        it("THEN coverage is 15002.12", async function () {
          assertPrec("15002.127659574468085105", await mocImpl.getCglb());
        });
        describe("WHEN alice mints 100 TC", function () {
          let alicePrevACBalance: Balance;
          beforeEach(async function () {
            alicePrevACBalance = await mocFunctions.assetBalanceOf(alice);
            await mocFunctions.mintTC({ from: alice, qTC: 100 });
          });
          it("THEN alice spends 105.007 assets instead of 105", async function () {
            const aliceActualACBalance = await mocFunctions.assetBalanceOf(alice);
            const diff = alicePrevACBalance - aliceActualACBalance;
            assertPrec("105.007893617022276595", diff);
          });
        });
      });
    });
  });
};

export { mintTCBehavior };
