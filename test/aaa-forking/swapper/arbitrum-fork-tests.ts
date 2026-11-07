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
  MocSwapperV3__factory,
  MocSwapperV4,
  MocSwapperV4__factory,
} from "../../../typechain";
import { fixtureFork } from "../../multicollateral/fixture";
import { assertPrec } from "../../helpers/assertHelper";
const helpers = require("@nomicfoundation/hardhat-network-helpers");

timedDescribe("Feature: MocSwappersV3 & V4 with uniswap - arbitrum fork", function () {
  let mocFunctions = new Array<any>(2);
  let buckets = new Array<any>(2);
  let tps = new Array<any>(1);
  let mocCore0: Address;
  let mocCore1: Address;
  let tp: Address;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let governorMock: GovernorMock;
  let deployer: Address;
  let mocSwapperV3Address: Address;
  let mocSwapperV4Address: Address;
  let mocSwapperV4: MocSwapperV4;
  const holderAddress = "0x2d070ed1321871841245D8EE5B84bD2712644322"; // https://arbiscan.io/address/0x2d070ed1321871841245D8EE5B84bD2712644322
  const WETH = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"; // https://arbiscan.io/address/0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
  const DAI = "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1"; // https://arbiscan.io/address/0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1
  const swapRouterV2 = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"; // https://arbiscan.io/address/0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
  const universalRouter = "0xa51afafe0263b40edaef0df8781ea9aa03e381a3"; // https://arbiscan.io/address/0xa51afafe0263b40edaef0df8781ea9aa03e381a3
  const permit2 = "0x000000000022D473030F116dDEE9F6B43aC78BA3"; // https://arbiscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3
  const hooks = CONSTANTS.ZERO_ADDRESS;
  const ETH = CONSTANTS.ZERO_ADDRESS;
  const fee = 3000;
  const tickSpacing = 60;

  // FIXME: test skipped because it fails on CI but passes locally. It could be an issue with the RPC node or the HH fork.
  //  Review it before deploying a multicollateral implementation on arbitrum network
  describe.skip("GIVEN 2 Moc implementations deployed on arbitrum mainnet using ETH and DAI as collateral", () => {
    async function baseSetup() {
      // use mainnet fork
      await resetFork("https://arb1.arbitrum.io/rpc", 314924472);
      await helpers.impersonateAccount(holderAddress);

      ({ deployer } = await getNamedAccounts());
      const signer = await ethers.getSigner(deployer);

      const mocContracts = await loadFixture(fixtureFork);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);

      // there is no setter, enforce ac token address writing the storage
      await network.provider.send("hardhat_setStorageAt", [
        buckets[0].mocImpl.target.toString(),
        ethers.toQuantity(553), // Slot acToken
        ethers.zeroPadValue(DAI, 32),
      ]);

      buckets[0].collateralAsset = ERC20__factory.connect(await buckets[0].mocImpl.acToken(), signer);
      governorMock = GovernorMock__factory.connect(await buckets[0].mocImpl.governor(), signer);

      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });

      mocCore0 = buckets[0].mocImpl.target.toString();
      mocCore1 = buckets[1].mocImpl.target.toString();
      tp = tps[0].target.toString();

      await helpers.setBalance(holderAddress, pEth(10000000));

      // add collateral
      await Promise.all([
        mocFunctions[0].mintTC({ from: holderAddress, qTC: 100, execute: false }),
        mocFunctions[1].mintTC({ from: holderAddress, qTC: 100, execute: false }),
      ]);
      // add TPs
      await Promise.all([
        mocFunctions[0].mintTP({ from: holderAddress, tp, qTP: 10, execute: false }),
        mocFunctions[1].mintTP({ from: holderAddress, tp, qTP: 10, execute: false }),
      ]);

      await mocMultiCollateralGuard.execute();

      // only swap 1 AC to don't empty the pool and get wrong conversions
      const dataProviderMockFactory = await ethers.getContractFactory("DataProviderMock");
      const providerSwappingETHtoDAI = (await dataProviderMockFactory.deploy(pEth(1))).target.toString();
      const providerSwappingDAItoETH = (await dataProviderMockFactory.deploy(pEth(1))).target.toString();

      const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
      // deploy MocSwapperV3
      const mocSwapperV3Factory = await ethers.getContractFactory("MocSwapperV3");
      const mocSwapperV3Impl = await mocSwapperV3Factory.deploy();
      let erc1967Proxy = await erc1967ProxyFactory.deploy(mocSwapperV3Impl.target, "0x");
      const mocSwapperV3 = MocSwapperV3__factory.connect(erc1967Proxy.target.toString(), signer);
      await mocSwapperV3.initialize(governorMock.target, await buckets[0].mocImpl.pauser(), swapRouterV2, WETH);
      await mocSwapperV3.setPool(ETH, DAI, fee, providerSwappingETHtoDAI);
      await mocSwapperV3.setPool(DAI, ETH, fee, providerSwappingDAItoETH);
      mocSwapperV3Address = mocSwapperV3.target.toString();
      // deploy MocSwapperV4
      const mocSwapperV4Factory = await ethers.getContractFactory("MocSwapperV4");
      const mocSwapperV4Impl = await mocSwapperV4Factory.deploy();
      erc1967Proxy = await erc1967ProxyFactory.deploy(mocSwapperV4Impl.target, "0x");
      mocSwapperV4 = MocSwapperV4__factory.connect(erc1967Proxy.target.toString(), signer);
      await mocSwapperV4.initialize(governorMock.target, await buckets[0].mocImpl.pauser(), universalRouter, permit2);
      await mocSwapperV4.setPool(ETH, DAI, fee, tickSpacing, hooks, providerSwappingETHtoDAI);
      await mocSwapperV4.setPool(DAI, ETH, fee, tickSpacing, hooks, providerSwappingDAItoETH);
      mocSwapperV4Address = mocSwapperV4.target.toString();
    }

    describe("WHEN TP prices fall on bucket 0 making coverage go below the rebalance threshold", () => {
      describe("AND a MocSwapperV3 using uniswapV3 is set on the ETH/DAI pair", () => {
        before(async () => {
          await loadFixture(baseSetup);
          await buckets[0].priceProviders[tp].poke(pEth(0.11));
          await buckets[1].priceProviders[tp].poke(pEth(1000000)); // increase price to do not revert by qACmin
          await mocMultiCollateralGuard.setMocSwapper(mocCore0, mocCore1, mocSwapperV3Address);
        });
        describe("AND micro liquidation is executed", () => {
          let mocCore1ACBalance: Balance;
          before(async () => {
            mocCore1ACBalance = await mocFunctions[1].acBalanceOf(mocCore1);
            await mocMultiCollateralGuard.execMicroLiquidation(mocCore0);
          });
          it("THEN DAI is swapped for ETH at a price of 1914.10", async () => {
            const daiSwapped = pEth(1);
            const ethSwapped = (await mocFunctions[1].acBalanceOf(mocCore1)) - mocCore1ACBalance;
            assertPrec((daiSwapped * BigInt(1e18)) / ethSwapped, "1914.108955327586994685");
          });
        });
      });
      describe("AND a MocSwapperV4 using uniswapV4 is set on the ETH/DAI pair", () => {
        before(async () => {
          await loadFixture(baseSetup);
          await buckets[0].priceProviders[tp].poke(pEth(0.11));
          await buckets[1].priceProviders[tp].poke(pEth(1000000)); // increase price to do not revert by qACmin
          await mocMultiCollateralGuard.setMocSwapper(mocCore0, mocCore1, mocSwapperV4Address);
        });
        describe("AND micro liquidation is executed", () => {
          let mocCore1ACBalance: Balance;
          before(async () => {
            mocCore1ACBalance = await mocFunctions[1].acBalanceOf(mocCore1);
            await mocMultiCollateralGuard.execMicroLiquidation(mocCore0);
          });
          it("THEN DAI is swapped for ETH at a price of 1918.87", async () => {
            const daiSwapped = pEth(1);
            const ethSwapped = (await mocFunctions[1].acBalanceOf(mocCore1)) - mocCore1ACBalance;
            assertPrec((daiSwapped * BigInt(1e18)) / ethSwapped, "1918.877039088532960775");
          });
        });
      });
    });
    describe("WHEN TP prices fall on bucket 1 making coverage go below the rebalance threshold", () => {
      describe("AND a MocSwapperV3 using uniswapV3 is set on the ETH/DAI pair", () => {
        before(async () => {
          await loadFixture(baseSetup);
          await buckets[1].priceProviders[tp].poke(pEth(0.11));
          await mocMultiCollateralGuard.setMocSwapper(mocCore0, mocCore1, mocSwapperV3Address);
        });
        describe("AND micro liquidation is executed", () => {
          let mocCore0ACBalance: Balance;
          before(async () => {
            mocCore0ACBalance = await mocFunctions[0].acBalanceOf(mocCore0);
            await mocMultiCollateralGuard.execMicroLiquidation(mocCore1);
          });
          it("THEN ETH is swapped for DAI at a price of 0.0005", async () => {
            const ethSwapped = pEth(1);
            const daiSwapped = (await mocFunctions[0].acBalanceOf(mocCore0)) - mocCore0ACBalance;
            assertPrec((ethSwapped * BigInt(1e18)) / daiSwapped, "0.000526634752172119");
          });
        });
      });
      describe("AND a MocSwapperV4 using uniswapV4 is set on the ETH/DAI pair", () => {
        before(async () => {
          await loadFixture(baseSetup);
          await buckets[1].priceProviders[tp].poke(pEth(0.11));
          await mocMultiCollateralGuard.setMocSwapper(mocCore0, mocCore1, mocSwapperV4Address);
        });
        describe("AND micro liquidation is executed", () => {
          let mocCore0ACBalance: Balance;
          before(async () => {
            mocCore0ACBalance = await mocFunctions[0].acBalanceOf(mocCore0);
            await mocMultiCollateralGuard.execMicroLiquidation(mocCore1);
          });
          it("THEN ETH is swapped for DAI at a price of 0.0009", async () => {
            const ethSwapped = pEth(1);
            const daiSwapped = (await mocFunctions[0].acBalanceOf(mocCore0)) - mocCore0ACBalance;
            assertPrec((ethSwapped * BigInt(1e18)) / daiSwapped, "0.000921068728525374");
          });
        });
      });
    });
    describe("WHEN a not authorized changer tries to set a pool", () => {
      it("THEN tx reverts", async () => {
        await loadFixture(baseSetup);
        await governorMock.setIsAuthorized(false);
        await expect(mocSwapperV4.setPool(ETH, DAI, fee, tickSpacing, hooks, DAI)).to.be.revertedWithCustomError(
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
