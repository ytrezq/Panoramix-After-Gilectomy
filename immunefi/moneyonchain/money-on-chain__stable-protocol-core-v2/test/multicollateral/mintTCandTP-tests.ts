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
import { ERC20Mock, MocMultiCollateralGuard } from "../../typechain";
import { fixtureCase1 } from "./fixture";

timedDescribe("Feature: multicollateral joint Mint TC and TP operation", function () {
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
      execCostParams: { mintTCandTPExecCost },
    },
  } = getNetworkDeployParams(hre);

  describe("GIVEN 3 Moc implementations", function () {
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

      alicePrevACBalance = await Promise.all(mocFunctions.map(mocFunction => mocFunction.acBalanceOf(alice)));
      bucketPrevACBalance = await Promise.all(
        buckets.map((bucket, index) => mocFunctions[index].acBalanceOf(bucket.mocImpl.target.toString())),
      );
      feeFlowPrevACBalance = await Promise.all(
        mocFunctions.map(mocFunction => mocFunction.acBalanceOf(mocFeeFlowAddress)),
      );

      enqueueOperations = async () => {
        await Promise.all([
          mocFunctions[0].mintTCandTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500, execute: false }), // 100 AC0
          mocFunctions[1].mintTCandTP({ tp: tps[1].target.toString(), from: alice, to: bob, qTP: 525, execute: false }), // 200 AC1
          mocFunctions[2].mintTCandTP({
            tp: tps[2].target.toString(),
            from: alice,
            qTP: 93458,
            vendor,
            execute: false,
          }), // 300 AC2
          mocFunctions[0].mintTCandTP({ tp: tps[1].target.toString(), from: charlie, qTP: 525, execute: false }), // 100 AC0
          mocFunctions[1].mintTCandTP({
            tp: tps[0].target.toString(),
            from: charlie,
            to: bob,
            qTP: 23500,
            execute: false,
          }), // 200 AC1
          mocFunctions[2].mintTCandTP({
            tp: tps[0].target.toString(),
            from: charlie,
            qTP: 23500,
            vendor,
            execute: false,
          }), // 300 AC2
        ]);
      };
    });
    describe("AND alice enqueue: a mintTCandTP 23500 TP0 (100 AC0) operation on bucket 0", function () {
      describe("AND enqueue: a mintTCandTP 525 TP1 (200 AC1) operation to bob on bucket 1", function () {
        describe("AND enqueue: a mintTCandTP 93458 TP2 (300 AC1) operation via vendor on bucket 2", function () {
          describe("AND charlie enqueue: a mintTCandTP 525 TP1 (100 AC0) operation on bucket 0 having Fee Tokens", function () {
            describe("AND enqueue: a mintTCandTP 23500 TP0 (200 AC0) operation to bob on bucket 1 having Fee Tokens", function () {
              describe("AND enqueue: a mintTCandTP 23500 TP0 (300 AC0) operation via vendor on bucket 2 having Fee Tokens", function () {
                before(async function () {
                  await enqueueOperations();
                });
                describe("AND queue is executed", function () {
                  // execution fee are paid on Coinbase that is configured as Collateral on bucket 1
                  const executionFeeOnAC1 = mintTCandTPExecCost * 3n;
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
                  it("THEN alice receives 454.14 TC0 and 750 TC2", async function () {
                    // ctargemaTP0 = 5.541 => qTC = 23500 * 4.541 / 235 = 454.14
                    assertPrec("454.140728164497264600", await mocFunctions[0].tcBalanceOf(alice));
                    // ctargemaTP2 = 3.5 => qTC = 93458 * 2.5 / 93458 = 750
                    assertPrec("750.000000000000000001", await mocFunctions[2].tcBalanceOf(alice));
                  });
                  it("THEN bob receives 1400 TC1", async function () {
                    // ctargemaTP1 = 4 => qTC = 525 * 3 / 2.625 = 600
                    // ctargemaTP0 = 5 => qTC = 23500 * 4 / 117.5 = 800
                    assertPrec(1400, await mocFunctions[1].tcBalanceOf(bob));
                  });
                  it("THEN charlie has 316.66 TC0 and 1200 TC2", async function () {
                    // ctargemaTP1 = 4.166 => qTC = 525 * 3.166 / 5.25 = 316.66
                    assertPrec("316.666666666666666600", await mocFunctions[0].tcBalanceOf(charlie));
                    // ctargemaTP0 = 5 => qTC = 23500 * 4 / 78.33 = 1200
                    assertPrec("1200.000000000000000005", await mocFunctions[2].tcBalanceOf(charlie));
                  });
                  it("THEN bucket 0 balance increase 970.8 AC0", async function () {
                    // 454.14 TC0 + 100 TP0 + 316.66 TC0 + 100 TP0 = 970.8 Ac0
                    const bucket0Address = buckets[0].mocImpl.target.toString();
                    const diff = (await mocFunctions[0].acBalanceOf(bucket0Address)) - bucketPrevACBalance[0];
                    assertPrec("970.807394831163931200", diff);
                  });
                  it("THEN bucket 1 balance increase 1800 AC1", async function () {
                    // 600 TC1 + 200 TP1 + 800 TC1 + 200 TP0 = 1800 AC1
                    const bucket1Address = buckets[1].mocImpl.target.toString();
                    const diff = (await mocFunctions[1].acBalanceOf(bucket1Address)) - bucketPrevACBalance[1];
                    assertPrec(1800, diff);
                  });
                  it("THEN bucket 2 balance increase 2550 AC2", async function () {
                    // 750 TC2 + 300 TP2 + 1200 TC2 + 300 TP0 = 2550 AC2
                    const bucket2Address = buckets[2].mocImpl.target.toString();
                    const diff = (await mocFunctions[2].acBalanceOf(bucket2Address)) - bucketPrevACBalance[2];
                    assertPrec("2550.000000000000000007", diff);
                  });
                  it("THEN Moc Fee Flow balance increase 44.33 AC0 (8% qACFee)", async function () {
                    const diff = (await mocFunctions[0].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[0];
                    assertPrec("44.331258253159781168", diff);
                  });
                  it("THEN Moc Fee Flow balance increase 64 AC1 (8% qACFee)", async function () {
                    const diff = (await mocFunctions[1].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[1];
                    assertPrec(64, diff);
                  });
                  it("THEN Moc Fee Flow balance increase 84 AC2 (8% qACFee)", async function () {
                    const diff = (await mocFunctions[2].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[2];
                    assertPrec(84, diff);
                  });
                  it("THEN alice balance decrease 598.47 AC0 (554.14 qAC + 8% qACFee)", async function () {
                    const aliceActualACBalance = await mocFunctions[0].acBalanceOf(alice);
                    const diff = alicePrevACBalance[0] - aliceActualACBalance;
                    assertPrec("598.471986417657045768", diff);
                  });
                  it("THEN alice balance decrease 864 AC1 (800 qAC + 8% qACFee)", async function () {
                    const aliceActualACBalance = await mocFunctions[1].acBalanceOf(alice);
                    const diff = alicePrevACBalance[1] - aliceActualACBalance - executionFeeOnAC1;
                    assertPrec(864, diff);
                  });
                  it("THEN alice balance decrease 1239 AC2 (1050 qAC + 8% qACFee + 10% qACVendorMarkup)", async function () {
                    const aliceActualACBalance = await mocFunctions[2].acBalanceOf(alice);
                    const diff = alicePrevACBalance[2] - aliceActualACBalance;
                    assertPrec("1239.000000000000000001", diff);
                  });
                  it("THEN Moc Fee Flow Fee Token balance increase 116.66 ((416.66 + 1000 + 1500) * 8%) * 50%)", async function () {
                    // 16.6 => 416.66 AC0 * 0.08 mintTCandTPFee * 0.5
                    // 40 => 1000 AC1 * 0.08 mintTCandTPFee * 0.5
                    // 60 => 1500 AC2 * 0.08 mintTCandTPFee * 0.5
                    const mocFeeFlowActualFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
                    assertPrec("116.666666666666666664", mocFeeFlowActualFeeTokenBalance);
                  });
                  it("THEN a TCandTPMinted event is emitted by bucket 0 queue", async function () {
                    // i: 0
                    // sender: alice
                    // receiver: alice
                    // qTC: 454.14 TC
                    // qTP: 23500 TP
                    // qAC: 554.14 AC + 8% for Moc Fee Flow
                    // qACtoMintTC: 454.14 AC
                    // qACtoMintTP: 100 AC
                    // qACfee: %8 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      alice,
                      alice,
                      pEth("454.140728164497264600"),
                      pEth(23500),
                      pEth("598.471986417657045768"),
                      pEth("454.140728164497264600"),
                      pEth(100),
                      pEth("44.331258253159781168"),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TCandTPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCandTPMinted event is emitted by bucket 1 queue", async function () {
                    // i: 1
                    // sender: alice
                    // receiver: bob
                    // qTC: 600 TC
                    // qTP: 525 TP
                    // qAC: 800 AC + 8% for Moc Fee Flow
                    // qACtoMintTC: 600 AC
                    // qACtoMintTP: 200 AC
                    // qACfee: %8 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      alice,
                      bob,
                      pEth(600),
                      pEth(525),
                      pEth(864),
                      pEth(600),
                      pEth(200),
                      pEth(64),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TCandTPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCandTPMinted event is emitted by bucket 2 queue", async function () {
                    // i: 2
                    // sender: alice
                    // receiver: alice
                    // qTC: 750 TC
                    // qTP: 93458 TP
                    // qAC: 1050 AC + 8% for Moc Fee Flow - 10% for vendor
                    // qACtoMintTC: 750 AC
                    // qACtoMintTP: 300 AC
                    // qACfee: %8 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 10% qAC
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[2].target.toString(),
                      alice,
                      alice,
                      pEth("750.000000000000000001"),
                      pEth(93458),
                      pEth("1239.000000000000000001"),
                      pEth("750.000000000000000001"),
                      pEth(300),
                      pEth(84),
                      0,
                      pEth(105),
                      0,
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TCandTPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCandTPMinted event using Fee Token is emitted by bucket 0 queue", async function () {
                    // i: 1
                    // sender: charlie
                    // receiver: charlie
                    // qTC: 316.66 TC
                    // qTP: 525 TP
                    // qAC: 416.66 AC
                    // qACtoMintTC: 316.66 AC
                    // qACtoMintTP: 100 AC
                    // qACfee: 0
                    // qFeeToken: 100 (0.8% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      charlie,
                      charlie,
                      pEth("316.666666666666666600"),
                      pEth(525),
                      pEth("416.666666666666666600"),
                      pEth("316.666666666666666600"),
                      pEth(100),
                      0,
                      pEth("16.666666666666666664"),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TCandTPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCandTPMinted event using Fee Token is emitted by bucket 1 queue", async function () {
                    // i: 0
                    // sender: charlie
                    // receiver: bob
                    // qTC: 800 TC
                    // qTP: 23500 TP
                    // qAC: 1000 AC
                    // qACtoMintTC: 800 AC
                    // qACtoMintTP: 200 AC
                    // qACfee: 0
                    // qFeeToken: 40 (0.8% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      bob,
                      pEth(800),
                      pEth(23500),
                      pEth(1000),
                      pEth(800),
                      pEth(200),
                      0,
                      pEth(40),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TCandTPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCandTPMinted event using Fee Token is emitted by bucket 2 queue", async function () {
                    // i: 0
                    // sender: charlie
                    // receiver: charlie
                    // qTC: 1200 TC
                    // qTP: 23500 TP
                    // qAC: 1500 AC
                    // qACtoMintTC: 1200 AC
                    // qACtoMintTP: 300 AC
                    // qACfee: 0
                    // qFeeToken: 60 (0.8% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 1500 * 10%
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      charlie,
                      pEth("1200.000000000000000005"),
                      pEth(23500),
                      pEth("1500.000000000000000006"),
                      pEth("1200.000000000000000005"),
                      pEth("300.000000000000000001"),
                      0,
                      pEth(60),
                      0,
                      pEth(150),
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TCandTPMinted")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN combined coverage is 4.53", async function () {
                    assertPrec(await mocMultiCollateralGuard.getCombinedCglb(), "4.534678991385273218");
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
