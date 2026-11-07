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
  MocSwapperV4MultiHop,
  MocSwapperV4MultiHop__factory,
} from "../../../typechain";
import { fixtureFork2 } from "../../multicollateral/fixture";
import { assertPrec } from "../../helpers/assertHelper";
const helpers = require("@nomicfoundation/hardhat-network-helpers");

timedDescribe("Feature: MocSwappersV4MultiHop with uniswap - arbitrum fork", function () {
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
  let mocSwapperV4: MocSwapperV4MultiHop;
  let maxACtoSwapProvider: Address;
  const crvHolderAddress = "0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D"; // https://arbiscan.io/address/0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D
  const daiHolderAddress = "0x2d070ed1321871841245D8EE5B84bD2712644322"; // https://arbiscan.io/address/0x2d070ed1321871841245D8EE5B84bD2712644322
  const CRV = "0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978"; // https://arbiscan.io/address/0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978
  const USDC = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"; // https://arbiscan.io/address/0xaf88d065e77c8cC2239327C5EDb3A432268e5831
  const DAI = "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1"; // https://arbiscan.io/address/0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1
  const universalRouter = "0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3"; // https://arbiscan.io/address/0xa51afafe0263b40edaef0df8781ea9aa03e381a3
  const permit2 = "0x000000000022D473030F116dDEE9F6B43aC78BA3"; // https://arbiscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3
  const ETH = CONSTANTS.ZERO_ADDRESS;
  const hooks = CONSTANTS.ZERO_ADDRESS;
  const tickSpacing = 60;

  // FIXME: test skipped because it fails on CI but passes locally. It could be an issue with the RPC node or the HH fork.
  //  Review it before deploying a multicollateral implementation on arbitrum network
  describe.skip("GIVEN 2 Moc implementations deployed on arbitrum mainnet using CRV, ETH and DAI as collateral", () => {
    async function baseSetup() {
      // use mainnet fork
      await resetFork("https://arb1.arbitrum.io/rpc", 331822441);
      await helpers.impersonateAccount(crvHolderAddress);
      await helpers.impersonateAccount(daiHolderAddress);

      ({ deployer } = await getNamedAccounts());
      const signer = await ethers.getSigner(deployer);

      const mocContracts = await loadFixture(fixtureFork2);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);

      // there is no setter, enforce ac token address writing the storage
      await network.provider.send("hardhat_setStorageAt", [
        buckets[0].mocImpl.target.toString(),
        ethers.toQuantity(553), // Slot acToken
        ethers.zeroPadValue(CRV, 32),
      ]);

      buckets[0].collateralAsset = ERC20__factory.connect(await buckets[0].mocImpl.acToken(), signer);
      governorMock = GovernorMock__factory.connect(await buckets[0].mocImpl.governor(), signer);

      await network.provider.send("hardhat_setStorageAt", [
        buckets[2].mocImpl.target.toString(),
        ethers.toQuantity(553), // Slot acToken
        ethers.zeroPadValue(DAI, 32),
      ]);

      buckets[2].collateralAsset = ERC20__factory.connect(await buckets[2].mocImpl.acToken(), signer);

      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });

      mocCore0 = buckets[0].mocImpl.target.toString();
      mocCore1 = buckets[1].mocImpl.target.toString();
      mocCore2 = buckets[2].mocImpl.target.toString();
      tp = tps[0].target.toString();

      await helpers.setBalance(crvHolderAddress, pEth(10000000));
      await helpers.setBalance(daiHolderAddress, pEth(10000000));

      // add collateral
      await Promise.all([
        mocFunctions[0].mintTC({ from: crvHolderAddress, qTC: 10, execute: false }),
        mocFunctions[1].mintTC({ from: daiHolderAddress, qTC: 10, execute: false }),
        mocFunctions[2].mintTC({ from: daiHolderAddress, qTC: 10, execute: false }),
      ]);
      // add TPs
      await Promise.all([
        mocFunctions[0].mintTP({ from: crvHolderAddress, tp, qTP: 1, execute: false }),
        mocFunctions[1].mintTP({ from: daiHolderAddress, tp, qTP: 1, execute: false }),
        mocFunctions[2].mintTP({ from: daiHolderAddress, tp, qTP: 1, execute: false }),
      ]);
      await mocMultiCollateralGuard.execute();

      // only swap 1 AC to don't empty the pool and get wrong conversions
      const dataProviderMockFactory = await ethers.getContractFactory("DataProviderMock");
      maxACtoSwapProvider = (await dataProviderMockFactory.deploy(pEth(1))).target.toString();

      // deploy MocSwapperV4
      const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
      const mocSwapperV4Factory = await ethers.getContractFactory("MocSwapperV4MultiHop");
      const mocSwapperV4Impl = await mocSwapperV4Factory.deploy();
      let erc1967Proxy = await erc1967ProxyFactory.deploy(mocSwapperV4Impl.target, "0x");
      mocSwapperV4 = MocSwapperV4MultiHop__factory.connect(erc1967Proxy.target.toString(), signer);
      await mocSwapperV4.initialize(governorMock.target, await buckets[0].mocImpl.pauser(), universalRouter, permit2);
      // set path MocSwapperV4MultiHop for CRV -> DAI
      await mocSwapperV4.setPath(
        CRV,
        DAI,
        [ETH, USDC],
        [3000, 3000, 100],
        [tickSpacing, tickSpacing, 1],
        [hooks, hooks, hooks],
        maxACtoSwapProvider,
      );
      await mocSwapperV4.setPath(
        DAI,
        CRV,
        [USDC, ETH],
        [100, 3000, 3000],
        [1, tickSpacing, tickSpacing],
        [hooks, hooks, hooks],
        maxACtoSwapProvider,
      );
      // set path MocSwapperV4MultiHop for ETH -> DAI
      await mocSwapperV4.setPath(ETH, DAI, [USDC], [3000, 100], [tickSpacing, 1], [hooks, hooks], maxACtoSwapProvider);
      await mocSwapperV4.setPath(DAI, ETH, [USDC], [100, 3000], [1, tickSpacing], [hooks, hooks], maxACtoSwapProvider);

      await mocMultiCollateralGuard.setMocSwapper(mocCore0, mocCore2, mocSwapperV4.target.toString());
      await mocMultiCollateralGuard.setMocSwapper(mocCore1, mocCore2, mocSwapperV4.target.toString());
    }

    describe("WHEN CRV bucket falls under liquidation threshold and DAI bucket is the target to rebalance", () => {
      before(async () => {
        await loadFixture(baseSetup);
        await buckets[0].priceProviders[tp].poke(pEth(0.11));
        // increase bucket 2 score to be the target bucket to rebalance
        await mocFunctions[2].mintTC({ from: daiHolderAddress, qTC: 1, execute: true });
      });
      describe("AND micro liquidation is executed", () => {
        let mocCore0ACBalance: Balance;
        let mocCore2ACBalance: Balance;
        before(async () => {
          mocCore0ACBalance = await mocFunctions[0].acBalanceOf(mocCore0);
          mocCore2ACBalance = await mocFunctions[2].acBalanceOf(mocCore2);
          await mocMultiCollateralGuard.execMicroLiquidation(mocCore0);
        });
        it("THEN CRV is swapped for DAI at a price of 1 DAI = 1.513 CRV", async () => {
          const crvSwapped = mocCore0ACBalance - (await mocFunctions[0].acBalanceOf(mocCore0));
          const daiSwapped = (await mocFunctions[2].acBalanceOf(mocCore2)) - mocCore2ACBalance;
          assertPrec(crvSwapped, pEth(1));
          assertPrec((crvSwapped * BigInt(1e18)) / daiSwapped, "1.513686443369181066");
        });
      });
    });
    describe("WHEN DAI bucket falls under liquidation threshold and CRV bucket is the target to rebalance", () => {
      before(async () => {
        await loadFixture(baseSetup);
        await buckets[2].priceProviders[tp].poke(pEth(0.11));
        // increase bucket 0 score to be the target bucket to rebalance
        await mocFunctions[0].mintTC({ from: crvHolderAddress, qTC: 1, execute: true });
      });
      describe("AND micro liquidation is executed", () => {
        let mocCore0ACBalance: Balance;
        let mocCore2ACBalance: Balance;
        before(async () => {
          mocCore0ACBalance = await mocFunctions[0].acBalanceOf(mocCore0);
          mocCore2ACBalance = await mocFunctions[2].acBalanceOf(mocCore2);
          await mocMultiCollateralGuard.execMicroLiquidation(mocCore2);
        });
        it("THEN DAI is swapped for CRV at a price of 1 CRV = 0.668 DAI", async () => {
          const daiSwapped = mocCore2ACBalance - (await mocFunctions[2].acBalanceOf(mocCore2));
          const crvSwapped = (await mocFunctions[0].acBalanceOf(mocCore0)) - mocCore0ACBalance;
          assertPrec(daiSwapped, pEth(1));
          assertPrec((daiSwapped * BigInt(1e18)) / crvSwapped, "0.668916197468253009");
        });
      });
    });
    describe("WHEN ETH bucket falls under liquidation threshold and DAI bucket is the target to rebalance", () => {
      before(async () => {
        await loadFixture(baseSetup);
        await buckets[1].priceProviders[tp].poke(pEth(0.11));
        // increase bucket 2 score to be the target bucket to rebalance
        await mocFunctions[2].mintTC({ from: daiHolderAddress, qTC: 1, execute: true });
      });
      describe("AND micro liquidation is executed", () => {
        let mocCore1ACBalance: Balance;
        let mocCore2ACBalance: Balance;
        before(async () => {
          mocCore1ACBalance = await mocFunctions[1].acBalanceOf(mocCore1);
          mocCore2ACBalance = await mocFunctions[2].acBalanceOf(mocCore2);
          await mocMultiCollateralGuard.execMicroLiquidation(mocCore1);
        });
        it("THEN ETH is swapped for DAI at a price of 1 DAI = 0.0008 ETH", async () => {
          const ethSwapped = mocCore1ACBalance - (await mocFunctions[1].acBalanceOf(mocCore1));
          const daiwapped = (await mocFunctions[2].acBalanceOf(mocCore2)) - mocCore2ACBalance;
          assertPrec(ethSwapped, pEth(1));
          assertPrec((ethSwapped * BigInt(1e18)) / daiwapped, "0.000865418385585233");
        });
      });
    });
    describe("WHEN DAI bucket falls under liquidation threshold and ETH bucket is the target to rebalance", () => {
      before(async () => {
        await loadFixture(baseSetup);
        await buckets[2].priceProviders[tp].poke(pEth(0.11));
        // increase bucket 1 score to be the target bucket to rebalance
        await mocFunctions[1].mintTC({ from: daiHolderAddress, qTC: 1, execute: true });
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
        it("THEN DAI is swapped for ETH at a price of 1 ETH = 1766.28 DAI", async () => {
          const daiSwapped = mocCore2ACBalance - (await mocFunctions[2].acBalanceOf(mocCore2));
          const ethSwapped = (await mocFunctions[1].acBalanceOf(mocCore1)) - mocCore1ACBalance;
          assertPrec(daiSwapped, pEth(1));
          assertPrec((daiSwapped * BigInt(1e18)) / ethSwapped, "1766.286027225741117208");
        });
      });
    });
    describe("WHEN the path is set using wrong path parameters", () => {
      it("THEN the tx reverts with WrongLength", async () => {
        await loadFixture(baseSetup);
        await expect(mocSwapperV4.setPath(ETH, DAI, [], [], [], [], DAI)).to.be.revertedWithCustomError(
          mocSwapperV4,
          "WrongLength",
        );
      });
    });
    describe("WHEN a not authorized changer tries to set a pool", () => {
      it("THEN tx reverts", async () => {
        await loadFixture(baseSetup);
        await governorMock.setIsAuthorized(false);
        await expect(mocSwapperV4.setPath(ETH, DAI, [], [], [], [], DAI)).to.be.revertedWithCustomError(
          mocSwapperV4,
          ERRORS.NOT_AUTH_CHANGER,
        );
      });
    });
    after(async () => {
      await resetFork();
    });
  });
});
