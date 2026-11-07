import { expect } from "chai";
import hre, { getNamedAccounts, ethers } from "hardhat";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { assertPrec } from "../helpers/assertHelper";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { Balance, CONSTANTS, getNetworkDeployParams, pEth, timedDescribe } from "../helpers/utils";
import { ERC20Mock, MocMultiCollateralGuard } from "../../typechain";
import { fixtureCase1 } from "./fixture";

timedDescribe("Feature: multicollateral redeem Pegged Tokens", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let alicePrevACBalance = new Array<Balance>(3);
  let bucketPrevACBalance = new Array<Balance>(3);
  let feeFlowPrevACBalance = new Array<Balance>(3);
  let bobPrevAC1Balance: Balance;
  let executionTx: ContractTransactionResponse;
  let feeToken: ERC20Mock;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let alice: Address;
  let bob: Address;
  let charlie: Address;
  let vendor: Address;
  let enqueueOperations: any;
  const noVendor = CONSTANTS.ZERO_ADDRESS;
  const {
    mocAddresses: { mocFeeFlowAddress },
    queueParams: {
      execCostParams: { tpRedeemExecCost },
    },
  } = getNetworkDeployParams(hre);

  describe("GIVEN 3 Moc implementations deployed with TPs minted to alice and charlie", function () {
    before(async function () {
      ({ alice, bob, charlie, vendor } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixtureCase1);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, feeToken, mocMultiCollateralGuard } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });

      // add collateral to every buckets
      await Promise.all(mocFunctions.map(fncs => fncs.mintTC({ from: alice, qTC: 100000, execute: false })));

      // add TPs to alice and charlie
      await Promise.all([
        mocFunctions[0].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500, execute: false }), // 100 AC0
        mocFunctions[1].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 525, execute: false }), // 200 AC1
        mocFunctions[2].mintTP({ tp: tps[2].target.toString(), from: alice, qTP: 93458, execute: false }), // 300 AC2
        mocFunctions[0].mintTP({ tp: tps[1].target.toString(), from: charlie, qTP: 525, execute: false }), // 100 AC0
        mocFunctions[1].mintTP({ tp: tps[0].target.toString(), from: charlie, qTP: 23500, execute: false }), // 200 AC1
        mocFunctions[2].mintTP({ tp: tps[0].target.toString(), from: charlie, qTP: 23500, execute: false }), // 300 AC2
      ]);
      await mocFunctions[0].executeQueue();

      const charlieSigner = await ethers.getSigner(charlie);
      // mint FeeToken to charlie
      await Promise.all([
        feeToken.mint(charlie, pEth(10000)),
        ...buckets.map(bucket =>
          feeToken.connect(charlieSigner).approve(bucket.mocImpl.target.toString(), pEth(10000)),
        ),
      ]);

      alicePrevACBalance = await Promise.all(mocFunctions.map(mocFunction => mocFunction.acBalanceOf(alice)));
      bucketPrevACBalance = await Promise.all(
        buckets.map((bucket, index) => mocFunctions[index].acBalanceOf(bucket.mocImpl.target.toString())),
      );
      feeFlowPrevACBalance = await Promise.all(
        mocFunctions.map(mocFunction => mocFunction.acBalanceOf(mocFeeFlowAddress)),
      );
      bobPrevAC1Balance = await mocFunctions[1].acBalanceOf(bob);
      // cases:
      // 1. TP0 is on all the buckets
      // 2. TP1 is missing on bucket2
      // 3. TP2 is only on bucket2
      enqueueOperations = async () => {
        await Promise.all([
          mocFunctions[0].redeemTP({ tp: tps[0], from: alice, qTP: 2350, execute: false }), // 10 AC0
          mocFunctions[1].redeemTP({ tp: tps[1], from: alice, to: bob, qTP: 52.5, execute: false }), // 20 AC1
          mocFunctions[2].redeemTP({ tp: tps[2], from: alice, qTP: 9345.8, vendor, execute: false }), // 30 AC2
          mocFunctions[0].redeemTP({ tp: tps[1], from: charlie, qTP: 52.5, execute: false }), // 10 AC0
          mocFunctions[1].redeemTP({ tp: tps[0], from: charlie, to: bob, qTP: 2350, execute: false }), // 20 AC1
          mocFunctions[2].redeemTP({ tp: tps[0], from: charlie, qTP: 2350, vendor, execute: false }), // 30 AC2
        ]);
      };
    });
    describe("AND alice enqueue: a redeem 2350 TP0 (10 AC0) operation on bucket 0", function () {
      describe("AND enqueue: a redeem 52.5 TP1 (20 AC1) operation to bob on bucket 1", function () {
        describe("AND enqueue: a redeem 9345.8 TP2 (30 AC1) operation via vendor on bucket 2", function () {
          describe("AND charlie enqueue: a redeem 52.5 TP1 (10 AC0) operation on bucket 0 having Fee Tokens", function () {
            describe("AND enqueue: a redeem 2350 TP0 (20 AC0) operation to bob on bucket 1 having Fee Tokens", function () {
              describe("AND enqueue: a redeem 2350 TP0 (30 AC0) operation via vendor on bucket 2 having Fee Tokens", function () {
                before(async function () {
                  await enqueueOperations();
                });
                describe("AND queue is executed", function () {
                  // execution fee are paid on Coinbase that is configured as Collateral on bucket 1
                  const executionFeeOnAC1 = tpRedeemExecCost * 3n;
                  before(async function () {
                    executionTx = await mocFunctions[0].executeQueue();
                  });
                  it("THEN alice has 21150 TP0, 472.5 TP1 and 84112.2 TP2", async function () {
                    assertPrec(21150, await tps[0].balanceOf(alice));
                    assertPrec(472.5, await tps[1].balanceOf(alice));
                    assertPrec(84112.2, await tps[2].balanceOf(alice));
                  });
                  it("THEN charlie has 42300 TP0 and 472.5 TP1", async function () {
                    assertPrec(42300, await tps[0].balanceOf(charlie));
                    assertPrec(472.5, await tps[1].balanceOf(charlie));
                  });
                  it("THEN bucket 0 balance decrease 20 AC0", async function () {
                    const bucket0Address = buckets[0].mocImpl.target.toString();
                    const diff = bucketPrevACBalance[0] - (await mocFunctions[0].acBalanceOf(bucket0Address));
                    // 2350 alice TP0 redeem => 10 AC0
                    // 52.5 charlie TP1 redeem => 10 AC0
                    assertPrec(20, diff);
                  });
                  it("THEN bucket 1 balance decrease 40 AC1", async function () {
                    const bucket1Address = buckets[1].mocImpl.target.toString();
                    const diff = bucketPrevACBalance[1] - (await mocFunctions[1].acBalanceOf(bucket1Address));
                    // 52.5 alice TP1 redeem => 20 AC1
                    // 2350 charlie TP0 redeem => 20 AC1
                    assertPrec(40, diff);
                  });
                  it("THEN bucket 2 balance decrease 60 AC2", async function () {
                    const bucket2Address = buckets[2].mocImpl.target.toString();
                    const diff = bucketPrevACBalance[2] - (await mocFunctions[2].acBalanceOf(bucket2Address));
                    // 9345.8 alice TP2 mint => 30 AC2
                    // 2350 charlie TP0 mint => 30 AC2
                    assertPrec(60, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 0.5 AC0 (5% qACFee TP0)", async function () {
                    const diff = (await mocFunctions[0].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[0];
                    assertPrec(0.5, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 1 AC1 (5% qACFee TP1)", async function () {
                    const diff = (await mocFunctions[1].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[1];
                    assertPrec(1, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 1.5 AC2 (5% qACFee TP2)", async function () {
                    const diff = (await mocFunctions[2].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[2];
                    assertPrec(1.5, diff);
                  });
                  it("THEN alice balance increase 9.5 AC0 (10 qAC - 5% qACFee TP0)", async function () {
                    const aliceActualACBalance = await mocFunctions[0].acBalanceOf(alice);
                    const diff = aliceActualACBalance - alicePrevACBalance[0];
                    assertPrec(9.5, diff);
                  });
                  it("THEN alice balance decrease the redeem execution fee on AC1, redeemed AC1 went to bob", async function () {
                    const aliceActualACBalance = await mocFunctions[1].acBalanceOf(alice);
                    const diff = alicePrevACBalance[1] - aliceActualACBalance;
                    assertPrec(executionFeeOnAC1, diff);
                  });
                  it("THEN alice balance increase 25.5 AC2 (30 qAC - 5% qACFee TP2 - 10% qACVendorMarkup)", async function () {
                    const aliceActualACBalance = await mocFunctions[2].acBalanceOf(alice);
                    const diff = aliceActualACBalance - alicePrevACBalance[2];
                    assertPrec(25.5, diff);
                  });
                  it("THEN bob balance increase 39 AC1 (20 qAC - 5% qACFee TP1 + 20 qAC)", async function () {
                    const bobActualACBalance = await mocFunctions[1].acBalanceOf(bob);
                    const diff = bobActualACBalance - bobPrevAC1Balance;
                    assertPrec(39, diff);
                  });
                  it("THEN Moc Fee Flow Fee Token balance increase 1.5 ((10 + 20 + 30) * 5%) * 50%)", async function () {
                    // 0.25 => 10 AC0 * 0.05 TP1 redeemFee * 0.5
                    // 0.5 => 20 AC1 * 0.05 TP0 redeemFee * 0.5
                    // 0.75 => 30 AC2 * 0.05 TP0 redeemFee * 0.5
                    const mocFeeFlowActualFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
                    assertPrec(1.5, mocFeeFlowActualFeeTokenBalance);
                  });
                  it("THEN a TPRedeemed event is emitted by bucket 0 queue for TP0", async function () {
                    // tp: tp0
                    // sender: alice
                    // receiver: alice
                    // qTP: 2350 TP
                    // qAC: 10 AC - 5% for Moc Fee Flow
                    // qACfee: %5 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      alice,
                      alice,
                      pEth(2350),
                      pEth(9.5),
                      pEth(0.5),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPRedeemed event is emitted by bucket 1 queue for TP1", async function () {
                    // tp: tp1
                    // sender: alice
                    // receiver: bob
                    // qTP: 52.5 TP
                    // qAC: 20 AC - 5% for Moc Fee Flow
                    // qACfee: %5 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      alice,
                      bob,
                      pEth(52.5),
                      pEth(19),
                      pEth(1),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPRedeemed event is emitted by bucket 2 queue for TP2", async function () {
                    // tp: tp2
                    // sender: alice
                    // receiver: alice
                    // qTP: 9345.8 TP
                    // qAC: 30 AC - 5% for Moc Fee Flow - 10% for vendor
                    // qACfee: %5 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 10% qAC
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[2].target.toString(),
                      alice,
                      alice,
                      pEth(9345.8),
                      pEth(25.5),
                      pEth(1.5),
                      0,
                      pEth(3),
                      0,
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPRedeemed event using Fee Token is emitted by bucket 0 queue for TP1", async function () {
                    // tp: tp1
                    // sender: charlie
                    // receiver: charlie
                    // qTP: 52.5 TP
                    // qAC: 10 AC
                    // qACfee: 0
                    // qFeeToken: 10 (0.5% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      charlie,
                      charlie,
                      pEth(52.5),
                      pEth(10),
                      0,
                      pEth(0.25),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPRedeemed event using Fee Token is emitted by bucket 1 queue for TP0", async function () {
                    // tp: tp0
                    // sender: charlie
                    // receiver: bob
                    // qTP: 2350 TP
                    // qAC: 20 AC
                    // qACfee: 0
                    // qFeeToken: 20 (0.5% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      bob,
                      pEth(2350),
                      pEth(20),
                      0,
                      pEth(0.5),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPRedeemed event using Fee Token is emitted by bucket 2 queue for TP0", async function () {
                    // tp: tp0
                    // sender: charlie
                    // receiver: charlie
                    // qTP: 2350 TP
                    // qAC: 30 AC
                    // qACfee: 0
                    // qFeeToken: 30 (0.5% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 30 * 10%
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      charlie,
                      pEth(2350),
                      pEth(30),
                      0,
                      pEth(0.75),
                      0,
                      pEth(3),
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN combined coverage is 340.5", async function () {
                    assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "340.506172839506172890");
                  });
                });
              });
            });
          });
        });
      });
    });
  });
});
