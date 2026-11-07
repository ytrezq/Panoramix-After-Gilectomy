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

timedDescribe("Feature: multicollateral swap Pegged Token for Collateral Token", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let alicePrevACBalance = new Array<Balance>(3);
  let feeFlowPrevACBalance = new Array<Balance>(3);
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
      execCostParams: { swapTPforTCExecCost },
    },
  } = getNetworkDeployParams(hre);

  describe("GIVEN 3 Moc implementations deployed with TCs and TPs minted to alice and charlie", function () {
    before(async function () {
      ({ alice, bob, charlie, vendor } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixtureCase1);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, feeToken, mocMultiCollateralGuard } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });

      // add TCs to alice and charlie
      await Promise.all([
        ...mocFunctions.map(fncs => fncs.mintTC({ from: alice, qTC: 100000, execute: false })),
        ...mocFunctions.map(fncs => fncs.mintTC({ from: charlie, qTC: 100000, execute: false })),
      ]);

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
      feeFlowPrevACBalance = await Promise.all(
        mocFunctions.map(mocFunction => mocFunction.acBalanceOf(mocFeeFlowAddress)),
      );

      enqueueOperations = async () => {
        await Promise.all([
          mocFunctions[0].swapTPforTC({ tp: tps[0], from: alice, qTP: 2350, execute: false }), // 10 AC0
          mocFunctions[1].swapTPforTC({ tp: tps[1], from: alice, to: bob, qTP: 52.5, execute: false }), // 20 AC1
          mocFunctions[2].swapTPforTC({ tp: tps[2], from: alice, qTP: 9345.8, vendor, execute: false }), // 30 AC2
          mocFunctions[0].swapTPforTC({ tp: tps[1], from: charlie, qTP: 52.5, execute: false }), // 10 AC0
          mocFunctions[1].swapTPforTC({ tp: tps[0], from: charlie, to: bob, qTP: 2350, execute: false }), // 20 AC1
          mocFunctions[2].swapTPforTC({ tp: tps[0], from: charlie, qTP: 2350, vendor, execute: false }), // 30 AC2
        ]);
      };
    });
    describe("AND alice enqueue: a swapTPforTC 2350 TP0 (10 AC0) operation on bucket 0", function () {
      describe("AND enqueue: a swapTPforTC 52.5 TP1 (20 AC1) operation to bob on bucket 1", function () {
        describe("AND enqueue: a swapTPforTC 9345.8 TP2 (30 AC2) operation via vendor on bucket 2", function () {
          describe("AND charlie enqueue: a swapTPforTC 52.5 TP1 (10 AC0) operation on bucket 0 having Fee Tokens", function () {
            describe("AND enqueue: a swapTPforTC 2350 TP0 (20 AC1) operation to bob on bucket 1 having Fee Tokens", function () {
              describe("AND enqueue: a swapTPforTC 2350 TP0 (30 AC2) operation via vendor on bucket 2 having Fee Tokens", function () {
                before(async function () {
                  await enqueueOperations();
                });
                describe("AND queue is executed", function () {
                  // execution fee are paid on Coinbase that is configured as Collateral on bucket 1
                  const executionFeeOnAC1 = swapTPforTCExecCost * 3n;
                  before(async function () {
                    executionTx = await mocFunctions[0].executeQueue();
                  });
                  it("THEN alice redeems 2350 TP0, 52.5 TP1 and 9345.8 TP2", async function () {
                    assertPrec(21150, await tps[0].balanceOf(alice));
                    assertPrec(472.5, await tps[1].balanceOf(alice));
                    assertPrec(84112.2, await tps[2].balanceOf(alice));
                  });
                  it("THEN charlie redeems 4700 TP0 and 5.25 TP1", async function () {
                    assertPrec(42300, await tps[0].balanceOf(charlie));
                    assertPrec(472.5, await tps[1].balanceOf(charlie));
                  });
                  it("THEN alice mints 10 TC0 and 30 TC2", async function () {
                    assertPrec(100010, await mocFunctions[0].tcBalanceOf(alice));
                    assertPrec(100030, await mocFunctions[2].tcBalanceOf(alice));
                  });
                  it("THEN bob mints 40 TC1", async function () {
                    assertPrec(40, await mocFunctions[1].tcBalanceOf(bob));
                  });
                  it("THEN charlie mints 10 TC0 and 30 TC2", async function () {
                    assertPrec(100010, await mocFunctions[0].tcBalanceOf(charlie));
                    assertPrec(100030, await mocFunctions[2].tcBalanceOf(charlie));
                  });
                  it("THEN Moc Fee Flow balance increase 0.1 AC0 (1% qACFee)", async function () {
                    const diff = (await mocFunctions[0].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[0];
                    assertPrec(0.1, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 0.2 AC1 (2% qACFee)", async function () {
                    const diff = (await mocFunctions[1].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[1];
                    assertPrec(0.2, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 0.3 AC2 (1% qACFee)", async function () {
                    const diff = (await mocFunctions[2].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[2];
                    assertPrec(0.3, diff);
                  });
                  it("THEN alice balance decrease 0.1 AC0 (1% qACFee)", async function () {
                    const aliceActualACBalance = await mocFunctions[0].acBalanceOf(alice);
                    const diff = alicePrevACBalance[0] - aliceActualACBalance;
                    assertPrec(0.1, diff);
                  });
                  it("THEN alice balance decrease 0.2 AC1 (1% qACFee)", async function () {
                    const aliceActualACBalance = await mocFunctions[1].acBalanceOf(alice);
                    const diff = alicePrevACBalance[1] - aliceActualACBalance - executionFeeOnAC1;
                    assertPrec(0.2, diff);
                  });
                  it("THEN alice balance decrease 3.3 AC2 (1% qACFee + 10% qACVendorMarkup)", async function () {
                    const aliceActualACBalance = await mocFunctions[2].acBalanceOf(alice);
                    const diff = alicePrevACBalance[2] - aliceActualACBalance;
                    assertPrec(3.3, diff);
                  });
                  it("THEN Moc Fee Flow Fee Token balance increase 0.3 ((10 + 20 + 30) * 1%) * 50%)", async function () {
                    // 0.05 => 100 AC0 * 0.01 swapTPforTCFee * 0.5
                    // 0.1 => 200 AC1 * 0.01 swapTPforTCFee * 0.5
                    // 0.15 => 300 AC2 * 0.01 swapTPforTCFee * 0.5
                    const mocFeeFlowActualFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
                    assertPrec(0.3, mocFeeFlowActualFeeTokenBalance);
                  });
                  it("THEN a TPSwappedForTC event is emitted by bucket 0 queue", async function () {
                    // i: 0
                    // sender: alice
                    // receiver: alice
                    // qTP: 2350 TP
                    // qTC: 10 TC
                    // qACfee: %1 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      alice,
                      alice,
                      pEth(2350),
                      pEth(10),
                      pEth(0.1),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TPSwappedForTC")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPSwappedForTC event is emitted by bucket 1 queue", async function () {
                    // i: 1
                    // sender: alice
                    // receiver: bob
                    // qTP: 52.5 TP
                    // qTC: 20 TC
                    // qACfee: %1 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      alice,
                      bob,
                      pEth(52.5),
                      pEth(20),
                      pEth(0.2),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TPSwappedForTC")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPSwappedForTC event is emitted by bucket 2 queue", async function () {
                    // i: 2
                    // sender: alice
                    // receiver: alice
                    // qTP: 9345.8 TP
                    // qTC: 30 TC
                    // qACfee: %1 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 10% qAC
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[2].target.toString(),
                      alice,
                      alice,
                      pEth(9345.8),
                      pEth(30),
                      pEth(0.3),
                      0,
                      pEth(3),
                      0,
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TPSwappedForTC")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPSwappedForTC event using Fee Token is emitted by bucket 0 queue", async function () {
                    // i: 1
                    // sender: charlie
                    // receiver: charlie
                    // qTP: 52.5 TP
                    // qTC: 10 TC
                    // qACfee: 0
                    // qFeeToken: 10 (0.1% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      charlie,
                      charlie,
                      pEth(52.5),
                      pEth(10),
                      0,
                      pEth(0.05),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TPSwappedForTC")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPSwappedForTC event using Fee Token is emitted by bucket 1 queue", async function () {
                    // i: 0
                    // sender: charlie
                    // receiver: bob
                    // qTP: 2350 TP
                    // qTC: 20 TC
                    // qACfee: 0
                    // qFeeToken: 20 (0.1% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      bob,
                      pEth(2350),
                      pEth(20),
                      0,
                      pEth(0.1),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TPSwappedForTC")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPSwappedForTC event using Fee Token is emitted by bucket 2 queue", async function () {
                    // i: 0
                    // sender: charlie
                    // receiver: charlie
                    // qTP: 2350 TP
                    // qTC: 30 TC
                    // qACfee: 0
                    // qFeeToken: 30 (0.1% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 30 * 10%
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      charlie,
                      pEth(2350),
                      pEth(30),
                      0,
                      pEth(0.15),
                      0,
                      pEth(3),
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TPSwappedForTC")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN combined coverage is 680.12", async function () {
                    assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "680.123456790123456892");
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
