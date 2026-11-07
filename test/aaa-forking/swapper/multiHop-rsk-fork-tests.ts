import { getNamedAccounts, ethers, network } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { Balance, CONSTANTS, ERRORS, pEth, timedDescribe, resetFork } from "../../helpers/utils";
import {
  ERC20__factory,
  GovernorMock,
  GovernorMock__factory,
  MocMultiCollateralGuard,
  MocSwapperV3MultiHop,
  MocSwapperV3MultiHop__factory,
} from "../../../typechain";
import { fixtureFork2 } from "../../multicollateral/fixture";
import { assertPrec } from "../../helpers/assertHelper";
const helpers = require("@nomicfoundation/hardhat-network-helpers");

timedDescribe("Feature: MocSwappersV3MultiHop with uniswap - rsk fork", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(1);
  let mocCore0: Address;
  let mocCore1: Address;
  let mocCore2: Address;
  let tp: Address;
  let governorMock: GovernorMock;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let deployer: Address;
  let mocSwapperV3: MocSwapperV3MultiHop;
  let maxACtoSwapProvider: Address;
  const bproHolderAddress = "0xB224228b0Fe71ceBf95EE25339166CD626759b52"; // https://explorer.rootstock.io/address/0xB224228b0Fe71ceBf95EE25339166CD626759b52
  const docHolderAddress = "0xD07d569322a93a47B62D71203e21f0AFf8246099"; // https://explorer.rootstock.io/address/0xD07d569322a93a47B62D71203e21f0AFf8246099
  const BPRO = "0x440CD83C160De5C96Ddb20246815eA44C7aBBCa8"; // https://explorer.rootstock.io/address/0x440CD83C160De5C96Ddb20246815eA44C7aBBCa8
  const DOC = "0xe700691dA7b9851F2F35f8b8182c69c53CcaD9Db"; // https://explorer.rootstock.io/address/0xe700691dA7b9851F2F35f8b8182c69c53CcaD9Db
  const WRBTC = "0x542fDA317318eBF1d3DEAf76E0b632741A7e677d"; // https://explorer.rootstock.io/address/0x542fda317318ebf1d3deaf76e0b632741a7e677d
  const USDT = "0xAf368c91793CB22739386DFCbBb2F1A9e4bCBeBf"; // https://explorer.rootstock.io/address/0xAf368c91793CB22739386DFCbBb2F1A9e4bCBeBf
  const swapRouterV2 = "0x0B14ff67f0014046b4b99057Aec4509640b3947A"; // https://explorer.rootstock.io/address/0x0B14ff67f0014046b4b99057Aec4509640b3947A
  const RBTC = CONSTANTS.ZERO_ADDRESS;

  describe("GIVEN 2 Moc implementations deployed on rsk mainnet using BPRO, RBTC and DOC as collateral", () => {
    async function baseSetup() {
      // use mainnet fork
      await resetFork(process.env["RSK_MAINNET_RPC"] || "https://public-node.rsk.co", 7490595);
      await helpers.impersonateAccount(bproHolderAddress);
      await helpers.impersonateAccount(docHolderAddress);

      ({ deployer } = await getNamedAccounts());
      const signer = await ethers.getSigner(deployer);

      const mocContracts = await loadFixture(fixtureFork2);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);

      // there is no setter, enforce ac token address writing the storage
      await network.provider.send("hardhat_setStorageAt", [
        buckets[0].mocImpl.target.toString(),
        ethers.toQuantity(553), // Slot acToken
        ethers.zeroPadValue(BPRO, 32),
      ]);

      buckets[0].collateralAsset = ERC20__factory.connect(await buckets[0].mocImpl.acToken(), signer);

      await network.provider.send("hardhat_setStorageAt", [
        buckets[2].mocImpl.target.toString(),
        ethers.toQuantity(553), // Slot acToken
        ethers.zeroPadValue(DOC, 32),
      ]);

      buckets[2].collateralAsset = ERC20__factory.connect(await buckets[2].mocImpl.acToken(), signer);
      governorMock = GovernorMock__factory.connect(await buckets[0].mocImpl.governor(), signer);

      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });

      mocCore0 = buckets[0].mocImpl.target.toString();
      mocCore1 = buckets[1].mocImpl.target.toString();
      mocCore2 = buckets[2].mocImpl.target.toString();
      tp = tps[0].target.toString();

      await helpers.setBalance(bproHolderAddress, pEth(10000000));
      await helpers.setBalance(docHolderAddress, pEth(10000000));

      // add collateral
      await Promise.all([
        mocFunctions[0].mintTC({ from: bproHolderAddress, qTC: 10, execute: false }),
        mocFunctions[1].mintTC({ from: docHolderAddress, qTC: 10, execute: false }),
        mocFunctions[2].mintTC({ from: docHolderAddress, qTC: 10, execute: false }),
      ]);
      // add TPs
      await Promise.all([
        mocFunctions[0].mintTP({ from: bproHolderAddress, tp, qTP: 1, execute: false }),
        mocFunctions[1].mintTP({ from: docHolderAddress, tp, qTP: 1, execute: false }),
        mocFunctions[2].mintTP({ from: docHolderAddress, tp, qTP: 1, execute: false }),
      ]);
      await mocMultiCollateralGuard.execute();

      // only swap 1 AC to don't empty the pool and get wrong conversions
      const dataProviderMockFactory = await ethers.getContractFactory("DataProviderMock");
      maxACtoSwapProvider = (await dataProviderMockFactory.deploy(pEth(1))).target.toString();

      // deploy MocSwapperV3
      const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
      const mocSwapperV3Factory = await ethers.getContractFactory("MocSwapperV3MultiHop");
      const mocSwapperV3Impl = await mocSwapperV3Factory.deploy();
      let erc1967Proxy = await erc1967ProxyFactory.deploy(mocSwapperV3Impl.target, "0x");
      mocSwapperV3 = MocSwapperV3MultiHop__factory.connect(erc1967Proxy.target.toString(), signer);
      await mocSwapperV3.initialize(governorMock.target, await buckets[0].mocImpl.pauser(), swapRouterV2, WRBTC);
      // set path MocSwapperV3MultiHop for BPRO -> DOC
      await mocSwapperV3.setPath(BPRO, DOC, [WRBTC, USDT], [3000, 3000, 500], maxACtoSwapProvider);
      await mocSwapperV3.setPath(DOC, BPRO, [USDT, WRBTC], [500, 3000, 3000], maxACtoSwapProvider);
      // set path MocSwapperV3MultiHop for RBTC -> DOC
      await mocSwapperV3.setPath(RBTC, DOC, [USDT], [3000, 500], maxACtoSwapProvider);
      await mocSwapperV3.setPath(DOC, RBTC, [USDT], [500, 3000], maxACtoSwapProvider);

      await mocMultiCollateralGuard.setMocSwapper(mocCore0, mocCore2, mocSwapperV3.target.toString());
      await mocMultiCollateralGuard.setMocSwapper(mocCore1, mocCore2, mocSwapperV3.target.toString());
    }

    describe("WHEN BPRO bucket falls under liquidation threshold and DOC bucket is the target to rebalance", () => {
      before(async () => {
        await loadFixture(baseSetup);
        await buckets[0].priceProviders[tp].poke(pEth(0.11));
        // increase bucket 2 score to be the target bucket to rebalance
        await mocFunctions[2].mintTC({ from: docHolderAddress, qTC: 1, execute: true });
      });
      describe("AND micro liquidation is executed", () => {
        let mocCore0ACBalance: Balance;
        let mocCore2ACBalance: Balance;
        before(async () => {
          mocCore0ACBalance = await mocFunctions[0].acBalanceOf(mocCore0);
          mocCore2ACBalance = await mocFunctions[2].acBalanceOf(mocCore2);
          await mocMultiCollateralGuard.execMicroLiquidation(mocCore0);
        });
        it("THEN BPRO is swapped for DOC at a price of 1 DOC = 0.0000088 BPRO", async () => {
          const bproSwapped = mocCore0ACBalance - (await mocFunctions[0].acBalanceOf(mocCore0));
          const docSwapped = (await mocFunctions[2].acBalanceOf(mocCore2)) - mocCore2ACBalance;
          assertPrec(bproSwapped, pEth(1));
          assertPrec((bproSwapped * BigInt(1e18)) / docSwapped, "0.000008806069888713");
        });
      });
    });
    describe("WHEN DOC bucket falls under liquidation threshold and BPRO bucket is the target to rebalance", () => {
      before(async () => {
        await loadFixture(baseSetup);
        await buckets[2].priceProviders[tp].poke(pEth(0.11));
        // increase bucket 0 score to be the target bucket to rebalance
        await mocFunctions[0].mintTC({ from: bproHolderAddress, qTC: 1, execute: true });
        await buckets[0].priceProviders[tp].poke(pEth(1000000)); // increase price to do not revert by qACmin
        await buckets[1].priceProviders[tp].poke(pEth(1000000)); // increase price to do not revert by qACmin
      });
      describe("AND micro liquidation is executed", () => {
        let mocCore0ACBalance: Balance;
        let mocCore2ACBalance: Balance;
        before(async () => {
          mocCore0ACBalance = await mocFunctions[0].acBalanceOf(mocCore0);
          mocCore2ACBalance = await mocFunctions[2].acBalanceOf(mocCore2);
          await mocMultiCollateralGuard.execMicroLiquidation(mocCore2);
        });
        it("THEN DOC is swapped for BPRO at a price of 1 BPRO = 117749.59 DOC", async () => {
          const docSwapped = mocCore2ACBalance - (await mocFunctions[2].acBalanceOf(mocCore2));
          const bproSwapped = (await mocFunctions[0].acBalanceOf(mocCore0)) - mocCore0ACBalance;
          assertPrec(docSwapped, pEth(1));
          assertPrec((docSwapped * BigInt(1e18)) / bproSwapped, "117749.595320607318206735");
        });
      });
    });
    describe("WHEN RBTC bucket falls under liquidation threshold and DOC bucket is the target to rebalance", () => {
      before(async () => {
        await loadFixture(baseSetup);
        await buckets[1].priceProviders[tp].poke(pEth(0.11));
        // increase bucket 2 score to be the target bucket to rebalance
        await mocFunctions[2].mintTC({ from: docHolderAddress, qTC: 1, execute: true });
      });
      describe("AND micro liquidation is executed", () => {
        let mocCore1ACBalance: Balance;
        let mocCore2ACBalance: Balance;
        before(async () => {
          mocCore1ACBalance = await mocFunctions[1].acBalanceOf(mocCore1);
          mocCore2ACBalance = await mocFunctions[2].acBalanceOf(mocCore2);
          await mocMultiCollateralGuard.execMicroLiquidation(mocCore1);
        });
        it("THEN RBTC is swapped for DOC at a price of 1 DOC = 0.00001 RBTC", async () => {
          const rbtcSwapped = mocCore1ACBalance - (await mocFunctions[1].acBalanceOf(mocCore1));
          const docSwapped = (await mocFunctions[2].acBalanceOf(mocCore2)) - mocCore2ACBalance;
          assertPrec(rbtcSwapped, pEth(1));
          assertPrec((rbtcSwapped * BigInt(1e18)) / docSwapped, "0.000010742705003141");
        });
      });
    });
    describe("WHEN DOC bucket falls under liquidation threshold and RBTC bucket is the target to rebalance", () => {
      before(async () => {
        await loadFixture(baseSetup);
        await buckets[2].priceProviders[tp].poke(pEth(0.11));
        // increase bucket 1 score to be the target bucket to rebalance
        await mocFunctions[1].mintTC({ from: docHolderAddress, qTC: 1, execute: true });
        await buckets[0].priceProviders[tp].poke(pEth(1000000)); // increase price to do not revert by qACmin
        await buckets[1].priceProviders[tp].poke(pEth(1000000)); // increase price to do not revert by qACmin
      });
      describe("AND micro liquidation is executed", () => {
        let mocCore1ACBalance: Balance;
        let mocCore2ACBalance: Balance;
        before(async () => {
          mocCore1ACBalance = await mocFunctions[1].acBalanceOf(mocCore1);
          mocCore2ACBalance = await mocFunctions[2].acBalanceOf(mocCore2);
          await mocMultiCollateralGuard.execMicroLiquidation(mocCore2);
        });
        it("THEN DOC is swapped for RBTC at a price of 1 RBTC = 95445.96 DOC", async () => {
          const docSwapped = mocCore2ACBalance - (await mocFunctions[2].acBalanceOf(mocCore2));
          const rbtcwapped = (await mocFunctions[1].acBalanceOf(mocCore1)) - mocCore1ACBalance;
          assertPrec(docSwapped, pEth(1));
          assertPrec((docSwapped * BigInt(1e18)) / rbtcwapped, "95445.961519544968438784");
        });
      });
    });
    describe("WHEN the path is set using wrong path parameters", () => {
      it("THEN the tx reverts with WrongLength", async () => {
        await loadFixture(baseSetup);
        await expect(mocSwapperV3.setPath(RBTC, DOC, [], [], RBTC)).to.be.revertedWithCustomError(
          mocSwapperV3,
          "WrongLength",
        );
      });
    });
    describe("WHEN a not authorized changer tries to set a pool", () => {
      it("THEN tx reverts", async () => {
        await loadFixture(baseSetup);
        await governorMock.setIsAuthorized(false);
        await expect(mocSwapperV3.setPath(RBTC, DOC, [], [], RBTC)).to.be.revertedWithCustomError(
          mocSwapperV3,
          ERRORS.NOT_AUTH_CHANGER,
        );
      });
    });
    after(async () => {
      await resetFork();
    });
  });
});
