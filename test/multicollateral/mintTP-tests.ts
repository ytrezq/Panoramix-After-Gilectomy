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

timedDescribe("Feature: multicollateral mint Pegged Tokens", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let alicePrevACBalance = new Array<Balance>(3);
  let bucketPrevACBalance = new Array<Balance>(3);
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
      execCostParams: { tpMintExecCost },
    },
  } = getNetworkDeployParams(hre);

  describe("GIVEN 3 Moc implementations deployed with 3 TPs added on every buckets", function () {
    before(async function () {
      ({ alice, bob, charlie, vendor } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixtureCase1);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, feeToken, mocMultiCollateralGuard } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });

      const charlieSigner = await ethers.getSigner(charlie);
      // mint FeeToken to charlie
      await Promise.all([
        feeToken.mint(charlie, pEth(10000)),
        ...buckets.map(bucket =>
          feeToken.connect(charlieSigner).approve(bucket.mocImpl.target.toString(), pEth(10000)),
        ),
      ]);

      // add collateral to every buckets
      await Promise.all(mocFunctions.map(fncs => fncs.mintTC({ from: alice, qTC: 100000, execute: false })));
      await mocFunctions[0].executeQueue();

      alicePrevACBalance = await Promise.all(mocFunctions.map(mocFunction => mocFunction.acBalanceOf(alice)));
      bucketPrevACBalance = await Promise.all(
        buckets.map((bucket, index) => mocFunctions[index].acBalanceOf(bucket.mocImpl.target.toString())),
      );
      feeFlowPrevACBalance = await Promise.all(
        mocFunctions.map(mocFunction => mocFunction.acBalanceOf(mocFeeFlowAddress)),
      );
      // cases:
      // 1. TP0 is on all the buckets
      // 2. TP1 is missing on bucket2
      // 3. TP2 is only on bucket2
      enqueueOperations = async () => {
        await Promise.all([
          mocFunctions[0].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500, execute: false }), // 100 AC0
          mocFunctions[1].mintTP({ tp: tps[1].target.toString(), from: alice, to: bob, qTP: 525, execute: false }), // 200 AC1
          mocFunctions[2].mintTP({ tp: tps[2].target.toString(), from: alice, qTP: 93458, vendor, execute: false }), // 300 AC2
          mocFunctions[0].mintTP({ tp: tps[1].target.toString(), from: charlie, qTP: 525, execute: false }), // 100 AC0
          mocFunctions[1].mintTP({ tp: tps[0].target.toString(), from: charlie, to: bob, qTP: 23500, execute: false }), // 200 AC1
          mocFunctions[2].mintTP({ tp: tps[0].target.toString(), from: charlie, qTP: 23500, vendor, execute: false }), // 300 AC2
        ]);
      };
    });
    describe("AND alice enqueue: a mint 23500 TP0 (100 AC0) operation on bucket 0", function () {
      describe("AND enqueue: a mint 525 TP1 (200 AC1) operation to bob on bucket 1", function () {
        describe("AND enqueue: a mint 93458 TP2 (300 AC1) operation via vendor on bucket 2", function () {
          describe("AND charlie enqueue: a mint 525 TP1 (100 AC0) operation on bucket 0 having Fee Tokens", function () {
            describe("AND enqueue: a mint 23500 TP0 (200 AC0) operation to bob on bucket 1 having Fee Tokens", function () {
              describe("AND enqueue: a mint 23500 TP0 (300 AC0) operation via vendor on bucket 2 having Fee Tokens", function () {
                before(async function () {
                  await enqueueOperations();
                });
                describe("AND queue is executed", function () {
                  // execution fee are paid on Coinbase that is configured as Collateral on bucket 1
                  const executionFeeOnAC1 = tpMintExecCost * 3n;
                  before(async function () {
                    executionTx = await mocFunctions[0].executeQueue();
                  });
                  it("THEN alice receives 23500 TP0 and 93458 TP2", async function () {
                    assertPrec(23500, await tps[0].balanceOf(alice));
                    assertPrec(93458, await tps[2].balanceOf(alice));
                  });
                  it("THEN bob receives 23500 TP0 and 52500 TP1", async function () {
                    assertPrec(23500, await tps[0].balanceOf(bob));
                    assertPrec(525, await tps[1].balanceOf(bob));
                  });
                  it("THEN charlie receives 23500 TP0 and 52500 TP1", async function () {
                    assertPrec(23500, await tps[0].balanceOf(charlie));
                    assertPrec(525, await tps[1].balanceOf(charlie));
                  });
                  it("THEN bucket 0 balance increase 200 AC0", async function () {
                    const bucket0Address = buckets[0].mocImpl.target.toString();
                    const diff = (await mocFunctions[0].acBalanceOf(bucket0Address)) - bucketPrevACBalance[0];
                    // 23500 alice TP0 mint => 100 AC0
                    // 525 charlie TP1 mint => 100 AC0
                    assertPrec(200, diff);
                  });
                  it("THEN bucket 1 balance increase 400 AC1", async function () {
                    const bucket1Address = buckets[1].mocImpl.target.toString();
                    const diff = (await mocFunctions[1].acBalanceOf(bucket1Address)) - bucketPrevACBalance[1];
                    // 525 alice TP1 mint => 200 AC1
                    // 23500 charlie TP0 mint => 200 AC1
                    assertPrec(400, diff);
                  });
                  it("THEN bucket 2 balance increase 600 AC2", async function () {
                    const bucket2Address = buckets[2].mocImpl.target.toString();
                    const diff = (await mocFunctions[2].acBalanceOf(bucket2Address)) - bucketPrevACBalance[2];
                    // 93458 alice TP2 mint => 300 AC2
                    // 23500 charlie TP0 mint => 300 AC2
                    assertPrec(600, diff, undefined, 1);
                  });
                  it("THEN Moc Fee Flow balance increase 5 AC0 (5% qACFee TP0)", async function () {
                    const diff = (await mocFunctions[0].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[0];
                    assertPrec(5, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 2 AC1 (0.1% qACFee TP1)", async function () {
                    const diff = (await mocFunctions[1].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[1];
                    assertPrec(0.2, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 15 AC2 (5% qACFee TP2)", async function () {
                    const diff = (await mocFunctions[2].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[2];
                    assertPrec(15, diff);
                  });
                  it("THEN alice balance decrease 105 AC0 (100 qAC + 5% qACFee TP0)", async function () {
                    const aliceActualACBalance = await mocFunctions[0].acBalanceOf(alice);
                    const diff = alicePrevACBalance[0] - aliceActualACBalance;
                    assertPrec(105, diff);
                  });
                  it("THEN alice balance decrease 200.2 AC1 (200 qAC + 0.1% qACFee TP1)", async function () {
                    const aliceActualACBalance = await mocFunctions[1].acBalanceOf(alice);
                    const diff = alicePrevACBalance[1] - aliceActualACBalance - executionFeeOnAC1;
                    assertPrec(200.2, diff);
                  });
                  it("THEN alice balance decrease 345 AC2 (300 qAC + 5% qACFee TP2 + 10% qACVendorMarkup)", async function () {
                    const aliceActualACBalance = await mocFunctions[2].acBalanceOf(alice);
                    const diff = alicePrevACBalance[2] - aliceActualACBalance;
                    assertPrec(345, diff);
                  });
                  it("THEN Moc Fee Flow Fee Token balance increase 12.55 ((100 * 0.1% + (200 + 300) * 5%) * 50%)", async function () {
                    // 0.05 => 100 AC0 * 0.001 TP1 mintFee * 0.5
                    // 5 => 200 AC1 * 0.05 TP0 mintFee * 0.5
                    // 7.5 => 300 AC2 * 0.05 TP0 mintTPFee * 0.5
                    const mocFeeFlowActualFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
                    assertPrec(12.55, mocFeeFlowActualFeeTokenBalance);
                  });
                  it("THEN a TPMinted event is emitted by bucket 0 queue for TP0", async function () {
                    // tp: tp0
                    // sender: alice
                    // receiver: alice
                    // qTP: 23500 TP
                    // qAC: 100 AC + 5% for Moc Fee Flow
                    // qACfee: %5 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      alice,
                      alice,
                      pEth(23500),
                      pEth(105),
                      pEth(5),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPMinted event is emitted by bucket 1 queue for TP1", async function () {
                    // tp: tp1
                    // sender: alice
                    // receiver: bob
                    // qTP: 525 TP
                    // qAC: 200 AC + 0.1% for Moc Fee Flow
                    // qACfee: %0.1 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      alice,
                      bob,
                      pEth(525),
                      pEth(200.2),
                      pEth(0.2),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPMinted event is emitted by bucket 2 queue for TP2", async function () {
                    // tp: tp2
                    // sender: alice
                    // receiver: alice
                    // qTP: 93458 TP
                    // qAC: 300 AC + 5% for Moc Fee Flow + 10% for vendor
                    // qACfee: %5 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 10% qAC
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[2].target.toString(),
                      alice,
                      alice,
                      pEth(93458),
                      pEth(345),
                      pEth(15),
                      0,
                      pEth(30),
                      0,
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPMinted event using Fee Token is emitted by bucket 0 queue for TP1", async function () {
                    // tp: tp1
                    // sender: charlie
                    // receiver: charlie
                    // qTP: 525 TP
                    // qAC: 100 AC
                    // qACfee: 0
                    // qFeeToken: 100 (0.1% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      charlie,
                      charlie,
                      pEth(525),
                      pEth(100),
                      0,
                      pEth(0.05),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPMinted event using Fee Token is emitted by bucket 1 queue for TP0", async function () {
                    // tp: tp0
                    // sender: charlie
                    // receiver: bob
                    // qTP: 23500 TP
                    // qAC: 200 AC
                    // qACfee: 0
                    // qFeeToken: 200 (0.5% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      bob,
                      pEth(23500),
                      pEth(200),
                      0,
                      pEth(5),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TPMinted event using Fee Token is emitted by bucket 2 queue for TP0", async function () {
                    // tp: tp0
                    // sender: charlie
                    // receiver: charlie
                    // qTP: 23500 TP
                    // qAC: 300 AC
                    // qACfee: 0
                    // qFeeToken: 300 (0.5% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 300 * 10%
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      charlie,
                      pEth(23500),
                      pEth("300.000000000000000001"),
                      0,
                      pEth(7.5),
                      0,
                      pEth(30),
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN combined coverage is 306.55", async function () {
                    assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "306.555555555555555601");
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
        it("THEN bucket 1 and 2 emit a TPMinted event", async function () {
          await expect(executionTx).to.emit(buckets[1].mocQueue, "TPMinted");
          await expect(executionTx).to.emit(buckets[2].mocQueue, "TPMinted");
        });
      });
    });
    describe("AND TPs prices are updated making combined coverage fall below combined ctargemaCA", function () {
      let aliceACPrevBalances: Balance[];
      before(async function () {
        aliceACPrevBalances = await Promise.all(mocFunctions.map(mocFunction => mocFunction.acBalanceOf(alice)));
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
        it("THEN AC tokens are returned", async function () {
          const aliceACActualBalances = await Promise.all(
            mocFunctions.map(mocFunction => mocFunction.acBalanceOf(alice)),
          );
          // execution fee are paid on Coinbase that is configured as Collateral on bucket 1
          const executionFeeOnAC1 = tpMintExecCost * 3n;
          aliceACPrevBalances[1] = aliceACPrevBalances[1] - executionFeeOnAC1;
          expect(aliceACPrevBalances).to.be.deep.equal(aliceACActualBalances);
        });
      });
    });
  });
});
