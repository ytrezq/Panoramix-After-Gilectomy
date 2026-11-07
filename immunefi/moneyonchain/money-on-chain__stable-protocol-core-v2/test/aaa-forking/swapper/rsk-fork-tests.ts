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
  MocSwapperV3,
  MocSwapperV3__factory,
} from "../../../typechain";
import { fixtureFork } from "../../multicollateral/fixture";
import { assertPrec } from "../../helpers/assertHelper";
const helpers = require("@nomicfoundation/hardhat-network-helpers");

timedDescribe("Feature: MocSwappersV3 with uniswap - rsk fork", function () {
  let mocFunctions = new Array<any>(2);
  let buckets = new Array<any>(2);
  let tps = new Array<any>(1);
  let mocCore0: Address;
  let mocCore1: Address;
  let tp: Address;
  let governorMock: GovernorMock;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let deployer: Address;
  let mocSwapperV3Address: Address;
  let mocSwapperV3: MocSwapperV3;
  const holderAddress = "0xD07d569322a93a47B62D71203e21f0AFf8246099"; // https://explorer.rootstock.io/address/0xD07d569322a93a47B62D71203e21f0AFf8246099
  const WRBTC = "0x542fDA317318eBF1d3DEAf76E0b632741A7e677d"; // https://explorer.rootstock.io/address/0x542fda317318ebf1d3deaf76e0b632741a7e677d
  const RIF = "0x2AcC95758f8b5F583470ba265EB685a8F45fC9D5"; // https://explorer.rootstock.io/address/0x2AcC95758f8b5F583470ba265EB685a8F45fC9D5
  const swapRouterV2 = "0x0B14ff67f0014046b4b99057Aec4509640b3947A"; // https://explorer.rootstock.io/address/0x0B14ff67f0014046b4b99057Aec4509640b3947A
  const fee = 3000;
  const RBTC = CONSTANTS.ZERO_ADDRESS;

  describe("GIVEN 2 Moc implementations deployed on rsk mainnet using RBTC and RIF as collateral", () => {
    async function baseSetup() {
      // use mainnet fork
      await resetFork(process.env["RSK_MAINNET_RPC"] || "https://public-node.rsk.co", 7334714);
      await helpers.impersonateAccount(holderAddress);

      ({ deployer } = await getNamedAccounts());
      const signer = await ethers.getSigner(deployer);

      const mocContracts = await loadFixture(fixtureFork);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);

      // there is no setter, enforce ac token address writing the storage
      await network.provider.send("hardhat_setStorageAt", [
        buckets[0].mocImpl.target.toString(),
        ethers.toQuantity(553), // Slot acToken
        ethers.zeroPadValue(RIF, 32),
      ]);

      buckets[0].collateralAsset = ERC20__factory.connect(await buckets[0].mocImpl.acToken(), signer);
      governorMock = GovernorMock__factory.connect(await buckets[0].mocImpl.governor(), signer);

      // RIF does not have increaseAllowance function, we must do it by approve
      const useAllowance = false;
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts }, useAllowance);
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });

      mocCore0 = buckets[0].mocImpl.target.toString();
      mocCore1 = buckets[1].mocImpl.target.toString();
      tp = tps[0].target.toString();

      await buckets[0].collateralAsset
        .connect(await ethers.getSigner(holderAddress))
        .approve(mocCore0, CONSTANTS.MAX_UINT256);
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
      const providerSwappingRBTCtoRIF = (await dataProviderMockFactory.deploy(pEth(1))).target.toString();
      const providerSwappingRIFtoRBTC = (await dataProviderMockFactory.deploy(pEth(1))).target.toString();

      // deploy MocSwapperV3
      const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
      const mocSwapperV3Factory = await ethers.getContractFactory("MocSwapperV3");
      const mocSwapperV3Impl = await mocSwapperV3Factory.deploy();
      let erc1967Proxy = await erc1967ProxyFactory.deploy(mocSwapperV3Impl.target, "0x");
      mocSwapperV3 = MocSwapperV3__factory.connect(erc1967Proxy.target.toString(), signer);
      await mocSwapperV3.initialize(governorMock.target, await buckets[0].mocImpl.pauser(), swapRouterV2, WRBTC);
      await mocSwapperV3.setPool(RBTC, RIF, fee, providerSwappingRBTCtoRIF);
      await mocSwapperV3.setPool(RIF, RBTC, fee, providerSwappingRIFtoRBTC);
      mocSwapperV3Address = mocSwapperV3.target.toString();
    }

    describe("WHEN TP prices fall on bucket 0 making coverage go below the rebalance threshold", () => {
      describe("WHEN micro liquidation is executed receiving less amount out that is expected", async () => {
        it("THEN tx reverts", async () => {
          await loadFixture(baseSetup);
          await buckets[0].priceProviders[tp].poke(pEth(0.11));
          await mocMultiCollateralGuard.setMocSwapper(mocCore0, mocCore1, mocSwapperV3Address);
          await expect(mocMultiCollateralGuard.execMicroLiquidation(mocCore0)).to.be.revertedWith(
            "Too little received",
          );
        });
      });
      describe("AND a MocSwapperV3 using uniswapV3 is set on the RBTC/RIF pair", () => {
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
          it("THEN RIF is swapped for RBTC at a price of 2040841.50", async () => {
            const rifSwapped = pEth(1);
            const rbtcSwapped = (await mocFunctions[1].acBalanceOf(mocCore1)) - mocCore1ACBalance;
            assertPrec((rifSwapped * BigInt(1e18)) / rbtcSwapped, "2040841.508728052383259604");
          });
        });
      });
    });
    describe("WHEN TP prices fall on bucket 1 making coverage go below the rebalance threshold", () => {
      describe("AND a MocSwapperV3 using uniswapV3 is set on the RBTC/RIF pair", () => {
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
          it("THEN RBTC is swapped for RIF at a price of 0.00000049", async () => {
            const rbtcSwapped = pEth(1);
            const rifSwapped = (await mocFunctions[0].acBalanceOf(mocCore0)) - mocCore0ACBalance;
            assertPrec((rbtcSwapped * BigInt(1e18)) / rifSwapped, "0.000000499385647126");
          });
        });
      });
    });
    describe("WHEN a not authorized changer tries to set a pool", () => {
      it("THEN tx reverts", async () => {
        await loadFixture(baseSetup);
        await governorMock.setIsAuthorized(false);
        await expect(mocSwapperV3.setPool(RBTC, RIF, fee, RBTC)).to.be.revertedWithCustomError(
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
