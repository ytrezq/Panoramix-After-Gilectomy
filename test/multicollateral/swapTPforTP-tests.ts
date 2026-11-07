import { expect } from "chai";
import hre, { getNamedAccounts, ethers } from "hardhat";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { assertPrec } from "../helpers/assertHelper";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { Balance, CONSTANTS, ERROR_SELECTOR, getNetworkDeployParams, pEth, timedDescribe } from "../helpers/utils";
import { ERC20Mock, MocMultiCollateralGuard } from "../../typechain";
import { fixtureCase1 } from "./fixture";

timedDescribe("Feature: multicollateral swap Pegged Token for another Pegged Token", function () {
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
      execCostParams: { swapTPforTPExecCost },
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
      const aliceCommonParams = { from: alice, execute: false };
      const charlieCommonParams = { from: charlie, execute: false };
      enqueueOperations = async () => {
        await Promise.all([
          mocFunctions[0].swapTPforTP({ tpFrom: tps[0], tpTo: tps[1], qTP: 2350, ...aliceCommonParams }), // 10 AC0
          mocFunctions[1].swapTPforTP({ tpFrom: tps[1], tpTo: tps[0], to: bob, qTP: 52.5, ...aliceCommonParams }), // 20 AC1
          mocFunctions[2].swapTPforTP({ tpFrom: tps[2], tpTo: tps[0], qTP: 9345.8, vendor, ...aliceCommonParams }), // 30 AC2
          mocFunctions[0].swapTPforTP({ tpFrom: tps[1], tpTo: tps[0], qTP: 52.5, ...charlieCommonParams }), // 10 AC0
          mocFunctions[1].swapTPforTP({ tpFrom: tps[0], tpTo: tps[1], to: bob, qTP: 2350, ...charlieCommonParams }), // 20 AC1
          mocFunctions[2].swapTPforTP({ tpFrom: tps[0], tpTo: tps[2], qTP: 2350, vendor, ...charlieCommonParams }), // 30 AC2
        ]);
      };
    });
    describe("AND alice enqueue: a swapTPforTP 2350 TP0 for TP1 (10 AC0) operation on bucket 0", function () {
      describe("AND enqueue: a swapTPforTP 52.5 TP1 for TP0 (20 AC1) operation to bob on bucket 1", function () {
        describe("AND enqueue: a swapTPforTP 9345.8 TP2 for TP0 (30 AC2) operation via vendor on bucket 2", function () {
          describe("AND charlie enqueue: a swapTPforTP 52.5 TP1 for TP0 (10 AC0) operation on bucket 0 having Fee Tokens", function () {
            describe("AND enqueue: a swapTPforTP 2350 TP0 for TP1 (20 AC1) operation to bob on bucket 1 having Fee Tokens", function () {
              describe("AND enqueue: a swapTPforTP 2350 TP0 for TP2 (30 AC2) operation via vendor on bucket 2 having Fee Tokens", function () {
                before(async function () {
                  await enqueueOperations();
                });
                describe("AND queue is executed", function () {
                  // execution fee are paid on Coinbase that is configured as Collateral on bucket 1
                  const executionFeeOnAC1 = swapTPforTPExecCost * 3n;
                  before(async function () {
                    executionTx = await mocFunctions[0].executeQueue();
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
                    // 0.05 => 100 AC0 * 0.01 swapTPforTPFee * 0.5
                    // 0.1 => 200 AC1 * 0.01 swapTPforTPFee * 0.5
                    // 0.15 => 300 AC2 * 0.01 swapTPforTPFee * 0.5
                    const mocFeeFlowActualFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
                    assertPrec(0.3, mocFeeFlowActualFeeTokenBalance);
                  });
                  it("THEN a TPSwappedForTP event is emitted by bucket 0 queue", async function () {
                    // iFrom: 0
                    // iTo: 1
                    // sender: alice
                    // receiver: alice
                    // qTPFrom: 2350 TP
                    // qTPTo: 52.5 TP
                    // qACfee: %1 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      tps[1].target.toString(),
                      alice,
                      alice,
                      pEth(2350),
                      pEth(52.5),
                      pEth(0.1),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TPSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPSwappedForTP event is emitted by bucket 1 queue", async function () {
                    // iFrom: 1
                    // iTo: 0
                    // sender: alice
                    // receiver: bob
                    // qTPFrom: 52.5 TP
                    // qTPTo: 2350 TP
                    // qACfee: %1 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      tps[0].target.toString(),
                      alice,
                      bob,
                      pEth(52.5),
                      pEth(2350),
                      pEth(0.2),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TPSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPSwappedForTP event is emitted by bucket 2 queue", async function () {
                    // iFrom: 2
                    // iTo: 0
                    // sender: alice
                    // receiver: alice
                    // qTPFrom: 9345.8 TP
                    // qTPTo: 2350 TP
                    // qACfee: %1 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 10% qAC
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[2].target.toString(),
                      tps[0].target.toString(),
                      alice,
                      alice,
                      pEth(9345.8),
                      pEth("2349.999999999999999995"),
                      pEth(0.3),
                      0,
                      pEth(3),
                      0,
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TPSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPSwappedForTP event using Fee Token is emitted by bucket 0 queue", async function () {
                    // iFrom: 1
                    // iTo: 0
                    // sender: charlie
                    // receiver: charlie
                    // qTPFrom: 52.5 TP
                    // qTPTo: 2350 TC
                    // qACfee: 0
                    // qFeeToken: 10 (0.1% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      tps[0].target.toString(),
                      charlie,
                      charlie,
                      pEth(52.5),
                      pEth(2350),
                      0,
                      pEth(0.05),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TPSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPSwappedForTP event using Fee Token is emitted by bucket 1 queue", async function () {
                    // iFrom: 0
                    // iTo: 1
                    // sender: charlie
                    // receiver: bob
                    // qTPFrom: 2350 TP
                    // qTPTo: 52.5 TP
                    // qACfee: 0
                    // qFeeToken: 20 (0.1% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      tps[1].target.toString(),
                      charlie,
                      bob,
                      pEth(2350),
                      pEth(52.5),
                      0,
                      pEth(0.1),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TPSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPSwappedForTP event using Fee Token is emitted by bucket 2 queue", async function () {
                    // iFrom: 0
                    // iTo: 2
                    // sender: charlie
                    // receiver: charlie
                    // qTPFrom: 2350 TP
                    // qTPto: 9345.8 TP
                    // qACfee: 0
                    // qFeeToken: 30 (0.1% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 30 * 10%
                    const args = [
                      tps[0].target.toString(),
                      tps[2].target.toString(),
                      charlie,
                      charlie,
                      pEth(2350),
                      pEth("9345.800000000000000019"),
                      0,
                      pEth(0.15),
                      0,
                      pEth(3),
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TPSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN combined coverage is 612.11", async function () {
                    assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "612.111111111111111203");
                  });
                });
              });
            });
          });
        });
      });
    });
    describe("AND TP0 price is updated on bucket 0 making its local coverage fall but the combined one is ok", function () {
      let charlieTP1PrevBalances: Balance;
      before(async function () {
        charlieTP1PrevBalances = await tps[1].balanceOf(charlie);
        await enqueueOperations();
        await mocFunctions[0].pokePrice(tps[0].target.toString(), 0.5);
      });
      describe("AND queue is executed", function () {
        before(async function () {
          executionTx = await mocFunctions[0].executeQueue();
        });
        it("THEN bucket 0 emit a low coverage event swapping TP1 for TP0 because ctargemaTP is lower", async function () {
          await expect(executionTx)
            .to.emit(buckets[0].mocQueue, "OperationError")
            .withArgs(anyValue, ERROR_SELECTOR.LOW_COVERAGE, "Low coverage");
        });
        it("THEN all the buckets emit a TPSwappedForTP event", async function () {
          await Promise.all(buckets.map(bucket => expect(executionTx).to.emit(bucket.mocQueue, "TPSwappedForTP")));
        });
        it("THEN TP1 tokens are returned", async function () {
          const charlieTP1ActualBalances = await tps[1].balanceOf(charlie);
          expect(charlieTP1PrevBalances).to.be.equal(charlieTP1ActualBalances);
        });
      });
    });
    describe("AND TPs prices are updated making combined coverage fall below combined ctargemaCA", function () {
      before(async function () {
        await enqueueOperations();
        await Promise.all(mocFunctions.map(mocFunction => mocFunction.pokePrice(tps[0].target.toString(), 0.5)));
      });
      describe("AND queue is executed", function () {
        before(async function () {
          executionTx = await mocFunctions[0].executeQueue();
        });
        it("THEN all the buckets emit a TPSwappedForTP event", async function () {
          await Promise.all(buckets.map(bucket => expect(executionTx).to.emit(bucket.mocQueue, "TPSwappedForTP")));
        });
        it("THEN all the buckets emit a low coverage event", async function () {
          await Promise.all(
            buckets.map(bucket =>
              expect(executionTx)
                .to.emit(bucket.mocQueue, "OperationError")
                .withArgs(anyValue, ERROR_SELECTOR.LOW_COVERAGE, "Low coverage"),
            ),
          );
        });
      });
    });
  });
});
