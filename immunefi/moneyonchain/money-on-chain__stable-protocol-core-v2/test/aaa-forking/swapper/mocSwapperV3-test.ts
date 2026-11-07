import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/dist/types";
import { ContractRunner } from "ethers";
import { expect } from "chai";
import { CONSTANTS, pEth, resetFork } from "../../helpers/utils";
import { ERC20, ERC20__factory, GovernorMock, MocSwapperV3, MocSwapperV3__factory } from "../../../typechain";

const helpers = require("@nomicfoundation/hardhat-network-helpers");

// RSK mainnet fork settings
const holderAddress = "0xa14088fc853059A2D3361aC145EeE1530c866BA4"; // https://explorer.rootstock.io/address/0xa14088fc853059A2D3361aC145EeE1530c866BA4
const WRBTC = "0x542fDA317318eBF1d3DEAf76E0b632741A7e677d"; // https://explorer.rootstock.io/address/0x542fda317318ebf1d3deaf76e0b632741a7e677d
const USDT = "0xAf368c91793CB22739386DFCbBb2F1A9e4bCBeBf"; // https://explorer.rootstock.io/address/0xAf368c91793CB22739386DFCbBb2F1A9e4bCBeBf
const swapRouterV2 = "0x0B14ff67f0014046b4b99057Aec4509640b3947A"; // https://explorer.rootstock.io/address/0x0B14ff67f0014046b4b99057Aec4509640b3947A
const fee = 3000;
const RBTC = CONSTANTS.ZERO_ADDRESS;

describe("MocSwapperV3 forked RSK mainnet", function () {
  let deployer: Address;
  let mocSwapperV3: MocSwapperV3;
  let governor: GovernorMock;
  let holder: ContractRunner;
  let usdtToken: ERC20;
  let wrbtcToken: ERC20;

  before(async function () {
    // use mainnet fork
    await resetFork(process.env["RSK_MAINNET_RPC"] || "https://public-node.rsk.co", 8057900);
    await helpers.impersonateAccount(holderAddress);

    ({ deployer } = await getNamedAccounts());
    const signer = await ethers.getSigner(deployer);

    holder = await ethers.getSigner(holderAddress);
    await helpers.setBalance(holderAddress, pEth(10000000));

    usdtToken = ERC20__factory.connect(USDT, signer);
    wrbtcToken = ERC20__factory.connect(WRBTC, signer);

    // Deploy GovernorMock
    const GovernorMockFactory = await ethers.getContractFactory("GovernorMock");
    governor = await GovernorMockFactory.deploy();

    const dataProviderMockFactory = await ethers.getContractFactory("DataProviderMock");
    const providerSwap = (await dataProviderMockFactory.deploy(CONSTANTS.MAX_UINT256)).target.toString();

    // deploy MocSwapperV3
    const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
    const mocSwapperV3Factory = await ethers.getContractFactory("MocSwapperV3");
    const mocSwapperV3Impl = await mocSwapperV3Factory.deploy();
    let erc1967Proxy = await erc1967ProxyFactory.deploy(mocSwapperV3Impl.target, "0x");
    mocSwapperV3 = MocSwapperV3__factory.connect(erc1967Proxy.target.toString(), signer);
    await mocSwapperV3.initialize(governor.target, deployer, swapRouterV2, WRBTC);
    await mocSwapperV3.setPool(RBTC, USDT, fee, providerSwap);
    await mocSwapperV3.setPool(USDT, RBTC, fee, providerSwap);

    await mocSwapperV3.setPool(USDT, WRBTC, fee, providerSwap);
    await mocSwapperV3.setPool(WRBTC, USDT, fee, providerSwap);
  });

  it("swapRC20ExactInput - swap RC20 for Coinbase", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const rbtcBalanceBefore = await ethers.provider.getBalance(holderAddress);
    const amountIn = pEth(15000) / 10n ** 12n; // USDT has 6 decimals
    const amountOutMin = pEth(0.01);
    await usdtToken.connect(holder).approve(mocSwapperV3.target, amountIn);
    await mocSwapperV3.connect(holder).swapRC20(USDT, RBTC, amountIn, amountOutMin, holderAddress);
    // Check balances
    // The RBTC balance must increase at least amountOutMin
    const rbtcBalance = await ethers.provider.getBalance(holderAddress);
    expect(rbtcBalance - rbtcBalanceBefore).to.be.gte(amountOutMin);
    // The USDT balance must decrease exactly amountIn
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalanceBefore - usdtBalance).to.be.eq(amountIn);
  });

  it("swapRC20ExactOutput - swap RC20 for Coinbase", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const rbtcBalanceBefore = await ethers.provider.getBalance(holderAddress);
    const amountOut = pEth(0.01);
    const amountInMax = pEth(15000) / 10n ** 12n; // USDT has 6 decimals
    await usdtToken.connect(holder).approve(mocSwapperV3.target, amountInMax);
    await mocSwapperV3.connect(holder).swapRC20ExactOutput(USDT, RBTC, amountOut, amountInMax, holderAddress);
    // Check balances
    // The RBTC balance must increase exactly amountOut
    const rbtcBalance = await ethers.provider.getBalance(holderAddress);
    expect(rbtcBalance - rbtcBalanceBefore).to.be.eq(amountOut);
    // The USDT balance must decrease at most amountInMax
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalanceBefore - usdtBalance).to.be.lt(amountInMax);
  });

  it("swapRC20ExactInput - swap RC20 for RC20", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const wrbtcBalanceBefore = await wrbtcToken.balanceOf(holderAddress);
    const amountIn = pEth(15000) / 10n ** 12n; // USDT has 6 decimals
    const amountOutMin = pEth(0.1);
    await usdtToken.connect(holder).approve(mocSwapperV3.target, amountIn);
    await mocSwapperV3.connect(holder).swapRC20(USDT, WRBTC, amountIn, amountOutMin, holderAddress);
    // Check balances
    // The WRBTC balance must increase at least amountOutMin
    const wrbtcBalance = await wrbtcToken.balanceOf(holderAddress);
    expect(wrbtcBalance - wrbtcBalanceBefore).to.be.gte(amountOutMin);
    // The USDT balance must decrease exactly amountIn
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalanceBefore - usdtBalance).to.be.eq(amountIn);
  });

  it("swapRC20ExactInput - reverts on partial swap", async function () {
    const amountIn = await usdtToken.balanceOf(holderAddress);
    const amountOutMin = pEth(0.1);
    await usdtToken.connect(holder).approve(mocSwapperV3.target, amountIn);
    await expect(
      mocSwapperV3.connect(holder).swapRC20(USDT, WRBTC, amountIn, amountOutMin, holderAddress),
    ).to.be.revertedWithCustomError(mocSwapperV3, "PartialSwap");
  });

  it("swapRC20ExactOutput - swap RC20 for RC20", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const wrbtcBalanceBefore = await wrbtcToken.balanceOf(holderAddress);
    const amountOut = pEth(0.1);
    const amountInMax = pEth(15000) / 10n ** 12n; // USDT has 6 decimals
    await usdtToken.connect(holder).approve(mocSwapperV3.target, amountInMax);
    await mocSwapperV3.connect(holder).swapRC20ExactOutput(USDT, WRBTC, amountOut, amountInMax, holderAddress);
    // Check balances
    // The WRBTC balance must increase exactly amountOut
    const wrbtcBalance = await wrbtcToken.balanceOf(holderAddress);
    expect(wrbtcBalance - wrbtcBalanceBefore).to.be.eq(amountOut);
    // The USDT balance must decrease at most amountInMax
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalanceBefore - usdtBalance).to.be.lt(amountInMax);
  });

  it("swapCoinbaseExactInput - swap Coinbase for RC20", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const rbtcBalanceBefore = await ethers.provider.getBalance(holderAddress);
    const amountIn = pEth(0.1);
    const amountOutMin = pEth(10000) / 10n ** 12n; // USDT has 6 decimals
    await mocSwapperV3.connect(holder).swapCoinbase(USDT, amountOutMin, holderAddress, {
      value: amountIn,
    });
    // Check balances
    // The USDT balance must increase at least amountOutMin
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalance - usdtBalanceBefore).to.be.gte(amountOutMin);
    // The RBTC balance must decrease exactly amountIn
    const rbtcBalance = await ethers.provider.getBalance(holderAddress);
    expect(rbtcBalanceBefore - rbtcBalance).to.be.eq(amountIn);
  });

  it("swapCoinbaseExactOutput - swap Coinbase for RC20", async function () {
    const usdtBalanceBefore = await usdtToken.balanceOf(holderAddress);
    const rbtcBalanceBefore = await ethers.provider.getBalance(holderAddress);
    const amountOut = pEth(10000) / 10n ** 12n; // USDT has 6 decimals
    const amountInMax = pEth(0.1);
    await mocSwapperV3.connect(holder).swapCoinbaseExactOutput(USDT, amountOut, holderAddress, {
      value: amountInMax,
    });
    // Check balances
    // The USDT balance must increase exactly amountOut
    const usdtBalance = await usdtToken.balanceOf(holderAddress);
    expect(usdtBalance - usdtBalanceBefore).to.be.eq(amountOut);
    // The RBTC balance must decrease at most amountInMax
    const rbtcBalance = await ethers.provider.getBalance(holderAddress);
    expect(rbtcBalanceBefore - rbtcBalance).to.be.lt(amountInMax);
  });
});
