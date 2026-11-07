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

timedDescribe("Feature: multicollateral redeem Collateral Tokens", function () {
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
      execCostParams: { tcRedeemExecCost },
    },
  } = getNetworkDeployParams(hre);

  describe("GIVEN 3 Moc implementations deployed with TCs minted to alice and charlie", function () {
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
      bucketPrevACBalance = await Promise.all(
        buckets.map((bucket, index) => mocFunctions[index].acBalanceOf(bucket.mocImpl.target.toString())),
      );
      feeFlowPrevACBalance = await Promise.all(
        mocFunctions.map(mocFunction => mocFunction.acBalanceOf(mocFeeFlowAddress)),
      );
      bobPrevAC1Balance = await mocFunctions[1].acBalanceOf(bob);

      enqueueOperations = async () => {
        await Promise.all([
          mocFunctions[0].redeemTC({ from: alice, qTC: 100, execute: false }), // 100 AC0
          mocFunctions[1].redeemTC({ from: alice, to: bob, qTC: 200, execute: false }), // 200 AC1
          mocFunctions[2].redeemTC({ from: alice, qTC: 300, vendor, execute: false }), // 300 AC2
          mocFunctions[0].redeemTC({ from: charlie, qTC: 100, execute: false }), // 100 AC0
          mocFunctions[1].redeemTC({ from: charlie, to: bob, qTC: 200, execute: false }), // 200 AC1
          mocFunctions[2].redeemTC({ from: charlie, qTC: 300, vendor, execute: false }), // 300 AC2
        ]);
      };
    });
    describe("AND alice enqueue: a redeem 100 TC0 (100 AC0) operation on bucket 0", function () {
      describe("AND enqueue: a redeem 200 TC1 (200 AC1) operation to bob on bucket 1", function () {
        describe("AND enqueue: a redeem 300 TC2 (300 AC1) operation via vendor on bucket 2", function () {
          describe("AND charlie enqueue: a redeem 100 TC0 (100 AC0) operation on bucket 0 having Fee Tokens", function () {
            describe("AND enqueue: a redeem 200 TC1 (200 AC0) operation to bob on bucket 1 having Fee Tokens", function () {
              describe("AND enqueue: a redeem 300 TC2 (300 AC0) operation via vendor on bucket 2 having Fee Tokens", function () {
                before(async function () {
                  await enqueueOperations();
                });
                describe("AND queue is executed", function () {
                  // execution fee are paid on Coinbase that is configured as Collateral on bucket 1
                  const executionFeeOnAC1 = tcRedeemExecCost * 3n;
                  before(async function () {
                    executionTx = await mocFunctions[0].executeQueue();
                  });
                  it("THEN alice has 99900 TC0, 99800 TC1 and 99700 TC2", async function () {
                    assertPrec(99900, await mocFunctions[0].tcBalanceOf(alice));
                    assertPrec(99800, await mocFunctions[1].tcBalanceOf(alice));
                    assertPrec(99700, await mocFunctions[2].tcBalanceOf(alice));
                  });
                  it("THEN charlie has 99900 TC0, 99800 TC1 and 99700 TC2", async function () {
                    assertPrec(99900, await mocFunctions[0].tcBalanceOf(charlie));
                    assertPrec(99800, await mocFunctions[1].tcBalanceOf(charlie));
                    assertPrec(99700, await mocFunctions[2].tcBalanceOf(charlie));
                  });
                  it("THEN bucket 0 balance decrease 200 AC0", async function () {
                    const bucket0Address = buckets[0].mocImpl.target.toString();
                    const diff = bucketPrevACBalance[0] - (await mocFunctions[0].acBalanceOf(bucket0Address));
                    assertPrec(200, diff);
                  });
                  it("THEN bucket 1 balance decrease 400 AC1", async function () {
                    const bucket1Address = buckets[1].mocImpl.target.toString();
                    const diff = bucketPrevACBalance[1] - (await mocFunctions[1].acBalanceOf(bucket1Address));
                    assertPrec(400, diff);
                  });
                  it("THEN bucket 2 balance decrease 600 AC2", async function () {
                    const bucket2Address = buckets[2].mocImpl.target.toString();
                    const diff = bucketPrevACBalance[2] - (await mocFunctions[2].acBalanceOf(bucket2Address));
                    assertPrec(600, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 5 AC0 (5% qACFee)", async function () {
                    const diff = (await mocFunctions[0].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[0];
                    assertPrec(5, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 10 AC1 (5% qACFee TP1)", async function () {
                    const diff = (await mocFunctions[1].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[1];
                    assertPrec(10, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 15 AC2 (5% qACFee TP2)", async function () {
                    const diff = (await mocFunctions[2].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[2];
                    assertPrec(15, diff);
                  });
                  it("THEN alice balance increase 95 AC0 (100 qAC - 5% qACFee TP0)", async function () {
                    const aliceActualACBalance = await mocFunctions[0].acBalanceOf(alice);
                    const diff = aliceActualACBalance - alicePrevACBalance[0];
                    assertPrec(95, diff);
                  });
                  it("THEN alice balance decrease the redeem execution fee on AC1, redeemed AC1 went to bob", async function () {
                    const aliceActualACBalance = await mocFunctions[1].acBalanceOf(alice);
                    const diff = alicePrevACBalance[1] - aliceActualACBalance;
                    assertPrec(executionFeeOnAC1, diff);
                  });
                  it("THEN alice balance increase 255 AC2 (300 qAC - 5% qACFee TP2 - 10% qACVendorMarkup)", async function () {
                    const aliceActualACBalance = await mocFunctions[2].acBalanceOf(alice);
                    const diff = aliceActualACBalance - alicePrevACBalance[2];
                    assertPrec(255, diff);
                  });
                  it("THEN bob balance increase 390 AC1 (200 qAC - 5% qACFee TP1 + 200 qAC)", async function () {
                    const bobActualACBalance = await mocFunctions[1].acBalanceOf(bob);
                    const diff = bobActualACBalance - bobPrevAC1Balance;
                    assertPrec(390, diff);
                  });
                  it("THEN Moc Fee Flow Fee Token balance increase 15 ((100 + 200 + 300) * 5%) * 50%)", async function () {
                    // 2.5 => 100 AC0 * 0.05 TP1 redeemFee * 0.5
                    // 5 => 200 AC1 * 0.05 TP0 redeemFee * 0.5
                    // 7.5 => 300 AC2 * 0.05 TP0 redeemFee * 0.5
                    const mocFeeFlowActualFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
                    assertPrec(15, mocFeeFlowActualFeeTokenBalance);
                  });
                  it("THEN a TCRedeemed event is emitted by bucket 0 queue", async function () {
                    // sender: alice
                    // receiver: alice
                    // qTC: 100 TC
                    // qAC: 100 AC - 5% for Moc Fee Flow
                    // qACfee: %5 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [alice, alice, pEth(100), pEth(95), pEth(5), 0, 0, 0, noVendor];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TCRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCRedeemed event is emitted by bucket 1 queue", async function () {
                    // sender: alice
                    // receiver: bob
                    // qTC: 200 TC
                    // qAC: 200 AC - 5% for Moc Fee Flow
                    // qACfee: %5 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [alice, bob, pEth(200), pEth(190), pEth(10), 0, 0, 0, noVendor];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TCRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCRedeemed event is emitted by bucket 2 queue", async function () {
                    // sender: alice
                    // receiver: alice
                    // qTC: 300 TC
                    // qAC: 300 AC - 5% for Moc Fee Flow - 10% for vendor
                    // qACfee: %5 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 10% qAC
                    // qFeeTokenVendorMarkup: 0
                    const args = [alice, alice, pEth(300), pEth(255), pEth(15), 0, pEth(30), 0, vendor];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TCRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCRedeemed event using Fee Token is emitted by bucket 0 queue", async function () {
                    // sender: charlie
                    // receiver: charlie
                    // qTC: 100 TC
                    // qAC: 100 AC
                    // qACfee: 0
                    // qFeeToken: 100 (0.5% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [charlie, charlie, pEth(100), pEth(100), 0, pEth(2.5), 0, 0, noVendor];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TCRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCRedeemed event using Fee Token is emitted by bucket 1 queue", async function () {
                    // sender: charlie
                    // receiver: bob
                    // qTC: 200 TC
                    // qAC: 200 AC
                    // qACfee: 0
                    // qFeeToken: 200 (0.5% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [charlie, bob, pEth(200), pEth(200), 0, pEth(5), 0, 0, noVendor];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TCRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCRedeemed event using Fee Token is emitted by bucket 2 queue", async function () {
                    // sender: charlie
                    // receiver: charlie
                    // qTC: 300 TC
                    // qAC: 300 AC
                    // qACfee: 0
                    // qFeeToken: 300 (0.5% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 300 * 10%
                    const args = [charlie, charlie, pEth(300), pEth(300), 0, pEth(7.5), 0, pEth(30), vendor];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TCRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN combined coverage is 611.11", async function () {
                    assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "611.111111111111111203");
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
        it("THEN bucket 1 and 2 emit a TCRedeemed event", async function () {
          await expect(executionTx).to.emit(buckets[1].mocQueue, "TCRedeemed");
          await expect(executionTx).to.emit(buckets[2].mocQueue, "TCRedeemed");
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
