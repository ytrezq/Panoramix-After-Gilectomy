import { expect } from "chai";
import hre, { ethers, getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { fixtureDeployedMocCoinbase } from "../../coinbase/fixture";
import { GovernorMock, GovernorMock__factory, MocCACoinbase } from "../../../typechain";
import { ERRORS, getNetworkDeployParams, timedDescribe } from "../../helpers/utils";

const fixtureDeploy = fixtureDeployedMocCoinbase(1);

timedDescribe("Feature: Verify all MocCore config settings are protected by governance", () => {
  let mocProxy: MocCACoinbase;
  let governorMock: GovernorMock;
  let mockAddress: Address;
  let pauser: Address;
  const { feeParams } = getNetworkDeployParams(hre);
  let expectOperationsFee: (expectedFees: any) => any;
  let setFeeTokenParams: (feeTokenAddress: Address, feeTokenPriceProviderAddress: Address) => Promise<any>;
  let setCoverageThresholds: (protThrld: bigint | number, liqThrld: bigint | number) => Promise<any>;
  let setSuccessFeeParams: (
    successFee: bigint | number,
    appreciationFactor: bigint | number,
    mocAppreciationBeneficiaryAddress?: Address,
  ) => Promise<any>;
  let setTCInterestParams: (
    tcInterestCollectorAddress: Address,
    tcInterestRate: bigint | number,
    tcInterestPaymentTimeSpan: bigint | number,
  ) => Promise<any>;
  let setFluxCapacitorParams: (
    maxAbsoluteOpProviderAddress: Address,
    maxOpDiffProviderAddress: Address,
    decayTimeSpan: bigint | number,
  ) => Promise<any>;

  before(async () => {
    ({ mocImpl: mocProxy } = await fixtureDeploy());
    const governorAddress = await mocProxy.governor();
    const [signer] = await ethers.getSigners();
    governorMock = GovernorMock__factory.connect(governorAddress, signer);
    mockAddress = governorAddress;
    ({ alice: pauser } = await getNamedAccounts());
    await mocProxy.setPauser(pauser);

    expectOperationsFee = async (expectedFees: any) => {
      const [
        feeRetainer,
        feeTokenPct,
        tcMintFee,
        tcRedeemFee,
        swapTCforTPFee,
        swapTPforTCFee,
        swapTPforTPFee,
        mintTCandTPFee,
        redeemTCandTPFee,
      ] = await Promise.all([
        mocProxy.feeRetainer(),
        mocProxy.feeTokenPct(),
        mocProxy.tcMintFee(),
        mocProxy.tcRedeemFee(),
        mocProxy.swapTCforTPFee(),
        mocProxy.swapTPforTCFee(),
        mocProxy.swapTPforTPFee(),
        mocProxy.mintTCandTPFee(),
        mocProxy.redeemTCandTPFee(),
      ]);

      const feeParams = {
        feeRetainer,
        feeTokenPct,
        tcMintFee,
        tcRedeemFee,
        swapTCforTPFee,
        swapTPforTCFee,
        swapTPforTPFee,
        mintTCandTPFee,
        redeemTCandTPFee,
      };

      expect(expectedFees).to.be.eq(feeParams);
    };

    setFeeTokenParams = async (feeTokenAddress, feeTokenPriceProviderAddress) =>
      mocProxy.setFeeTokenParams(feeTokenAddress, feeTokenPriceProviderAddress);
    setCoverageThresholds = async (protThrld, liqThrld) => mocProxy.setCoverageThresholds(protThrld, liqThrld);
    setSuccessFeeParams = async (successFee, appreciationFactor, mocAppreciationBeneficiaryAddress = mockAddress) =>
      mocProxy.setSuccessFeeParams(successFee, appreciationFactor, mocAppreciationBeneficiaryAddress);
    setTCInterestParams = async (tcInterestCollectorAddress, tcInterestRate, tcInterestPaymentTimeSpan) =>
      mocProxy.setTCInterestParams(tcInterestCollectorAddress, tcInterestRate, tcInterestPaymentTimeSpan);
    setFluxCapacitorParams = async (maxAbsoluteOpProviderAddress, maxOpDiffProviderAddress, decayTimeSpan) =>
      mocProxy.setFluxCapacitorParams(maxAbsoluteOpProviderAddress, maxOpDiffProviderAddress, decayTimeSpan);
  });

  describe("GIVEN the Governor has authorized the change", () => {
    before(async () => {
      await governorMock.setIsAuthorized(true);
    });
    // MocEma
    describe(`WHEN setEmaCalculationTimeSpan is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocProxy.setEmaCalculationTimeSpan(40);
        expect(await mocProxy.emaCalculationTimeSpan()).to.be.equal(40);
      });
    });
    // MocSettlement
    describe(`WHEN setSettlementTimeSpan is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocProxy.setSettlementTimeSpan(41);
        expect(await mocProxy.settlementTimeSpan()).to.be.equal(41);
      });
    });
    // MocBaseBucket
    describe(`WHEN setOperationsFee is invoked`, () => {
      Object.entries(feeParams).forEach(([key]) => {
        describe(`AND setOperationsFee is invoked to update ${key}`, () => {
          it(`THEN only ${key} is updated`, async function () {
            const feeParamsToUpdate = Object.assign({}, feeParams, { [key]: 42 });
            await mocProxy.setOperationsFee(feeParamsToUpdate);
            expectOperationsFee(feeParamsToUpdate);
          });
        });
      });
    });
    describe(`WHEN setMocFeeFlowAddress is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocProxy.setMocFeeFlowAddress(mockAddress);
        expect(await mocProxy.mocFeeFlowAddress()).to.be.equal(mockAddress);
      });
    });
    describe(`WHEN setFeeTokenParams is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await setFeeTokenParams(mockAddress, await mocProxy.feeTokenPriceProvider());
        expect(await mocProxy.feeToken()).to.be.equal(mockAddress);
      });
      it("THEN the fee token price provider can be updated", async function () {
        await setFeeTokenParams(await mocProxy.feeToken(), mockAddress);
        expect(await mocProxy.feeTokenPriceProvider()).to.be.equal(mockAddress);
      });
    });
    describe(`WHEN setCoverageThresholds is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await setCoverageThresholds(45, await mocProxy.liqThrld());
        expect(await mocProxy.protThrld()).to.be.equal(45);
      });
      it("THEN the liq threshold can be updated", async function () {
        await setCoverageThresholds(await mocProxy.protThrld(), 46);
        expect(await mocProxy.liqThrld()).to.be.equal(46);
      });
    });
    describe(`WHEN setLiqEnable is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocProxy.setLiqEnabled(true);
        expect(await mocProxy.liqEnabled()).to.be.equal(true);
      });
    });
    describe(`WHEN setSuccessFeeParams is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await setSuccessFeeParams(47, 48);
        expect(await mocProxy.successFee()).to.be.equal(47);
        expect(await mocProxy.appreciationFactor()).to.be.equal(48);
        expect(await mocProxy.mocAppreciationBeneficiaryAddress()).to.be.equal(mockAddress);
      });
    });
    describe(`WHEN setTCInterestParams is invoked`, () => {
      it("THEN the collector can be updated", async function () {
        await setTCInterestParams(
          mockAddress,
          await mocProxy.tcInterestRate(),
          await mocProxy.tcInterestPaymentTimeSpan(),
        );
        expect(await mocProxy.tcInterestCollectorAddress()).to.be.equal(mockAddress);
      });
      it("THEN the rate can be updated", async function () {
        await setTCInterestParams(
          await mocProxy.tcInterestCollectorAddress(),
          51,
          await mocProxy.tcInterestPaymentTimeSpan(),
        );
        expect(await mocProxy.tcInterestRate()).to.be.equal(51);
      });
      it("THEN the time span can be updated", async function () {
        await setTCInterestParams(await mocProxy.tcInterestCollectorAddress(), await mocProxy.tcInterestRate(), 52);
        expect(await mocProxy.tcInterestPaymentTimeSpan()).to.be.equal(52);
      });
    });
    describe(`WHEN setMocVendors is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocProxy.setMocVendors(mockAddress);
        expect(await mocProxy.mocVendors()).to.be.equal(mockAddress);
      });
    });
    describe(`WHEN setFluxCapacitorParams is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await setFluxCapacitorParams(mockAddress, await mocProxy.maxOpDiffProvider(), await mocProxy.decayTimeSpan());
        expect(await mocProxy.maxAbsoluteOpProvider()).to.be.equal(mockAddress);
      });
      it("THEN the differential provider can be updated", async function () {
        await setFluxCapacitorParams(
          await mocProxy.maxAbsoluteOpProvider(),
          mockAddress,
          await mocProxy.decayTimeSpan(),
        );
        expect(await mocProxy.maxOpDiffProvider()).to.be.equal(mockAddress);
      });
      it("THEN the decay time span can be updated", async function () {
        await setFluxCapacitorParams(await mocProxy.maxAbsoluteOpProvider(), await mocProxy.maxOpDiffProvider(), 53);
        expect(await mocProxy.decayTimeSpan()).to.be.equal(53);
      });
    });
    describe(`WHEN setTransferMaxGas is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocProxy.setTransferMaxGas(54);
        expect(await mocProxy.transferMaxGas()).to.be.equal(54);
      });
    });
    describe(`WHEN setMocQueue is invoked`, () => {
      it("THEN the new value is assigned", async function () {
        await mocProxy.setMocQueue(mockAddress);
        expect(await mocProxy.mocQueue()).to.be.equal(mockAddress);
      });
    });
  });
  describe("GIVEN the Governor has not authorized the change", () => {
    let expectRevertNotAuthorized: (it: any) => any;
    before(async () => {
      await governorMock.setIsAuthorized(false);
      expectRevertNotAuthorized = it => expect(it).to.be.revertedWithCustomError(mocProxy, ERRORS.NOT_AUTH_CHANGER);
    });
    describe("WHEN setEmaCalculationTimeSpan is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.setEmaCalculationTimeSpan(42));
      });
    });
    describe("WHEN setSettlementTimeSpan is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.setSettlementTimeSpan(42));
      });
    });
    describe("WHEN setOperationsFee is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.setOperationsFee(feeParams));
      });
    });
    describe("WHEN setMocFeeFlowAddress is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.setMocFeeFlowAddress(mockAddress));
      });
    });
    describe("WHEN setFeeTokenParams is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(setFeeTokenParams(mockAddress, mockAddress));
      });
    });
    describe("WHEN setCoverageThresholds is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(setCoverageThresholds(42, 42));
      });
    });
    describe("WHEN setSuccessFeeParams is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(setSuccessFeeParams(42, 42));
      });
    });
    describe("WHEN makeUnstoppable is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.makeUnstoppable());
      });
    });
    describe("WHEN makeStoppable is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.makeStoppable());
      });
    });
    describe("WHEN setPauser is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.setPauser(mockAddress));
      });
    });
    describe("WHEN setLiqEnable is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.setLiqEnabled(true));
      });
    });
    describe(`WHEN setLiqEnable is invoked by the pauser`, () => {
      it("THEN the new value is assigned", async function () {
        await mocProxy.connect(await ethers.getSigner(pauser)).setLiqEnabled(true);
        expect(await mocProxy.liqEnabled()).to.be.equal(true);
      });
    });
    describe("WHEN setTCInterestParams is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(setTCInterestParams(mockAddress, 42, 42));
      });
    });
    describe("WHEN setMocVendors is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.setMocVendors(mockAddress));
      });
    });
    describe("WHEN setMocCoreExpansion is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.setMocCoreExpansion(mockAddress));
      });
    });
    describe("WHEN setFluxCapacitorParams is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(setFluxCapacitorParams(mockAddress, mockAddress, 42));
      });
    });
    describe("WHEN setTransferMaxGas is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.setTransferMaxGas(42));
      });
    });
    describe("WHEN setMocQueue is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        await expectRevertNotAuthorized(mocProxy.setMocQueue(mockAddress));
      });
    });
  });
});
