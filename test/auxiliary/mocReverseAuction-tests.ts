import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { Address } from "hardhat-deploy/types";
import {
  ERC20Mock,
  ERC20Mock__factory,
  GovernorMock,
  GovernorMock__factory,
  MocReverseAuction,
  MocReverseAuction__factory,
  MocSwapperMock,
  MocSwapperMock__factory,
  PriceProviderMock,
  PriceProviderMock__factory,
} from "../../typechain";
import { pEth } from "../helpers/utils";

describe("Feature: MocReverseAuction", () => {
  let governorMock: GovernorMock;
  let swapperMock: MocSwapperMock;
  let priceProviderMock: PriceProviderMock;
  let tokenIn: ERC20Mock;
  let tokenOut: ERC20Mock;
  let mocReverseAuction: MocReverseAuction;
  let deployer: Address;

  const orderThreshold = pEth(1);

  beforeEach(async () => {
    ({ deployer } = await getNamedAccounts());
    const signer = await ethers.getSigner(deployer);

    governorMock = await new GovernorMock__factory(signer).deploy();

    swapperMock = await new MocSwapperMock__factory(signer).deploy();

    priceProviderMock = await new PriceProviderMock__factory(signer).deploy(0);

    tokenIn = await new ERC20Mock__factory(signer).deploy();
    tokenOut = await new ERC20Mock__factory(signer).deploy();

    mocReverseAuction = await new MocReverseAuction__factory(signer).deploy(
      governorMock.target,
      swapperMock.target,
      tokenIn.target,
      tokenOut.target,
      deployer,
      orderThreshold,
      priceProviderMock.target,
      pEth("0.1"),
    );
  });

  describe("GIVEN the price provider is stale", () => {
    beforeEach(async () => {
      await tokenIn.mint(mocReverseAuction.target, pEth(2));
      await priceProviderMock.deprecatePriceProvider();
    });

    it("THEN readyToTriggerOrders is true", async () => {
      expect(await mocReverseAuction.readyToTriggerOrders()).to.be.equal(true);
    });

    it("THEN triggerOrders uses stale pricing", async () => {
      const tx = await mocReverseAuction.triggerOrders();
      await tx.wait();
    });
  });

  describe("GIVEN amountOutMin is calculated", () => {
    beforeEach(async () => {
      await tokenIn.mint(mocReverseAuction.target, pEth(2));
    });

    it("THEN with price 10 and 10% slippage amountOutMin is 18", async () => {
      await priceProviderMock.poke(pEth(10));
      const [, amountOutMin] = await mocReverseAuction.getAmountOutMin();
      expect(amountOutMin).to.be.equal(pEth(18));
    });

    it("THEN with price 0.5 and 10% slippage amountOutMin is 0.9", async () => {
      await priceProviderMock.poke(pEth("0.5"));
      const [, amountOutMin] = await mocReverseAuction.getAmountOutMin();
      expect(amountOutMin).to.be.equal(pEth("0.9"));
    });
  });
});
