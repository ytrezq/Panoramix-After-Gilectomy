import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/dist/types";
import { ContractRunner } from "ethers";
import { expect } from "chai";
import { CONSTANTS, pEth, resetFork } from "../../helpers/utils";
import {
  ERC20,
  ERC20__factory,
  GovernorMock,
  MocSwapperV4MultiHop,
  MocSwapperV4MultiHop__factory,
} from "../../../typechain";

const helpers = require("@nomicfoundation/hardhat-network-helpers");

// Ethereum mainnet fork settings
const holderAddress = "0x6AC38D1b2f0c0c3b9E816342b1CA14d91D5Ff60B"; // https://etherscan.io/address/0x6AC38D1b2f0c0c3b9E816342b1CA14d91D5Ff60B
const USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7"; // https://etherscan.io/address/0xdAC17F958D2ee523a2206206994597C13D831ec7
const WBTC = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"; // https://etherscan.io/address/0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
const universalRouter = "0x66a9893cc07d91d95644aedd05d03f95e1dba8af"; // https://etherscan.io/address/0x66a9893cc07d91d95644aedd05d03f95e1dba8af
const permit2 = "0x000000000022D473030F116dDEE9F6B43aC78BA3"; // https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3
const hooks = CONSTANTS.ZERO_ADDRESS;
const ETH = CONSTANTS.ZERO_ADDRESS;
const fee = 3000;
const tickSpacing = 60;

// FIXME: test skipped because it fails on CI but passes locally. It could be an issue with the RPC node or the HH fork.
//  Review it before deploying a multicollateral implementation on ethereum network
describe.skip("MocSwapperV4MultiHop forked Ethereum mainnet", function () {
  let deployer: Address;
  let mocSwapperV4MultiHop: MocSwapperV4MultiHop;
  let governor: GovernorMock;
  let holder: ContractRunner;
  let wbtcToken: ERC20;
  let usdtToken: ERC20;

  before(async function () {
    // use mainnet fork
    await resetFork(process.env["ETH_MAINNET_RPC"] || "https://eth.llamarpc.com", 24000000);
    await helpers.impersonateAccount(holderAddress);

    ({ deployer } = await getNamedAccounts());
    const signer = await ethers.getSigner(deployer);

    holder = await ethers.getSigner(holderAddress);
    await helpers.setBalance(holderAddress, pEth(10000000));

    wbtcToken = ERC20__factory.connect(WBTC, signer);
    usdtToken = ERC20__factory.connect(USDT, signer);

    // Deploy GovernorMock
    const GovernorMockFactory = await ethers.getContractFactory("GovernorMock");
    governor = await GovernorMockFactory.deploy();

    const dataProviderMockFactory = await ethers.getContractFactory("DataProviderMock");
    const providerSwap = (await dataProviderMockFactory.deploy(CONSTANTS.MAX_UINT256)).target.toString();

    // deploy MocSwapperV4MultiHop
    const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
    const mocSwapperV4MultiHopFactory = await ethers.getContractFactory("MocSwapperV4MultiHop");
    const mocSwapperV4MultiHopImpl = await mocSwapperV4MultiHopFactory.deploy();
    const erc1967Proxy = await erc1967ProxyFactory.deploy(mocSwapperV4MultiHopImpl.target, "0x");
    mocSwapperV4MultiHop = MocSwapperV4MultiHop__factory.connect(erc1967Proxy.target.toString(), signer);
    await mocSwapperV4MultiHop.initialize(governor.target, deployer, universalRouter, permit2);

    // Set multihop path: USDT -> WBTC -> ETH
    await mocSwapperV4MultiHop.setPath(
      USDT,
      ETH,
      [], // intermediate tokens
      [fee], // fees
      [tickSpacing], // tickSpacings
      [hooks], // hooks
      providerSwap,
    );
    await mocSwapperV4MultiHop.setPath(ETH, USDT, [], [fee], [tickSpacing], [hooks], providerSwap);
    await mocSwapperV4MultiHop.setPath(WBTC, USDT, [], [fee], [tickSpacing], [hooks], providerSwap);
    await mocSwapperV4MultiHop.setPath(USDT, WBTC, [], [fee], [tickSpacing], [hooks], providerSwap);
  });

  it("swapRC20ExactInput - swap RC20 for Coinbase", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const ethBalanceBefore = await ethers.provider.getBalance(holderAddress);
    const amountIn = pEth(5000) / 10n ** 12n; // USDT has 6 decimals
    const amountOutMin = pEth(1);
    await usdtToken.connect(holder).approve(mocSwapperV4MultiHop.target, 0);
    await usdtToken.connect(holder).approve(mocSwapperV4MultiHop.target, amountIn);
    await mocSwapperV4MultiHop.connect(holder).swapRC20(USDT, ETH, amountIn, amountOutMin, holderAddress);
    // Check balances
    // The ETH balance must increase at least amountOutMin
    const ethBalance = await ethers.provider.getBalance(holderAddress);
    expect(ethBalance - ethBalanceBefore).to.be.gte(amountOutMin);
    // The USDT balance must decrease exactly amountIn
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalanceBefore - usdtBalance).to.be.eq(amountIn);
  });

  it("swapRC20ExactOutput - swap RC20 for Coinbase", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const ethBalanceBefore = await ethers.provider.getBalance(holderAddress);
    const amountOut = pEth(1);
    const amountInMax = pEth(5000) / 10n ** 12n; // USDT has 6 decimals
    await usdtToken.connect(holder).approve(mocSwapperV4MultiHop.target, 0);
    await usdtToken.connect(holder).approve(mocSwapperV4MultiHop.target, amountInMax);
    await mocSwapperV4MultiHop.connect(holder).swapRC20ExactOutput(USDT, ETH, amountOut, amountInMax, holderAddress);
    // Check balances
    // The ETH balance must increase exactly amountOut
    const ethBalance = await ethers.provider.getBalance(holderAddress);
    expect(ethBalance - ethBalanceBefore).to.be.eq(amountOut);
    // The USDT balance must decrease at most amountInMax
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalanceBefore - usdtBalance).to.be.lt(amountInMax);
  });

  it("swapRC20ExactInput - swap RC20 for RC20", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const wbtcBalanceBefore = await wbtcToken.balanceOf(holderAddress);
    const amountIn = pEth(15000) / 10n ** 12n; // USDT has 6 decimals
    const amountOutMin = pEth(0.1) / 10n ** 10n; // WBTC has 8 decimals
    await usdtToken.connect(holder).approve(mocSwapperV4MultiHop.target, 0);
    await usdtToken.connect(holder).approve(mocSwapperV4MultiHop.target, amountIn);
    await mocSwapperV4MultiHop.connect(holder).swapRC20(USDT, WBTC, amountIn, amountOutMin, holderAddress);
    // Check balances
    // The WBTC balance must increase at least amountOutMin
    const wbtcBalance = await wbtcToken.balanceOf(holderAddress);
    expect(wbtcBalance - wbtcBalanceBefore).to.be.gte(amountOutMin);
    // The USDT balance must decrease exactly amountIn
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalanceBefore - usdtBalance).to.be.eq(amountIn);
  });

  it("swapRC20ExactOutput - swap RC20 for RC20", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const wbtcBalanceBefore = await wbtcToken.balanceOf(holderAddress);
    const amountOut = pEth(0.1) / 10n ** 10n; // WBTC has 8 decimals
    const amountInMax = pEth(15000) / 10n ** 12n; // USDT has 6 decimals
    await usdtToken.connect(holder).approve(mocSwapperV4MultiHop.target, 0);
    await usdtToken.connect(holder).approve(mocSwapperV4MultiHop.target, amountInMax);
    await mocSwapperV4MultiHop.connect(holder).swapRC20ExactOutput(USDT, WBTC, amountOut, amountInMax, holderAddress);
    // Check balances
    // The WBTC balance must increase exactly amountOut
    const wbtcBalance = await wbtcToken.balanceOf(holderAddress);
    expect(wbtcBalance - wbtcBalanceBefore).to.be.eq(amountOut);
    // The USDT balance must decrease at most amountInMax
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalanceBefore - usdtBalance).to.be.lt(amountInMax);
  });

  it("swapCoinbaseExactInput - swap Coinbase for RC20", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const ethBalanceBefore = await ethers.provider.getBalance(holderAddress);
    const amountIn = pEth(1);
    const amountOutMin = pEth(2792) / 10n ** 12n; // USDT has 6 decimals
    await mocSwapperV4MultiHop.connect(holder).swapCoinbase(USDT, amountOutMin, holderAddress, {
      value: amountIn,
    });
    // Check balances
    // The USDT balance must increase at least amountOutMin
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalance - usdtBalanceBefore).to.be.gte(amountOutMin);
    // The ETH balance must decrease exactly amountIn
    const ethBalance = await ethers.provider.getBalance(holderAddress);
    expect(ethBalanceBefore - ethBalance).to.be.eq(amountIn);
  });

  it("swapCoinbaseExactOutput - swap Coinbase for RC20", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const ethBalanceBefore = await ethers.provider.getBalance(holderAddress);
    const amountOut = pEth(3000) / 10n ** 12n; // USDT has 6 decimals
    const amountInMax = pEth(10);
    await mocSwapperV4MultiHop.connect(holder).swapCoinbaseExactOutput(USDT, amountOut, holderAddress, {
      value: amountInMax,
    });
    // Check balances
    // The USDT balance must increase exactly amountOut
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalance - usdtBalanceBefore).to.be.eq(amountOut);
    // The ETH balance must decrease at most amountInMax
    const ethBalance = await ethers.provider.getBalance(holderAddress);
    expect(ethBalanceBefore - ethBalance).to.be.lt(amountInMax);
  });
});
