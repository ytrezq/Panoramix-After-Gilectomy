import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { expect } from "chai";
import { resetFork, timedDescribe } from "../../helpers/utils";
import { GovernorMock, IMocV1, IMocV1__factory, TVLRatioSourceV1 } from "../../../typechain";
import { assertPrec } from "../../helpers/assertHelper";

timedDescribe("Feature: MocTokenAllocator V1 - rsk fork", function () {
  let deployer: Address;
  let governor: GovernorMock;
  let tvlRatioSourceV1: TVLRatioSourceV1;
  let mocV1: IMocV1;
  const MocStateV1 = "0xb9C42EFc8ec54490a37cA91c423F7285Fa01e257";
  const tcYeldRecipient = "0x0000000000000000000000000000000000000001";
  const tpYeldRecipient = "0x0000000000000000000000000000000000000011";

  describe("GIVEN the Moc V1 protocol deployed in mainnet", () => {
    before(async () => {
      // use mainnet fork
      await resetFork(process.env["RSK_MAINNET_RPC"] || "https://public-node.rsk.co", 7609600);
      ({ deployer } = await getNamedAccounts());
      const signer = await ethers.getSigner(deployer);

      const GovernorMockFactory = await ethers.getContractFactory("GovernorMock");
      governor = await GovernorMockFactory.deploy();

      mocV1 = IMocV1__factory.connect(MocStateV1, signer);
    });
    describe("WHEN metrics are requested", function () {
      it("THEN the TVL is 1203.77 btc and the LckAC is 32.48 btc", async function () {
        const tvl = await mocV1.collateralRbtcInSystem();
        const lckAC = await mocV1.globalLockedBitcoin();
        assertPrec(tvl, "1203.774439150997780386");
        assertPrec(lckAC, "32.486919845585191383");
      });
      it("THEN btc price is 107548 usd and the ema adjusted is 90501.71 usd", async function () {
        const btcPrice = await mocV1.getBitcoinPrice();
        const bcons = await mocV1.getBcons();
        assertPrec(btcPrice, 107548);
        assertPrec(bcons, "90501.710202963707099144");
      });
      it("THEN global coverage is 37.05 and target coverage is 4", async function () {
        const coverage = await mocV1.globalCoverage();
        const targetCoverage = await mocV1.cobj();
        assertPrec(coverage, "37.054126549168208003");
        assertPrec(targetCoverage, 4);
      });
    });
    describe("AND a TVLRatioSourceV1 is deployed", function () {
      before(async function () {
        const TVLRatioSourceFactory = await ethers.getContractFactory("TVLRatioSourceV1");
        tvlRatioSourceV1 = await TVLRatioSourceFactory.deploy(
          governor.target,
          MocStateV1,
          tcYeldRecipient,
          tpYeldRecipient,
        );
      });
      describe("WHEN checks TVL ratio source values", function () {
        it("THEN the target coverage adjusted by ema is 4.75", async function () {
          const targetCoverageAdj = await tvlRatioSourceV1.getTargetCoverageAdj();
          // targetCoverageAdj = targetCoverage * btcPrice / bcons
          // = 4 * 107548 / 90501.710202963707099144 = 4.75
          assertPrec(targetCoverageAdj, "4.753412935901760189");
        });
        it("THEN the AC available to mint is 279.57 btc", async function () {
          const availableToMint = await tvlRatioSourceV1.getAvailableToMint();
          // availableToMint = (tvl * (coverage - targetCoverageAdj)) / ((targetCoverageAdj - 1) * coverage))
          // = (1203.77 * (37.05 - 4.75)) / ((4.75 - 1) * 37.05)) = 279.57
          assertPrec(availableToMint, "279.572408373256232258");
        });
        it("THEN the TVL criteria to split is 89% for TC and 11% for TP", async function () {
          const { ratios, recipients } = await tvlRatioSourceV1.getRatio();
          expect(recipients[0]).to.be.equal(tcYeldRecipient);
          // availableToMint / availableToMint + lckAC = 279.57 / (279.57 + 32.48) = 0.895895052934284610
          assertPrec(ratios[0], "0.895895052934284610");
          expect(recipients[1]).to.be.equal(tpYeldRecipient);
          // lckAC / availableToMint + lckAC = 32.48 / (279.57 + 32.48) = 0.104104947065715390
          assertPrec(ratios[1], "0.104104947065715390");
        });
      });
    });
    after(async () => {
      await resetFork();
    });
  });
});
