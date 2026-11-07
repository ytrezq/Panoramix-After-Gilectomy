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

timedDescribe("Feature: multicollateral joint redeem TC and TP operation", function () {
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
  let cglbRelationBefore: Balance;
  const noVendor = CONSTANTS.ZERO_ADDRESS;
  const {
    mocAddresses: { mocFeeFlowAddress },
    queueParams: {
      execCostParams: { redeemTCandTPExecCost },
    },
  } = getNetworkDeployParams(hre);

  let getCglbRelation: () => Promise<Balance>;

  describe("GIVEN 3 Moc implementations deployed with TCs and TPs minted to alice and charlie", function () {
    before(async function () {
      ({ alice, bob, charlie, vendor } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixtureCase1);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, feeToken, mocMultiCollateralGuard } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });

      getCglbRelation = async () => {
        const cglb = (await mocMultiCollateralGuard.getCombinedCglb()) - pEth(1);
        const ctargema = (await mocMultiCollateralGuard.getCombinedCtargemaCA()) - pEth(1);
        return (cglb * pEth(1)) / ctargema;
      };

      const execute = false;
      // add TCs to alice and charlie
      await Promise.all([
        ...mocFunctions.map(fncs => fncs.mintTC({ from: alice, qTC: 100000, execute })),
        ...mocFunctions.map(fncs => fncs.mintTC({ from: charlie, qTC: 100000, execute })),
      ]);

      // add TPs to alice and charlie
      await Promise.all([
        mocFunctions[0].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500, execute }), // 100 AC0
        mocFunctions[1].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 525, execute }), // 200 AC1
        mocFunctions[2].mintTP({ tp: tps[2].target.toString(), from: alice, qTP: 93458, execute }), // 300 AC2
        mocFunctions[0].mintTP({ tp: tps[1].target.toString(), from: charlie, qTP: 525, execute }), // 100 AC0
        mocFunctions[1].mintTP({ tp: tps[0].target.toString(), from: charlie, qTP: 23500, execute }), // 200 AC1
        mocFunctions[2].mintTP({ tp: tps[0].target.toString(), from: charlie, qTP: 23500, execute }), // 300 AC2
      ]);
      // the startFromBucket padding is not inherent for this tests, it's just that the numbers where crafted with that configuration
      await mocFunctions[0].executeQueue({ startFromBucket: 1 });

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
        // Operations are streamlined because different order affects rounding errors
        await mocFunctions[0].redeemTCandTP({ tp: tps[0], from: alice, qTC: 100, qTP: 23500, execute }); // 100 AC0
        await mocFunctions[1].redeemTCandTP({ tp: tps[1], from: alice, to: bob, qTC: 200, qTP: 525, execute }); // 200 AC1
        await mocFunctions[2].redeemTCandTP({ tp: tps[2], from: alice, qTC: 300, qTP: 93458, vendor, execute }); // 300 AC2
        await mocFunctions[0].redeemTCandTP({ tp: tps[1], from: charlie, qTC: 100, qTP: 525, execute }); // 100 AC0
        await mocFunctions[1].redeemTCandTP({ tp: tps[0], from: charlie, to: bob, qTP: 23500, qTC: 200, execute }); // 200 AC1
        await mocFunctions[2].redeemTCandTP({ tp: tps[0], from: charlie, qTC: 300, qTP: 23500, vendor, execute }); // 300 AC2
      };
    });
    describe("AND alice enqueue: a redeemTCandTP 100 TC0 (100 AC0) operation on bucket 0", function () {
      describe("AND enqueue: a redeemTCandTP 200 TC1 (200 AC1) operation to bob on bucket 1", function () {
        describe("AND enqueue: a redeemTCandTP 300 TC2 (300 AC1) operation via vendor on bucket 2", function () {
          describe("AND charlie enqueue: a redeemTCandTP 100 TC0 (100 AC0) operation on bucket 0 having Fee Tokens", function () {
            describe("AND enqueue: a redeemTCandTP 200 TC1 (200 AC0) operation to bob on bucket 1 having Fee Tokens", function () {
              describe("AND enqueue: a redeemTCandTP 300 TC2 (300 AC0) operation via vendor on bucket 2 having Fee Tokens", function () {
                before(async function () {
                  await enqueueOperations();
                });
                describe("AND queue is executed", function () {
                  // execution fee are paid on Coinbase that is configured as Collateral on bucket 1
                  const executionFeeOnAC1 = redeemTCandTPExecCost * 3n;
                  before(async function () {
                    cglbRelationBefore = await getCglbRelation();
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
                  it("THEN alice redeems 29.93 TP0, 1.01 TP1 and 216.22 TP2", async function () {
                    assertPrec("23470.069966089406149230", await tps[0].balanceOf(alice));
                    assertPrec("523.987796470648762670", await tps[1].balanceOf(alice));
                    assertPrec("93241.774817266038997914", await tps[2].balanceOf(alice));
                  });
                  it("THEN charlie has 33.98 + 33.98 TP0 and 0.95 TP1", async function () {
                    assertPrec("46932.037763029274064964", await tps[0].balanceOf(charlie));
                    assertPrec("524.041070340614617266", await tps[1].balanceOf(charlie));
                  });
                  it("THEN bucket 0 balance decrease 200.3 AC0", async function () {
                    // 100 TC0 + (29.93 / 235) TP0 + 100 TC0 + (0.95/ 5.25) TP1 = 200.3 AC0
                    const bucket0Address = buckets[0].mocImpl.target.toString();
                    const diff = bucketPrevACBalance[0] - (await mocFunctions[0].acBalanceOf(bucket0Address));
                    assertPrec("200.310015114882417555", diff);
                  });
                  it("THEN bucket 1 balance decrease 400.6 AC1", async function () {
                    // 200 TC1 + (1.01 / 2.625) TP1 + 200 TC1 + (33.98 / 117.5) TP0 = 400.6 AC1
                    const bucket1Address = buckets[1].mocImpl.target.toString();
                    const diff = bucketPrevACBalance[1] - (await mocFunctions[1].acBalanceOf(bucket1Address));
                    assertPrec("400.674802352900824886", diff);
                  });
                  it("THEN bucket 2 balance decrease 601.1 AC2", async function () {
                    // 300 TC2 + (216.22 / 311.52) TP2 + 300 TC2 + (33.98 / 78.33) TP0 = 601.1 AC2
                    const bucket2Address = buckets[2].mocImpl.target.toString();
                    const diff = bucketPrevACBalance[2] - (await mocFunctions[2].acBalanceOf(bucket2Address));
                    assertPrec("601.127883932705664452", diff);
                  });
                  it("THEN Moc Fee Flow balance increase 8.01 AC0 (8% qACFee)", async function () {
                    const diff = (await mocFunctions[0].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[0];
                    assertPrec("8.010188947714244715", diff);
                  });
                  it("THEN Moc Fee Flow balance increase 16.03 AC1 (8% qACFee)", async function () {
                    const diff = (await mocFunctions[1].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[1];
                    assertPrec("16.030848107561180566", diff);
                  });
                  it("THEN Moc Fee Flow balance increase 24.05 AC2 (8% qACFee)", async function () {
                    const diff = (await mocFunctions[2].acBalanceOf(mocFeeFlowAddress)) - feeFlowPrevACBalance[2];
                    assertPrec("24.055526593610125019", diff);
                  });
                  it("THEN alice balance increase 92.17 AC0 (100.12 qAC - 8% qACFee)", async function () {
                    const aliceActualACBalance = await mocFunctions[0].acBalanceOf(alice);
                    const diff = aliceActualACBalance - alicePrevACBalance[0];
                    assertPrec("92.117172898713814224", diff);
                  });
                  it("THEN alice balance decrease the redeemTCandTP execution fee on AC1, redeemed AC1 went to bob", async function () {
                    const aliceActualACBalance = await mocFunctions[1].acBalanceOf(alice);
                    const diff = alicePrevACBalance[1] - aliceActualACBalance;
                    assertPrec(executionFeeOnAC1, diff);
                  });
                  it("THEN alice balance increase 246.56 AC2 (300.6 qAC - 8% qACFee - 10% qACVendorMarkup)", async function () {
                    const aliceActualACBalance = await mocFunctions[2].acBalanceOf(alice);
                    const diff = aliceActualACBalance - alicePrevACBalance[2];
                    assertPrec("246.569147584503781447", diff);
                  });
                  it("THEN bob balance increase 384.64 AC1 (200.38 qAC - 8% qACFee + 200.28 qAC)", async function () {
                    const bobActualACBalance = await mocFunctions[1].acBalanceOf(bob);
                    const diff = bobActualACBalance - bobPrevAC1Balance;
                    assertPrec("384.643954245339644320", diff);
                  });
                  it("THEN Moc Fee Flow Fee Token balance increase 24.03 ((100.18 + 200.28 + 300.43) * 8%) * 50%)", async function () {
                    // 4 => 100.18 AC0 * 0.08 TCandTPRedeemFee * 0.5
                    // 8.01 => 200.28 AC1 * 0.08 TCandTPRedeemFee * 0.5
                    // 12.01 => 300.43 AC2 * 0.08 TCandTPRedeemFee * 0.5
                    const mocFeeFlowActualFeeTokenBalance = await feeToken.balanceOf(mocFeeFlowAddress);
                    assertPrec("24.036226231576781124", mocFeeFlowActualFeeTokenBalance);
                  });
                  it("THEN a TCandTPRedeemed event is emitted by bucket 0 queue", async function () {
                    // i: 0
                    // sender: alice
                    // receiver: alice
                    // qTC: 100 TC
                    // qTP: 29.93 TP
                    // qAC: 100.18 AC - 8% for Moc Fee Flow
                    // qACtoRedeemTC: 100 AC
                    // qACtoRedeemTP: 0.127361846428058939 AC
                    // qACfee: %8 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      alice,
                      alice,
                      pEth(100),
                      pEth("29.930033910593850770"),
                      pEth("92.117172898713814224"),
                      pEth(100),
                      pEth("0.127361846428058939"),
                      pEth("8.010188947714244715"),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TCandTPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCandTPRedeemed event is emitted by bucket 1 queue", async function () {
                    // i: 1
                    // sender: alice
                    // receiver: bob
                    // qTC: 200 TC
                    // qTP: 1.01 TP
                    // qAC: 200.38 AC - 8% for Moc Fee Flow
                    // qACtoRedeemTC: 200 AC
                    // qACtoRedeemTP: 0.385601344514757078 AC
                    // qACfee: %8 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      alice,
                      bob,
                      pEth(200),
                      pEth("1.012203529351237330"),
                      pEth("184.354753236953576512"),
                      pEth(200),
                      pEth("0.385601344514757078"),
                      pEth("16.030848107561180566"),
                      0,
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TCandTPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCandTPRedeemed event is emitted by bucket 2 queue", async function () {
                    // i: 2
                    // sender: alice
                    // receiver: alice
                    // qTC: 300 TC
                    // qTP: 216.22 TP
                    // qAC: 300.69 AC - 8% for Moc Fee Flow - 10% for vendor
                    // qACtoRedeemTC: 300 AC
                    // qACtoRedeemTP: 0.694082420126562740 AC
                    // qACfee: %8 AC
                    // qFeeToken: 0
                    // qACVendorMarkup: 10% qAC
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[2].target.toString(),
                      alice,
                      alice,
                      pEth(300),
                      pEth("216.225182733961002086"),
                      pEth("246.569147584503781447"),
                      pEth(300),
                      pEth("0.694082420126562740"),
                      pEth("24.055526593610125019"),
                      0,
                      pEth("30.069408242012656274"),
                      0,
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TCandTPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCandTPRedeemed event using Fee Token is emitted by bucket 0 queue", async function () {
                    // i: 1
                    // sender: charlie
                    // receiver: charlie
                    // qTC: 100 TC
                    // qTP: 0.95 TP
                    // qAC: 100.18 AC
                    // qACtoRedeemTC: 100 AC
                    // qACtoRedeemTP: 0.182653268454358616 AC
                    // qACfee: 0
                    // qFeeToken: 100.18 (0.8% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[1].target.toString(),
                      charlie,
                      charlie,
                      pEth(100),
                      pEth("0.958929659385382734"),
                      pEth("100.182653268454358616"),
                      pEth(100),
                      pEth("0.182653268454358616"),
                      0,
                      pEth("4.007306130738174344"),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[0].mocQueue, "TCandTPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCandTPRedeemed event using Fee Token is emitted by bucket 1 queue", async function () {
                    // i: 0
                    // sender: charlie
                    // receiver: bob
                    // qTC: 200 TC
                    // qTP: 33.98 TP
                    // qAC: 200.28 AC
                    // qACtoRedeemTC: 200 AC
                    // qACtoRedeemTP: 0.289201008386067808 AC
                    // qACfee: 0
                    // qFeeToken: 200.28 (0.8% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 0
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      bob,
                      pEth(200),
                      pEth("33.981118485362967521"),
                      pEth("200.289201008386067808"),
                      pEth(200),
                      pEth("0.289201008386067808"),
                      0,
                      pEth("8.011568040335442712"),
                      0,
                      0,
                      noVendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[1].mocQueue, "TCandTPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN a TCandTPRedeemed event using Fee Token is emitted by bucket 2 queue", async function () {
                    // i: 0
                    // sender: charlie
                    // receiver: charlie
                    // qTC: 300 TC
                    // qTP: 33.98 TP
                    // qAC: 300.43 AC
                    // qACtoRedeemTC: 300 AC
                    // qACtoRedeemTP: 0.433801512579101712 AC
                    // qACfee: 0
                    // qFeeToken: 300.43 (0.8% * 50%)
                    // qACVendorMarkup: 0
                    // qFeeTokenVendorMarkup: 300.43 * 10%
                    const args = [
                      tps[0].target.toString(),
                      charlie,
                      charlie,
                      pEth(300),
                      pEth("33.981118485362967515"),
                      pEth("300.433801512579101712"),
                      pEth(300),
                      pEth("0.433801512579101712"),
                      0,
                      pEth("12.017352060503164068"),
                      0,
                      pEth("30.043380151257910171"),
                      vendor,
                    ];
                    await expect(executionTx)
                      .to.emit(buckets[2].mocQueue, "TCandTPRedeemed")
                      .withArgs(...args, anyValue); // operID is not relevant here
                  });
                  it("THEN relation between combined coverage and combined ctargemaCA remains the same", async function () {
                    assertPrec(cglbRelationBefore, await getCglbRelation(), undefined, 100);
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
