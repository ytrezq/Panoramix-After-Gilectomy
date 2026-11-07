import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { expect } from "chai";
import { resetFork, timedDescribe } from "../../helpers/utils";
import { GovernorMock, IMocV2, IMocV2__factory, TPRatioSourceV2, TVLRatioSourceV2 } from "../../../typechain";
import { assertPrec } from "../../helpers/assertHelper";

timedDescribe("Feature: MocTokenAllocator V2 - rsk fork", function () {
  let deployer: Address;
  let governor: GovernorMock;
  let tvlRatioSourceV2: TVLRatioSourceV2;
  let tpRatioSourceV2: TPRatioSourceV2;
  let mocV2: IMocV2;
  let tp0: Address;
  const MocV2 = "0xA27024Ed70035E46dba712609fc2Afa1c97aA36A";
  const tcYeldRecipient = "0x0000000000000000000000000000000000000001";
  const tpYeldRecipient = "0x0000000000000000000000000000000000000011";

  describe("GIVEN the Moc V2 protocol deployed in mainnet", () => {
    before(async () => {
      // use mainnet fork
      await resetFork(process.env["RSK_MAINNET_RPC"] || "https://public-node.rsk.co", 7609600);
      ({ deployer } = await getNamedAccounts());
      const signer = await ethers.getSigner(deployer);

      const GovernorMockFactory = await ethers.getContractFactory("GovernorMock");
      governor = await GovernorMockFactory.deploy();

      mocV2 = IMocV2__factory.connect(MocV2, signer);
      tp0 = await mocV2.tpTokens(0);
    });
    describe("WHEN metrics are requested", function () {
      it("THEN the TVL is 151649348 rif and the LckAC is 20388140 rif", async function () {
        const tvl = await mocV2.getTotalACavailable();
        const lckAC = await mocV2.getLckAC();
        assertPrec(tvl, "151649348.814813351115572452");
        assertPrec(lckAC, "20388140.337260571818513698");
      });
      it("THEN global coverage is 7.43 and target coverage is 5.5", async function () {
        const coverage = await mocV2.getCglb();
        const targetCoverage = await mocV2.calcCtargemaCA();
        assertPrec(coverage, "7.438115801943196510");
        assertPrec(targetCoverage, 5.5);
      });
    });
    describe("AND TVLRatioSourceV2 is deployed", function () {
      before(async function () {
        const TVLRatioSourceFactory = await ethers.getContractFactory("TVLRatioSourceV2");
        tvlRatioSourceV2 = await TVLRatioSourceFactory.deploy(governor.target, MocV2, tcYeldRecipient, tpYeldRecipient);
      });
      describe("WHEN checks TVL ratio source values", function () {
        it("THEN the AC available to mint is 8781017 rif", async function () {
          const availableToMint = await tvlRatioSourceV2.getAvailableToMint();
          // availableToMint = (tvl * (coverage - targetCoverageAdj)) / ((targetCoverageAdj - 1) * coverage))
          // = (151649348 * (7.43 - 5.5)) / ((5.5 - 1) * 7.43)) = 8781017
          assertPrec(availableToMint, "8781017.102195601357543051");
        });
        it("THEN the TVL criteria to split is 30% for TC and 7'% for TP", async function () {
          const { ratios, recipients } = await tvlRatioSourceV2.getRatio();
          expect(recipients[0]).to.be.equal(tcYeldRecipient);
          // availableToMint / availableToMint + lckAC = 8781017 / (8781017 + 20388140) = 0.301037735506127590
          assertPrec(ratios[0], "0.301037735506127590");
          expect(recipients[1]).to.be.equal(tpYeldRecipient);
          // lckAC / availableToMint + lckAC = 20388140 / (8781017 + 20388140 = 0.698962264493872410
          assertPrec(ratios[1], "0.698962264493872410");
        });
      });
    });
    describe("AND TPRatioSourceV1 is deployed", function () {
      before(async function () {
        const TPRatioSourceFactory = await ethers.getContractFactory("TPRatioSourceV2");
        tpRatioSourceV2 = await TPRatioSourceFactory.deploy(governor.target, MocV2, [tp0], [tpYeldRecipient]);
      });
      describe("WHEN checks TP ratio source values", function () {
        it("THEN the total lckAC is 20388140 AC0", async function () {
          const lckAC = await tpRatioSourceV2.getTotalShares();
          assertPrec(lckAC, "20388140.337260571818513698");
        });
        it("THEN the lckAC for TP 0 is 20388140", async function () {
          const lckAC = await tpRatioSourceV2.getShareArray();
          const lckAC0 = await tpRatioSourceV2.getShareByToken(tp0);
          assertPrec(lckAC[0], lckAC0);
          assertPrec(lckAC[0], "20388140.337260571818513698");
        });
        it("THEN the TP criteria to split is 100% for TP0", async function () {
          const { ratios, recipients } = await tpRatioSourceV2.getRatio();
          expect(recipients[0]).to.be.equal(tpYeldRecipient);
          assertPrec(ratios[0], 1);
        });
      });
    });
    after(async () => {
      await resetFork();
    });
  });
});
