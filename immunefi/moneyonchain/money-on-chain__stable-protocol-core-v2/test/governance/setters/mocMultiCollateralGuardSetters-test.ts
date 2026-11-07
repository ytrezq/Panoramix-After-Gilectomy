import { expect } from "chai";
import { ethers } from "hardhat";
import { fixtureDeployedMocCoinbase } from "../../coinbase/fixture";
import { GovernorMock, GovernorMock__factory, MocMultiCollateralGuard } from "../../../typechain";
import { CONSTANTS, ERRORS } from "../../helpers/utils";

const fixtureDeploy = fixtureDeployedMocCoinbase(1);

describe("Feature: Verify all MocMultiCollateralGuard config settings are protected by governance", () => {
  let governorMock: GovernorMock;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let liqParams: any;
  let mocSwappers: any;
  before(async () => {
    ({ mocMultiCollateralGuard } = await fixtureDeploy());
    const governorAddress = await mocMultiCollateralGuard.governor();
    const [signer] = await ethers.getSigners();
    governorMock = GovernorMock__factory.connect(governorAddress, signer);

    const baseBucket = await mocMultiCollateralGuard.buckets(0);
    liqParams = {
      acCoinbasePriceProvider: await mocMultiCollateralGuard.acCoinbasePriceProvider(baseBucket),
      rebalanceExecFeeRecipient: await mocMultiCollateralGuard.rebalanceExecFeeRecipient(baseBucket),
      rtcThrld: await mocMultiCollateralGuard.rtcThrld(baseBucket),
      microLiquidationThrld: await mocMultiCollateralGuard.microLiquidationThrld(baseBucket),
      penaltyRate: await mocMultiCollateralGuard.penaltyRate(baseBucket),
    };
    mocSwappers = Array(Number(await mocMultiCollateralGuard.getBucketAmount())).fill(CONSTANTS.ZERO_ADDRESS); // mocSwapper is irrelevant here
  });

  describe("GIVEN the Governor has authorized the change", () => {
    before(async () => {
      await governorMock.setIsAuthorized(true);
    });
    describe(`WHEN add bucket is invoked`, () => {
      before(async () => {
        await mocMultiCollateralGuard.addBucket(governorMock.target.toString(), liqParams, mocSwappers);
      });
      it("THEN the new value is assigned", async function () {
        const lastBucket = (await mocMultiCollateralGuard.getBucketAmount()) - 1n;
        expect(await mocMultiCollateralGuard.buckets(lastBucket)).to.be.equal(governorMock.target.toString());
      });
    });
    describe(`WHEN setMaxOperPerBatch is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocMultiCollateralGuard.setMaxOperPerBatch(20);
        expect(await mocMultiCollateralGuard.maxOperPerBatch()).to.be.equal(20);
      });
    });
    describe(`WHEN setMicroLiquidationExecCost is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocMultiCollateralGuard.setMicroLiquidationExecCost(21);
        expect(await mocMultiCollateralGuard.microLiquidationExecCost()).to.be.equal(21);
      });
    });
    describe(`WHEN setLiquidationExecCost is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocMultiCollateralGuard.setLiquidationExecCost(22);
        expect(await mocMultiCollateralGuard.liquidationExecCost()).to.be.equal(22);
      });
    });
    describe(`WHEN setCoinbaseExecFeeRecipient is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocMultiCollateralGuard.setCoinbaseExecFeeRecipient(governorMock.target);
        expect(await mocMultiCollateralGuard.coinbaseExecFeeRecipient()).to.be.equal(governorMock.target);
      });
    });
    describe(`WHEN setMocSwapper is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        const bucketA = await mocMultiCollateralGuard.buckets(0);
        const bucketB = await mocMultiCollateralGuard.buckets(1);
        const mocSwapper = governorMock.target.toString();
        await mocMultiCollateralGuard.setMocSwapper(bucketA, bucketB, mocSwapper);
        expect(await mocMultiCollateralGuard.mocSwappers(bucketA, bucketB)).to.be.equal(mocSwapper);
        expect(await mocMultiCollateralGuard.mocSwappers(bucketB, bucketA)).to.be.equal(mocSwapper);
      });
    });
  });
  describe("GIVEN the Governor has not authorized the change", () => {
    let expectRevertNotAuthorized: (it: any) => any;
    before(async () => {
      await governorMock.setIsAuthorized(false);
      expectRevertNotAuthorized = it =>
        expect(it).to.be.revertedWithCustomError(mocMultiCollateralGuard, ERRORS.NOT_AUTH_CHANGER);
    });
    describe("WHEN setMaxOperPerBatch is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocMultiCollateralGuard.setMaxOperPerBatch(42));
      });
    });
    describe("WHEN registerBucket is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(
          mocMultiCollateralGuard.addBucket(governorMock.target.toString(), liqParams, mocSwappers),
        );
      });
    });
    describe("WHEN setMicroLiquidationExecCost is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocMultiCollateralGuard.setMicroLiquidationExecCost(21));
      });
    });
    describe("WHEN setLiquidationExecCost is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocMultiCollateralGuard.setLiquidationExecCost(22));
      });
    });
    describe("WHEN setCoinbaseExecFeeRecipient is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocMultiCollateralGuard.setCoinbaseExecFeeRecipient(governorMock.target));
      });
    });
    describe(`WHEN setMocSwapper is invoked`, () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        const bucketA = await mocMultiCollateralGuard.buckets(0);
        const bucketB = await mocMultiCollateralGuard.buckets(1);
        const mocSwapper = governorMock.target.toString();
        await expectRevertNotAuthorized(mocMultiCollateralGuard.setMocSwapper(bucketA, bucketB, mocSwapper));
      });
    });
  });
});
