import { expect } from "chai";
import { ContractTransactionResponse } from "ethers";
import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { assertPrec } from "../../helpers/assertHelper";
import { mocFunctionsRC20 } from "../../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../../helpers/mocFunctionsCoinbase";
import { CONSTANTS, ERRORS, ethersGetBalance, ethersSendValue, pEth, timedDescribe } from "../../helpers/utils";
import {
  ERC20Mock,
  GovernorMock,
  GovernorMock__factory,
  MocMultiCollateralGuard,
  MocTokenAllocator,
  TCRatioSourceV3,
  TPRatioSourceV3,
  TVLRatioSourceV3,
} from "../../../typechain";
import { fixtureCase1 } from "../fixture";

timedDescribe("Feature: multicollateral mint Collateral Tokens", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(3);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let feeToken: ERC20Mock;
  let alice: Address;
  let governor: GovernorMock;

  describe("GIVEN 3 Moc implementations deployed with 3 TPs and some operations executed", function () {
    before(async function () {
      ({ alice } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixtureCase1);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard, feeToken } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });

      const [signer] = await ethers.getSigners();
      governor = GovernorMock__factory.connect(await buckets[0].mocImpl.governor(), signer);

      // add collateral to every buckets
      await Promise.all(mocFunctions.map(fncs => fncs.mintTC({ from: alice, qTC: 10000, execute: false })));
      await mocFunctions[0].executeQueue();

      await Promise.all([
        mocFunctions[0].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500, execute: false }), // 100 AC0
        mocFunctions[0].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 525, execute: false }), // 100 AC0
        mocFunctions[0].mintTP({ tp: tps[2].target.toString(), from: alice, qTP: 93458, execute: false }), // 100 AC0

        mocFunctions[1].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500 * 2, execute: false }), // 400 AC1
        mocFunctions[1].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 525 / 2, execute: false }), // 100 AC1
        mocFunctions[1].mintTP({ tp: tps[2].target.toString(), from: alice, qTP: 93458 / 2, execute: false }), // 100 AC1

        mocFunctions[2].mintTP({ tp: tps[0].target.toString(), from: alice, qTP: 23500 * 1.5, execute: false }), // 450 AC2
        mocFunctions[2].mintTP({ tp: tps[1].target.toString(), from: alice, qTP: 525 / 2, execute: false }), // 150 AC1
        mocFunctions[2].mintTP({ tp: tps[2].target.toString(), from: alice, qTP: 93458, execute: false }), // 300 AC2
      ]);

      await mocFunctions[0].executeQueue();
    });
    describe("WHEN metrics are requested", function () {
      it("THEN in bucket 0 the TVL is 10300 and the LckAC is 300", async function () {
        const tvl = await buckets[0].mocImpl.getTotalACavailable();
        const lckAC = await buckets[0].mocImpl.getLckAC();
        assertPrec(tvl, 10300);
        assertPrec(lckAC, 300);
      });
      it("THEN in bucket 1 the TVL is 10600 and the LckAC is 600", async function () {
        const tvl = await buckets[1].mocImpl.getTotalACavailable();
        const lckAC = await buckets[1].mocImpl.getLckAC();
        assertPrec(tvl, 10600);
        assertPrec(lckAC, 600);
      });
      it("THEN in bucket 2 the TVL is 10900 and the LckAC is 900", async function () {
        const tvl = await buckets[2].mocImpl.getTotalACavailable();
        const lckAC = await buckets[2].mocImpl.getLckAC();
        assertPrec(tvl, 10900, undefined, 1);
        assertPrec(lckAC, 900, undefined, 1);
      });
      it("THEN normalization factors are 1, 0.5 and 0.33", async function () {
        const normFactors = await mocMultiCollateralGuard.getNormalizationFactors();
        assertPrec(normFactors[0], 1);
        assertPrec(normFactors[1], 0.5);
        assertPrec(normFactors[2], "0.333333333333333333");
      });
    });
    describe("AND a MocTokenAllocator is deployed", function () {
      const tcRecipients = [
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        "0x0000000000000000000000000000000000000003",
      ];
      const tpRecipients = [
        "0x0000000000000000000000000000000000000011",
        "0x0000000000000000000000000000000000000012",
        "0x0000000000000000000000000000000000000013",
      ];
      let mocTVLAllocator: MocTokenAllocator;
      let mocTCAllocator: MocTokenAllocator;
      let mocTPAllocator: MocTokenAllocator;
      let tvlRatioSource: TVLRatioSourceV3;
      let tcRatioSource: TCRatioSourceV3;
      let tpRatioSource: TPRatioSourceV3;
      before(async function () {
        const tcAddresses = await Promise.all(buckets.map(bucket => bucket.mocImpl.tcToken()));
        const tpAddresses = await Promise.all(tps.map(tp => tp.target));
        const MocTokenAllocatorFactory = await ethers.getContractFactory("MocTokenAllocator");
        const TVLRatioSourceFactory = await ethers.getContractFactory("TVLRatioSourceV3");
        const TPRatioSourceFactory = await ethers.getContractFactory("TPRatioSourceV3");
        const TCRatioSourceFactory = await ethers.getContractFactory("TCRatioSourceV3");

        tcRatioSource = await TCRatioSourceFactory.deploy(
          governor,
          mocMultiCollateralGuard.target,
          tcAddresses,
          tcRecipients,
        );
        mocTCAllocator = await MocTokenAllocatorFactory.deploy(governor, tcRatioSource.target);

        tpRatioSource = await TPRatioSourceFactory.deploy(
          governor,
          mocMultiCollateralGuard.target,
          tpAddresses,
          tpRecipients,
        );
        mocTPAllocator = await MocTokenAllocatorFactory.deploy(governor, tpRatioSource.target);

        tvlRatioSource = await TVLRatioSourceFactory.deploy(
          governor,
          mocMultiCollateralGuard.target,
          mocTCAllocator.target,
          mocTPAllocator.target,
        );
        mocTVLAllocator = await MocTokenAllocatorFactory.deploy(governor, tvlRatioSource.target);
      });
      describe("WHEN checks TVL ratio source values", function () {
        it("THEN the total lckAC normalized is 899.99 AC0 and the TVL is 19233.33 AC0", async function () {
          const totalLckAC = await tvlRatioSource.getLckAC();
          const totalTVL = await tvlRatioSource.getTVL();
          // totalLckAC = 300 * 1 + 600 * 0.5 + 900 * 0.33 = 300 + 300 + 299.99 = 899.99
          assertPrec(totalLckAC, "899.999999999999999700");
          // totalTVL = 10300 * 1 + 10600 * 0.5 + 10900 * 0.33 = 10300 + 5300 + 3633.33 = 19233.33
          assertPrec(totalTVL, "19233.333333333333329700");
        });
        it("THEN the combined coverage is 21.3 and the combined ctargemaCA is 4.48", async function () {
          const coverage = await tvlRatioSource.getCoverage();
          const ctargemaCA = await tvlRatioSource.getTargetCoverageAdj();
          // coverage = totalTVL / totalLckAC = 19233.33 / 899.99 = 21.370370370370370373
          assertPrec(coverage, "21.370370370370370373");
          assertPrec(ctargemaCA, "4.484952708030921692");
        });
        it("THEN the AC available to mint normalized is 4360.71 AC0", async function () {
          const availableToMint = await tvlRatioSource.getAvailableToMint();
          // availableToMint = (tvl * (coverage - ctargemaCA)) / ((ctargemaCA - 1) * coverage))
          // = (19233.33 * (21.37 - 4.48)) / ((4.48 - 1) * 21.37)
          assertPrec(availableToMint, "4360.712230351064840862");
        });
        it("THEN the TVL criteria to split is 83% for TC and 17% for TP", async function () {
          const { ratios, recipients } = await mocTVLAllocator.getRatio();
          expect(recipients[0]).to.be.equal(mocTCAllocator.target);
          // availableToMint / availableToMint + lckAC = 4360.71 / (4360.71 + 899.99) = 0.828920503423936572
          assertPrec(ratios[0], "0.828920503423936572");
          expect(recipients[1]).to.be.equal(mocTPAllocator.target);
          // lckAC / availableToMint + lckAC = 899.99 / (4360.71 + 899.99) = 0.171079496576063428
          assertPrec(ratios[1], "0.171079496576063428");
        });
      });
      describe("WHEN checks TC ratio source values", function () {
        it("THEN the ac available to mint normalized for bucket 0 is 2203.52 AC0", async function () {
          const availableToMint = await tcRatioSource.getShareArray();
          const availableToMint0 = await tcRatioSource.getShareByToken(await buckets[0].mocImpl.tcToken());
          const ctargema = await buckets[0].mocImpl.getCtargemaCA();
          assertPrec(availableToMint[0], availableToMint0);
          assertPrec(ctargema, "4.538191457426098410");
          // availableToMint = (acAvailable - lckAC) / ctargemaCA = (10300 - 300) / 4.538 = 2203.52
          assertPrec(availableToMint[0], "2203.520960676182248221");
        });
        it("THEN the ac available to mint normalized for bucket 1 is 1090.9 AC0", async function () {
          const availableToMint = await tcRatioSource.getShareArray();
          const availableToMint1 = await tcRatioSource.getShareByToken(await buckets[1].mocImpl.tcToken());
          const ctargema = await buckets[1].mocImpl.getCtargemaCA();
          assertPrec(availableToMint[1], availableToMint1);
          assertPrec(ctargema, "4.583333333333333333");
          // availableToMint = (acAvailable - lckAC) * nf / ctargemaCA = (10600 - 600) * 0.5 / 4.583 = 1090.9
          assertPrec(availableToMint[1], "1090.909090909090909170");
        });
        it("THEN the ac available to mint normalized for bucket 2 is 769.23 AC0", async function () {
          const availableToMint = await tcRatioSource.getShareArray();
          const availableToMint2 = await tcRatioSource.getShareByToken(await buckets[2].mocImpl.tcToken());
          const ctargema = await buckets[2].mocImpl.getCtargemaCA();
          assertPrec(availableToMint[2], availableToMint2);
          assertPrec(ctargema, "4.333333333333333333");
          // availableToMint = (acAvailable - lckAC) * nf / ctargemaCA = (10900 - 900) * 0.33 / 4.333 = 769.23
          assertPrec(availableToMint[2], "769.230769230769230059");
        });
        it("THEN the total AC available to mint normalized is 4063.66 AC0", async function () {
          const availableToMint = await tcRatioSource.getTotalShares();
          // availableToMint = 2203.52 + 1090.9 + 769.23 = 4063.66
          assertPrec(availableToMint, "4063.660820816042387450");
        });
        it("THEN the TC criteria to split is 54% for AC0, 26% for AC1 and 18% for AC2", async function () {
          const { ratios, recipients } = await mocTCAllocator.getRatio();
          expect(recipients[0]).to.be.equal(tcRecipients[0]);
          // 2203.52 / 4063.66 = 0.54
          assertPrec(ratios[0], "0.542250216698371761");
          expect(recipients[1]).to.be.equal(tcRecipients[1]);
          // 1090.9 / 4063.66 = 0.26
          assertPrec(ratios[1], "0.268454760131781974");
          expect(recipients[2]).to.be.equal(tcRecipients[2]);
          // 769.23 / 4063.66 = 0.18
          assertPrec(ratios[2], "0.189295023169846263");
        });
      });
      describe("WHEN checks TP ratio source values", function () {
        it("THEN the lckAC normalized for TP 0 is 450 AC0", async function () {
          const lckAC = await tpRatioSource.getShareArray();
          const lckAC0 = await tpRatioSource.getShareByToken(await tps[0].target);
          assertPrec(lckAC[0], lckAC0);
          // lckAC = lckAC0TP0 * nf + lckAC1TP0 * nf + lckAC2TP0 * nf = 100 * 1 + 400 * 0.5 + 450 * 0.33  = 449.99
          assertPrec(lckAC[0], "449.999999999999999850");
        });
        it("THEN the lckAC normalized for TP 1 is 200 AC0", async function () {
          const lckAC = await tpRatioSource.getShareArray();
          const lckAC1 = await tpRatioSource.getShareByToken(await tps[1].target);
          assertPrec(lckAC[1], lckAC1);
          // lckAC = lckAC0TP1 * nf + lckAC1TP1 * nf + lckAC2TP1 * nf = 100 * 1 + 100 * 0.5 + 150 * 0.33  = 199.99
          assertPrec(lckAC[1], "199.999999999999999950");
        });
        it("THEN the lckAC normalized for TP 2 is 249 AC0", async function () {
          const lckAC = await tpRatioSource.getShareArray();
          const lckAC2 = await tpRatioSource.getShareByToken(await tps[2].target);
          assertPrec(lckAC[2], lckAC2);
          // lckAC = lckAC0TP2 * nf + lckAC1TP2 * nf + lckAC2TP2 * nf = 100 * 1 + 100 * 0.5 + 300 * 0.33  = 249.99
          assertPrec(lckAC[2], "249.999999999999999900");
        });
        it("THEN the total lckAC normalized is 900 AC0", async function () {
          const lckAC = await tpRatioSource.getTotalShares();
          // lckAC = 449.99 + 199.99 + 249.99 = 899.99
          assertPrec(lckAC, "899.999999999999999700");
        });
        it("THEN the TP criteria to split is 50% for TP0, 22% for AC1 and 27% for AC2", async function () {
          const { ratios, recipients } = await mocTPAllocator.getRatio();
          expect(recipients[0]).to.be.equal(tpRecipients[0]);
          // 449.99 / 899.99 = 0.52
          assertPrec(ratios[0], 0.5);
          expect(recipients[1]).to.be.equal(tpRecipients[1]);
          // 199.99 / 899.99 = 0.22
          assertPrec(ratios[1], "0.222222222222222222");
          expect(recipients[2]).to.be.equal(tpRecipients[2]);
          // 249.99 / 899.99 = 0.27
          assertPrec(ratios[2], "0.277777777777777777");
        });
      });
      describe("AND 1000 FeeTokens are sent to the MocTVLAllocator", async function () {
        before(async function () {
          await feeToken.mint(mocTVLAllocator.target, pEth(1000));
        });
        describe("WHEN the MocTVLAllocator executes the split", async () => {
          let tx: ContractTransactionResponse;
          before(async function () {
            tx = await mocTVLAllocator.split(feeToken.target);
          });
          it("THEN TCAllocator receives 828.92 FeeTokens and TPAllocator receives 171.07", async function () {
            assertPrec(await feeToken.balanceOf(mocTCAllocator.target), "828.920503423936572");
            assertPrec(await feeToken.balanceOf(mocTPAllocator.target), "171.079496576063428");
            assertPrec(await feeToken.balanceOf(mocTVLAllocator.target), 0);
          });
          it("THEN a SplitExecuted event is emitted", async function () {
            await expect(tx)
              .to.emit(mocTVLAllocator, "SplitExecuted")
              .withArgs(
                feeToken.target,
                [mocTCAllocator.target, mocTPAllocator.target],
                [pEth("828.920503423936572"), pEth("171.079496576063428")],
              );
          });
          describe("AND the MocTCAllocator executes the split", async () => {
            before(async function () {
              tx = await mocTCAllocator.split(feeToken.target);
            });
            it("THEN TC0 receives 448.92 FeeTokens, TC1 receives 217.07 and TC2 receives 162.92", async function () {
              assertPrec(await feeToken.balanceOf(tcRecipients[0]), "449.482322607353017442");
              assertPrec(await feeToken.balanceOf(tcRecipients[1]), "222.527654914988850921");
              assertPrec(await feeToken.balanceOf(tcRecipients[2]), "156.910525901594701977");
              assertPrec(await feeToken.balanceOf(mocTCAllocator.target), 0, undefined, 2000);
            });
            it("THEN a SplitExecuted event is emitted", async function () {
              await expect(tx)
                .to.emit(mocTCAllocator, "SplitExecuted")
                .withArgs(
                  feeToken.target,
                  [tcRecipients[0], tcRecipients[1], tcRecipients[2]],
                  [pEth("449.482322607353017442"), pEth("222.527654914988850921"), pEth("156.910525901594701977")],
                );
            });
          });
          describe("AND the MocTPAllocator executes the split", async () => {
            before(async function () {
              tx = await mocTPAllocator.split(feeToken.target);
            });
            it("THEN TP0 receives 85.36 FeeTokens, TP1 receives 37.78 and TP2 receives 47.93", async function () {
              assertPrec(await feeToken.balanceOf(tpRecipients[0]), "85.539748288031714000");
              assertPrec(await feeToken.balanceOf(tpRecipients[1]), "38.017665905791872850");
              assertPrec(await feeToken.balanceOf(tpRecipients[2]), "47.522082382239840978");
              assertPrec(await feeToken.balanceOf(mocTPAllocator.target), 0, undefined, 2000);
            });
            it("THEN a SplitExecuted event is emitted", async function () {
              await expect(tx)
                .to.emit(mocTPAllocator, "SplitExecuted")
                .withArgs(
                  feeToken.target,
                  [tpRecipients[0], tpRecipients[1], tpRecipients[2]],
                  [pEth("85.539748288031714000"), pEth("38.017665905791872850"), pEth("47.522082382239840978")],
                );
            });
          });
          describe("WHEN emergency withdraw is called", async () => {
            before(async function () {
              tx = await mocTCAllocator.emergencyWithdraw(feeToken.target, alice);
            });
            it("THEN the MocTVLAllocator sends all FeeTokens to alice", async function () {
              assertPrec(await feeToken.balanceOf(alice), "0.000000000000001660");
              assertPrec(await feeToken.balanceOf(mocTVLAllocator.target), 0);
            });
            it("THEN an EmergencyWithdraw event is emitted", async function () {
              await expect(tx)
                .to.emit(mocTCAllocator, "EmergencyWithdraw")
                .withArgs(feeToken.target, alice, pEth("0.000000000000001660"));
            });
          });
        });
      });
      describe("AND 1 Coinbase is sent to the MocTVLAllocator", async function () {
        before(async function () {
          await ethersSendValue(alice, mocTVLAllocator.target.toString(), pEth(1));
        });
        describe("WHEN the MocTVLAllocator executes the split", async () => {
          before(async function () {
            await mocTVLAllocator.split(CONSTANTS.ZERO_ADDRESS);
          });
          it("THEN TCAllocator receives 0.82 Coinbase and TPAllocator receives 0.17", async function () {
            assertPrec(await ethersGetBalance(mocTCAllocator.target.toString()), "0.828920503423936572");
            assertPrec(await ethersGetBalance(mocTPAllocator.target.toString()), "0.171079496576063428");
            assertPrec(await ethersGetBalance(mocTVLAllocator.target.toString()), 0);
          });
        });
      });
      describe("WHEN governor does not authorize changes", function () {
        let expectRevertNotAuthorized: (it: any) => any;
        before(async function () {
          await governor.setIsAuthorized(false);
          expectRevertNotAuthorized = it =>
            expect(it).to.be.revertedWithCustomError(mocTVLAllocator, ERRORS.NOT_AUTH_CHANGER);
        });
        it("THEN emergencyWithdraw fails", async function () {
          await expectRevertNotAuthorized(mocTVLAllocator.emergencyWithdraw(feeToken.target, alice));
        });
        it("THEN setRatioSource fails", async function () {
          await expectRevertNotAuthorized(mocTVLAllocator.setRatioSource(feeToken.target));
        });
        it("THEN set setMocSource fails", async function () {
          await expectRevertNotAuthorized(tvlRatioSource.setMocSource(feeToken.target));
          await expectRevertNotAuthorized(tcRatioSource.setMocSource(feeToken.target));
          await expectRevertNotAuthorized(tpRatioSource.setMocSource(feeToken.target));
        });
        it("THEN setTCYeldRecipient fails", async function () {
          await expectRevertNotAuthorized(tvlRatioSource.setTCYeldRecipient(feeToken.target));
        });
        it("THEN setTPYeldRecipient fails", async function () {
          await expectRevertNotAuthorized(tvlRatioSource.setTPYeldRecipient(feeToken.target));
        });
        it("THEN setRecipient fails", async function () {
          await expectRevertNotAuthorized(tcRatioSource.setYeldRecipient(feeToken.target, feeToken.target));
          await expectRevertNotAuthorized(tpRatioSource.setYeldRecipient(feeToken.target, feeToken.target));
        });
      });
      describe("WHEN governor authorizes changes", function () {
        before(async function () {
          await governor.setIsAuthorized(true);
        });
        it("THEN setRatioSource succeeds", async function () {
          await mocTVLAllocator.setRatioSource(feeToken.target);
          expect(await mocTVLAllocator.ratioSource()).to.be.equal(feeToken.target);
        });
        it("THEN set setMocSource succeeds", async function () {
          await tvlRatioSource.setMocSource(feeToken.target);
          await tcRatioSource.setMocSource(feeToken.target);
          await tpRatioSource.setMocSource(feeToken.target);
          expect(await tvlRatioSource.mocSource()).to.be.equal(feeToken.target);
          expect(await tcRatioSource.mocSource()).to.be.equal(feeToken.target);
          expect(await tpRatioSource.mocSource()).to.be.equal(feeToken.target);
        });
        it("THEN setTCYeldRecipient succeeds", async function () {
          await tvlRatioSource.setTCYeldRecipient(feeToken.target);
          expect(await tvlRatioSource.tcYeldRecipient()).to.be.equal(feeToken.target);
        });
        it("THEN setTPYeldRecipient succeeds", async function () {
          await tvlRatioSource.setTPYeldRecipient(feeToken.target);
          expect(await tvlRatioSource.tpYeldRecipient()).to.be.equal(feeToken.target);
        });
        it("THEN setRecipient succeeds", async function () {
          await tcRatioSource.setYeldRecipient(feeToken.target, alice);
          await tpRatioSource.setYeldRecipient(feeToken.target, alice);
          expect(await tcRatioSource.yeldRecipients(feeToken.target)).to.be.equal(alice);
          expect(await tpRatioSource.yeldRecipients(feeToken.target)).to.be.equal(alice);
        });
      });
    });
  });
});
