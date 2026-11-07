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

timedDescribe("Feature: multicollateral swap Collateral Token for Pegged Token", function () {
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
      execCostParams: { swapTCforTPExecCost },
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
          mocFunctions[0].swapTCforTP({ tp: tps[0].target.toString(), from: alice, qTC: 100, execute: false }), // 100 AC0
          mocFunctions[1].swapTCforTP({ tp: tps[1].target.toString(), from: alice, to: bob, qTC: 200, execute: false }), // 200 AC1
          mocFunctions[2].swapTCforTP({ tp: tps[2].target.toString(), from: alice, qTC: 300, vendor, execute: false }), // 300 AC2
          mocFunctions[0].swapTCforTP({ tp: tps[1].target.toString(), from: charlie, qTC: 100, execute: false }), // 100 AC0
          mocFunctions[1].swapTCforTP({
            tp: tps[0].target.toString(),
            from: charlie,
            to: bob,
            qTC: 200,
            execute: false,
          }), // 200 AC1
          mocFunctions[2].swapTCforTP({
            tp: tps[0].target.toString(),
            from: charlie,
            qTC: 300,
            vendor,
            execute: false,
          }), // 300 AC2
        ]);
      };
    });
    describe("AND alice enqueue: a swapTCforTP 100 TC0 (100 AC0) operation on bucket 0", function () {
      describe("AND enqueue: a swapTCforTP 200 TC1 (200 AC1) operation to bob on bucket 1", function () {
        describe("AND enqueue: a swapTCforTP 300 TC2 (300 AC2) operation via vendor on bucket 2", function () {
          describe("AND charlie enqueue: a swapTCforTP 100 TC0 (100 AC0) operation on bucket 0 having Fee Tokens", function () {
            describe("AND enqueue: a swapTCforTP 200 TC1 (200 AC1) operation to bob on bucket 1 having Fee Tokens", function () {
              describe("AND enqueue: a swapTCforTP 300 TC2 (300 AC2) operation via vendor on bucket 2 having Fee Tokens", function () {
                before(async function () {
                  await enqueueOperations();
                });
                describe("AND queue is executed", function () {
                  // execution fee are paid on Coinbase that is configured as Collateral on bucket 1
                  const executionFeeOnAC1 = swapTCforTPExecCost * 3n;
                  before(async function () {
                    executionTx = await mocFunctions[0].executeQueue();
                  });
                  it("THEN alice redeems 100 TC0, 200 TC1 and 300 TC2", async function () {
                    assertPrec(99900, await mocFunctions[0].tcBalanceOf(alice));
                    assertPrec(99800, await mocFunctions[1].tcBalanceOf(alice));
                    assertPrec(99700, await mocFunctions[2].tcBalanceOf(alice));
                  });
                  it("THEN charlie redeems 100 TC0, 200 TC1 and 300 TC2", async function () {
                    assertPrec(99900, await mocFunctions[0].tcBalanceOf(charlie));
                    assertPrec(99800, await mocFunctions[1].tcBalanceOf(charlie));
                    assertPrec(99700, await mocFunctions[2].tcBalanceOf(charlie));
                  });
                  it("THEN alice mints 23500 TP0 and 93457.99 TP2", async function () {
                    assertPrec(47000, await tps[0].balanceOf(alice));
                    assertPrec("186915.999999999999999800", await tps[2].balanceOf(alice));
                  });
                  it("THEN bob mints 23500 TP0 and 525 TP1", async function () {
                    assertPrec(23500, await tps[0].balanceOf(bob));
                    assertPrec(525, await tps[1].balanceOf(bob));
                  });
                  it("THEN charlie mints 23499.99 TP0 and 525 TP1", async function () {
                    assertPrec("70499.999999999999999900", await tps[0].balanceOf(charlie));
                    assertPrec(1050, await tps[1].balanceOf(charlie));
                  });
                  it("THEN Moc Fee Flow balance increase 1 AC0 (1% qACFee)", async function () {
                    const diff = (await mocFunctions[0].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[0];
                    assertPrec(1, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 2 AC1 (2% qACFee)", async function () {
                    const diff = (await mocFunctions[1].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[1];
                    assertPrec(2, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 3 AC2 (1% qACFee)", async function () {
                    const diff = (await mocFunctions[2].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[2];
                    assertPrec(3, diff);
                  });
                  it("THEN alice balance decrease 1 AC0 (1% qACFee)", async function () {
                    const aliceActualACBalance = await mocFunctions[0].acBalanceOf(alice);
                    const diff = alicePrevACBalance[0] - aliceActualACBalance;
                    assertPrec(1, diff);
                  });
                  it("THEN alice balance decrease 2 AC1 (1% qACFee)", async function () {
                    const aliceActualACBalance = await mocFunctions[1].acBalanceOf(alice);
                    const diff = alicePrevACBalance[1] - aliceActualACBalance - executionFeeOnAC1;
                    assertPrec(2, diff);
                  });
                  it("THEN alice balance decrease 33 AC2 (1% qACFee + 10% qACVendorMarkup)", async function () {
                    const aliceActualACBalance = await mocFunctions[2].acBalanceOf(alice);
                    const diff = alicePrevACBalance[2] - aliceActualACBalance;
                    assertPrec(33, diff);
                  });
                  it("THEN Moc Fee Flow Fee Token balance increase 3 ((100 + 200 + 300) * 1%) * 50%)", async function () {
                    // 0.5 => 100 AC0 * 0.01 swapTCforTPFee * 0.5
                    // 1 => 200 AC1 * 0.01 swapTCforTPFee * 0.5
                    // 1.5 => 300 AC2 * 0.01 swapTCforTPFee * 0.5
                    const mocFeeFlowActualFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
                    assertPrec(3, mocFeeFlowActualFeeTokenBalance);
                  });
                  it("THEN a TCSwappedForTP event is emitted by bucket 0 queue", async function () {
                    // i: 0
                    // sender: alice
                    // receiver: alice
                    // qTC: 100 TC
                    // qTP: 23500 TP
                    // qACfee: %1 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      alice,
                      alice,
                      pEth(100),
                      pEth(23500),
                      pEth(1),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TCSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCSwappedForTP event is emitted by bucket 1 queue", async function () {
                    // i: 1
                    // sender: alice
                    // receiver: bob
                    // qTC: 200 TC
                    // qTP: 525 TP
                    // qACfee: %1 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      alice,
                      bob,
                      pEth(200),
                      pEth(525),
                      pEth(2),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TCSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCSwappedForTP event is emitted by bucket 2 queue", async function () {
                    // i: 2
                    // sender: alice
                    // receiver: alice
                    // qTC: 300 TC
                    // qTP: 93457.9 TP
                    // qACfee: %1 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 10% qAC
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[2].target.toString(),
                      alice,
                      alice,
                      pEth(300),
                      pEth("93457.999999999999999800"),
                      pEth(3),
                      0,
                      pEth(30),
                      0,
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TCSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCSwappedForTP event using Fee Token is emitted by bucket 0 queue", async function () {
                    // i: 1
                    // sender: charlie
                    // receiver: charlie
                    // qTC: 100 TC
                    // qTP: 525 TP
                    // qACfee: 0
                    // qFeeToken: 0.5 (0.1% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      charlie,
                      charlie,
                      pEth(100),
                      pEth(525),
                      0,
                      pEth(0.5),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TCSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCSwappedForTP event using Fee Token is emitted by bucket 1 queue", async function () {
                    // i: 0
                    // sender: charlie
                    // receiver: bob
                    // qTC: 200 TC
                    // qTP: 23500 TP
                    // qACfee: 0
                    // qFeeToken: 200 (0.1% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      bob,
                      pEth(200),
                      pEth(23500),
                      0,
                      pEth(1),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TCSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCSwappedForTP event using Fee Token is emitted by bucket 2 queue", async function () {
                    // i: 0
                    // sender: charlie
                    // receiver: charlie
                    // qTC: 300 TC
                    // qTP: 23499.9 TP
                    // qACfee: 0
                    // qFeeToken: 300 (0.1% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 300 * 10%
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      charlie,
                      pEth(300),
                      pEth("23499.999999999999999900"),
                      0,
                      pEth(1.5),
                      0,
                      pEth(30),
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TCSwappedForTP")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN combined coverage is 306.05", async function () {
                    assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "306.055555555555555601");
                  });
                });
              });
            });
          });
        });
      });
    });
    describe("AND TP0 price is updated on bucket 0 making its local coverage fall but the combined one is ok", function () {
      before(async function () {
        await enqueueOperations();
        await mocFunctions[0].pokePrice(tps[0].target.toString(), 0.5);
      });
      describe("AND queue is executed", function () {
        before(async function () {
          executionTx = await mocFunctions[0].executeQueue();
        });
        it("THEN bucket 0 emit a low coverage event", async function () {
          await expect(executionTx)
            .to.emit(buckets[0].mocQueue, "OperationError")
            .withArgs(anyValue, ERROR_SELECTOR.LOW_COVERAGE, "Low coverage");
        });
        it("THEN bucket 1 and 2 emit a TCSwappedForTP event", async function () {
          await expect(executionTx).to.emit(buckets[1].mocQueue, "TCSwappedForTP");
          await expect(executionTx).to.emit(buckets[2].mocQueue, "TCSwappedForTP");
        });
      });
    });
    describe("AND TPs prices are updated making combined coverage fall below combined ctargemaCA", function () {
      let aliceTCPrevBalances: Balance[];
      before(async function () {
        aliceTCPrevBalances = await Promise.all(mocFunctions.map(mocFunction => mocFunction.tcBalanceOf(alice)));
        await enqueueOperations();
        await Promise.all(mocFunctions.map(mocFunction => mocFunction.pokePrice(tps[0].target.toString(), 0.5)));
      });
      describe("AND queue is executed", function () {
        before(async function () {
          executionTx = await mocFunctions[0].executeQueue();
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
        it("THEN TC tokens are returned", async function () {
          const aliceTCActualBalances = await Promise.all(
            mocFunctions.map(mocFunction => mocFunction.tcBalanceOf(alice)),
          );
          expect(aliceTCPrevBalances).to.be.deep.equal(aliceTCActualBalances);
        });
      });
    });
  });
});
