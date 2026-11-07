import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/dist/types";
import { assertPrec } from "../helpers/assertHelper";
import { pEth } from "../helpers/utils";
import { MocCARC20, ERC20Mock } from "../../typechain";

const caInjectionBehavior = function () {
  let mocContracts: any;
  let mocFunctions: any;
  let mocImpl: MocCARC20;
  let collateralAsset: ERC20Mock;
  let alice: Address;

  describe("Feature: collateral injection", function () {
    before(async function () {
      mocContracts = this.mocContracts;
      mocFunctions = this.mocFunctions;
      ({ mocImpl, collateralAsset } = mocContracts);
      ({ alice } = await getNamedAccounts());
      // add collateral
      await mocFunctions.mintTC({ from: alice, qTC: 10 });
    });
    describe("WHEN a user transfers CA tokens to the contract address", function () {
      before(async function () {
        await collateralAsset.connect(await ethers.getSigner(alice)).transfer(mocImpl.target.toString(), pEth(5));
      });
      it("THEN moc AC balance increases", async function () {
        assertPrec(15, await collateralAsset.balanceOf(mocImpl.target.toString()));
      });
      it("THEN nothing changes on the model", async function () {
        assertPrec(10, await mocImpl.nACcb());
        assertPrec(1, await mocImpl.getPTCac());
      });
      describe("WHEN someone executes refreshACBalance", function () {
        before(async function () {
          await mocImpl.refreshACBalance();
        });
        it("THEN nACcb reflects the new balance", async function () {
          assertPrec(15, await mocImpl.nACcb());
        });
        it("THEN TC ac price increases as there is more collateral", async function () {
          assertPrec(1.5, await mocImpl.getPTCac());
        });
        describe("WHEN someone executes refreshACBalance again", function () {
          before(async function () {
            await mocImpl.refreshACBalance();
          });
          it("THEN nothing happens as the balance is already updated", async function () {
            assertPrec(15, await mocImpl.nACcb());
            assertPrec(1.5, await mocImpl.getPTCac());
          });
        });
      });
    });
  });
};

export { caInjectionBehavior };
