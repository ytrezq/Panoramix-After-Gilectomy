import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { Address } from "hardhat-deploy/types";
import { CommissionSplitterCoinbase, CommissionSplitterRC20, ERC20Mock } from "../../typechain";
import { Balance, deployCommissionSplitter, ethersGetBalance, ethersSendValue, pEth } from "../helpers/utils";

describe("Feature: Commission Splitter", () => {
  let acToken: ERC20Mock;
  let feeToken: ERC20Mock;
  let commissionSplitter: CommissionSplitterRC20 | CommissionSplitterCoinbase;
  let alice: Address, bob: Address, deployer: Address;
  describe("GIVEN there is a RC20 CommissionSplitter", () => {
    before(async () => {
      ({ alice, bob, deployer } = await getNamedAccounts());
      const signer = await ethers.getSigner(deployer);

      const rc20MockFactory = await ethers.getContractFactory("ERC20Mock", signer);
      acToken = await rc20MockFactory.deploy();
      feeToken = await rc20MockFactory.deploy();

      // Governor is not relevant for this tests
      const governorAddress = deployer;
      const initParams = {
        acToken: await acToken.getAddress(),
        governorAddress,
        feeToken: await feeToken.getAddress(),
        acTokenAddressRecipient1: alice,
        acTokenAddressRecipient2: bob,
        acTokenPctToRecipient1: pEth("0.6"), // 60%
        feeTokenAddressRecipient1: alice,
        feeTokenAddressRecipient2: bob,
        feeTokenPctToRecipient1: pEth("0.3"), // 30%
      };
      commissionSplitter = await deployCommissionSplitter(initParams);
    });
    describe("WHEN AC Tokens funds are transfer to it and splitted", () => {
      before(async () => {
        const commSplitterAddress = await commissionSplitter.getAddress();
        await acToken.mint(deployer, pEth(1000));
        await acToken.transfer(commSplitterAddress, pEth(100));
        await feeToken.mint(deployer, pEth(10000));
        await feeToken.transfer(commSplitterAddress, pEth(1000));
        await commissionSplitter.split();
        await acToken.transfer(commSplitterAddress, pEth(200));
        await feeToken.transfer(commSplitterAddress, pEth(100));
        await commissionSplitter.split();
      });
      it("THEN recipients gets their corresponding AC share", async () => {
        expect(await acToken.balanceOf(alice)).to.be.equal(pEth(180));
        expect(await acToken.balanceOf(bob)).to.be.equal(pEth(120));
      });
      it("THEN recipients gets their corresponding Fee Token share", async () => {
        expect(await feeToken.balanceOf(alice)).to.be.equal(pEth(330));
        expect(await feeToken.balanceOf(bob)).to.be.equal(pEth(770));
      });
      it("THEN reverts when CommissionSplitter receives coinbase", async () => {
        await expect(ethersSendValue(deployer, await commissionSplitter.getAddress(), pEth(10))).to.be.reverted;
      });
    });
  });
  describe("GIVEN there is a Coinbase CommissionSplitter", () => {
    let aliceBalanceBefore: Balance;
    let bobBalanceBefore: Balance;
    before(async () => {
      ({ alice, bob, deployer } = await getNamedAccounts());
      const signer = await ethers.getSigner(deployer);

      const rc20MockFactory = await ethers.getContractFactory("ERC20Mock", signer);
      feeToken = await rc20MockFactory.deploy();

      // Governor is not relevant for this tests
      const governorAddress = deployer;
      const initParams = {
        governorAddress,
        feeToken: await feeToken.getAddress(),
        acTokenAddressRecipient1: alice,
        acTokenAddressRecipient2: bob,
        acTokenPctToRecipient1: pEth("0.6"), // 60%
        feeTokenAddressRecipient1: alice,
        feeTokenAddressRecipient2: bob,
        feeTokenPctToRecipient1: pEth("0.3"), // 30%
      };
      commissionSplitter = await deployCommissionSplitter(initParams);

      aliceBalanceBefore = await ethersGetBalance(alice);
      bobBalanceBefore = await ethersGetBalance(bob);
    });
    describe("WHEN AC Tokens funds are transfer to it and splitted", () => {
      before(async () => {
        const commSplitterAddress = await commissionSplitter.getAddress();
        await ethersSendValue(deployer, commSplitterAddress, pEth(100));
        await feeToken.mint(deployer, pEth(10000));
        await feeToken.transfer(commSplitterAddress, pEth(1000));
        await commissionSplitter.split();
        await ethersSendValue(deployer, commSplitterAddress, pEth(200));
        await feeToken.transfer(commSplitterAddress, pEth(100));
        await commissionSplitter.split();
      });
      it("THEN recipients gets their corresponding AC share", async () => {
        expect((await ethersGetBalance(alice)) - aliceBalanceBefore).to.be.equal(pEth(180));
        expect((await ethersGetBalance(bob)) - bobBalanceBefore).to.be.equal(pEth(120));
      });
      it("THEN recipients gets their corresponding Fee Token share", async () => {
        expect(await feeToken.balanceOf(alice)).to.be.equal(pEth(330));
        expect(await feeToken.balanceOf(bob)).to.be.equal(pEth(770));
      });
    });
  });
});
