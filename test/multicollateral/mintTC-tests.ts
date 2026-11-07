import { expect } from "chai";
import hre, { getNamedAccounts, ethers } from "hardhat";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../helpers/assertHelper";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { Balance, CONSTANTS, getNetworkDeployParams, pEth, timedDescribe } from "../helpers/utils";
import { ERC20Mock } from "../../typechain";
import { fixtureCase1 } from "./fixture";

timedDescribe("Feature: multicollateral mint Collateral Tokens", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let alicePrevACBalance = new Array<Balance>(3);
  let executionTx: ContractTransactionResponse;
  let feeToken: ERC20Mock;
  let alice: Address;
  let bob: Address;
  let charlie: Address;
  let vendor: Address;
  let enqueueOperations: any;
  const noVendor = CONSTANTS.ZERO_ADDRESS;
  const {
    mocAddresses: { mocFeeFlowAddress },
    queueParams: {
      execCostParams: { tcMintExecCost },
    },
  } = getNetworkDeployParams(hre);

  describe("GIVEN 3 Moc implementations deployed with 3 TPs added on every buckets", function () {
    before(async function () {
      ({ alice, bob, charlie, vendor } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixtureCase1);
      ({ mocBucketContracts: buckets, feeToken } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });
      alicePrevACBalance = await Promise.all(mocFunctions.map(mocFunction => mocFunction.acBalanceOf(alice)));

      const charlieSigner = await ethers.getSigner(charlie);
      // mint FeeToken to charlie
      await Promise.all([
        feeToken.mint(charlie, pEth(10000)),
        ...buckets.map(bucket =>
          feeToken.connect(charlieSigner).approve(bucket.mocImpl.target.toString(), pEth(10000)),
        ),
      ]);

      enqueueOperations = async () => {
        await Promise.all([
          mocFunctions[0].mintTC({ from: alice, qTC: 100, execute: false }),
          mocFunctions[1].mintTC({ from: alice, to: bob, qTC: 200, execute: false }),
          mocFunctions[2].mintTC({ from: alice, qTC: 300, vendor, execute: false }),
          mocFunctions[0].mintTC({ from: charlie, qTC: 100, execute: false }),
          mocFunctions[1].mintTC({ from: charlie, to: bob, qTC: 200, execute: false }),
          mocFunctions[2].mintTC({ from: charlie, qTC: 300, vendor, execute: false }),
        ]);
      };
    });
    describe("WHEN alice enqueue: a mint 100 TC operation on bucket 0", function () {
      describe("AND enqueue: a mint 200 TC operation to bob on bucket 1", function () {
        describe("AND enqueue: a mint 300 TC operation via vendor on bucket 2", function () {
          describe("AND charlie enqueue the same operations but having Fee Tokens", function () {
            before(async function () {
              await enqueueOperations();
            });
            describe("AND queue is executed", function () {
              // execution fee are paid on Coinbase that is configured as Collateral on bucket 1
              const executionFeeOnAC1 = tcMintExecCost * 3n;
              before(async function () {
                executionTx = await mocFunctions[0].executeQueue();
              });
              it("THEN alice receives 100 TC0", async function () {
                assertPrec(100, await mocFunctions[0].tcBalanceOf(alice));
              });
              it("THEN bob receives 400 TC1", async function () {
                assertPrec(400, await mocFunctions[1].tcBalanceOf(bob));
              });
              it("THEN alice receives 300 TC2", async function () {
                assertPrec(300, await mocFunctions[2].tcBalanceOf(alice));
              });
              it("THEN bucket 0 balance increase 200 AC0", async function () {
                assertPrec(200, await mocFunctions[0].acBalanceOf(buckets[0].mocImpl.target.toString()));
              });
              it("THEN bucket 1 balance increase 400 AC1", async function () {
                assertPrec(400, await mocFunctions[1].acBalanceOf(buckets[1].mocImpl.target.toString()));
              });
              it("THEN bucket 2 balance increase 600 AC2", async function () {
                assertPrec(600, await mocFunctions[2].acBalanceOf(buckets[2].mocImpl.target.toString()));
              });
              it("THEN Moc Fee Flow balance increase 5 AC0 (5% qACFee)", async function () {
                assertPrec(5, await mocFunctions[0].acBalanceOf(mocFeeFlowAddress));
              });
              it("THEN Moc Fee Flow balance increase 10 AC1 (5% qACFee)", async function () {
                assertPrec(10, await mocFunctions[1].acBalanceOf(mocFeeFlowAddress));
              });
              it("THEN Moc Fee Flow balance increase 15 AC2 (5% qACFee)", async function () {
                assertPrec(15, await mocFunctions[2].acBalanceOf(mocFeeFlowAddress));
              });
              it("THEN alice balance decrease 105 AC0 (100 qAC + 5% qACFee)", async function () {
                const aliceActualACBalance = await mocFunctions[0].acBalanceOf(alice);
                const diff = alicePrevACBalance[0] - aliceActualACBalance;
                assertPrec(105, diff);
              });
              it("THEN alice balance decrease 210 AC1 (200 qAC + 5% qACFee)", async function () {
                const aliceActualACBalance = await mocFunctions[1].acBalanceOf(alice);
                const diff = alicePrevACBalance[1] - aliceActualACBalance - executionFeeOnAC1;
                assertPrec(210, diff);
              });
              it("THEN alice AC balance decrease 345 AC 2 (200 qAC + 5% qACFee + 10% qACVendorMarkup)", async function () {
                const aliceActualACBalance = await mocFunctions[2].acBalanceOf(alice);
                const diff = alicePrevACBalance[2] - aliceActualACBalance;
                assertPrec(345, diff);
              });
              it("THEN Moc Fee Flow Fee Token balance increase 15 ((100 + 200 + 300) * 5% * 50%)", async function () {
                const mocFeeFlowActualFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
                assertPrec(15, mocFeeFlowActualFeeTokenBalance);
              });
              it("THEN a TCMinted event is emitted by bucket 0 queue", async function () {
                // sender: alice
                // receiver: alice
                // qTC: 100 TC
                // qAC: 100 AC + 5% for Moc Fee Flow
                // qACfee: %5 AC
                // qFeeToken: 0
                // qACVendorMarkup: 0
                // qFeeTokenVendorMarkup: 0
                const args = [alice, alice, pEth(100), pEth(100 * 1.05), pEth(100 * 0.05), 0, 0, 0, noVendor];
                await expect(executionTx)
                  .to.emit(buckets[0].mocQueue, "TCMinted")
                  .withArgs(...args, anyValue); // operID is not relevant here
              });
              it("THEN a TCMinted event is emitted by bucket 1 queue", async function () {
                // sender: alice
                // receiver: bob
                // qTC: 200 TC
                // qAC: 200 AC + 5% for Moc Fee Flow
                // qACfee: %5 AC
                // qFeeToken: 0
                // qACVendorMarkup: 0
                // qFeeTokenVendorMarkup: 0
                const args = [alice, bob, pEth(200), pEth(200 * 1.05), pEth(200 * 0.05), 0, 0, 0, noVendor];
                await expect(executionTx)
                  .to.emit(buckets[1].mocQueue, "TCMinted")
                  .withArgs(...args, anyValue); // operID is not relevant here
              });
              it("THEN a TCMinted event is emitted by bucket 2 queue", async function () {
                // sender: alice
                // receiver: alice
                // qTC: 300 TC
                // qAC: 300 AC + 5% for Moc Fee Flow + 10% for vendor
                // qACfee: 5% qAC
                // qFeeToken: 0
                // qACVendorMarkup: 10% qAC
                // qFeeTokenVendorMarkup: 0
                const args = [
                  alice,
                  alice,
                  pEth(300),
                  pEth(300 * 1.15),
                  pEth(300 * 0.05),
                  0,
                  pEth(300 * 0.1),
                  0,
                  vendor,
                ];
                await expect(executionTx)
                  .to.emit(buckets[2].mocQueue, "TCMinted")
                  .withArgs(...args, anyValue); // operID is not relevant here
              });
              it("THEN a TCMinted event using Fee Token is emitted by bucket 0 queue", async function () {
                // sender: charlie
                // receiver: charlie
                // qTC: 100 TC
                // qAC: 100 AC
                // qACfee: 0
                // qFeeToken: 100 (5% * 50%)
                // qACVendorMarkup: 0
                // qFeeTokenVendorMarkup: 0
                const args = [charlie, charlie, pEth(100), pEth(100), 0, pEth(100 * 0.05 * 0.5), 0, 0, noVendor];
                await expect(executionTx)
                  .to.emit(buckets[0].mocQueue, "TCMinted")
                  .withArgs(...args, anyValue); // operID is not relevant here
              });
              it("THEN a TCMinted event using Fee Token is emitted by bucket 1 queue", async function () {
                // sender: charlie
                // receiver: bob
                // qTC: 200 TC
                // qAC: 200 AC
                // qACfee: 0
                // qFeeToken: 200 (5% * 50%)
                // qACVendorMarkup: 0
                // qFeeTokenVendorMarkup: 0
                const args = [charlie, bob, pEth(200), pEth(200), 0, pEth(200 * 0.05 * 0.5), 0, 0, noVendor];
                await expect(executionTx)
                  .to.emit(buckets[1].mocQueue, "TCMinted")
                  .withArgs(...args, anyValue); // operID is not relevant here
              });
              it("THEN a TCMinted event using Fee Token is emitted by bucket 2 queue", async function () {
                // sender: charlie
                // receiver: charlie
                // qTC: 300 TC
                // qAC: 300 AC
                // qACfee: 0
                // qFeeToken: 300 (5% * 50%)
                // qACVendorMarkup: 0
                // qFeeTokenVendorMarkup: 300 * 10%
                const args = [
                  charlie,
                  charlie,
                  pEth(300),
                  pEth(300),
                  0,
                  pEth(300 * 0.05 * 0.5),
                  0,
                  pEth(300 * 0.1),
                  vendor,
                ];
                await expect(executionTx)
                  .to.emit(buckets[2].mocQueue, "TCMinted")
                  .withArgs(...args, anyValue); // operID is not relevant here
              });
            });
          });
        });
      });
    });
  });
});
