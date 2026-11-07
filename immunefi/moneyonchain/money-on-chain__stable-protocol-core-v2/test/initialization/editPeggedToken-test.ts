import { expect } from "chai";
import { BigNumberish, ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { ERRORS, timedDescribe, tpParamsDefault } from "../helpers/utils";
import { MocCARC20, MocRC20, PriceProviderMock } from "../../typechain";
import { fixtureDeployedMocRC20 } from "../rc20/fixture";

timedDescribe("Feature: MocCARC20 edit Pegged Token", function () {
  let mocImpl: MocCARC20;
  let mocPeggedTokens: MocRC20[];
  let priceProviders: PriceProviderMock[];
  const mocEditPeggedToken =
    (mocCARC20: MocCARC20) =>
    ({
      tpTokenAddress = mocPeggedTokens[0].target.toString(),
      priceProviderAddress = priceProviders[0].target.toString(),
      tpCtarg = tpParamsDefault.tpCtarg,
      tpMintFee = tpParamsDefault.tpMintFee,
      tpRedeemFee = tpParamsDefault.tpRedeemFee,
      tpEma = tpParamsDefault.tpEma,
      tpEmaSf = tpParamsDefault.tpEmaSf,
    }: {
      tpTokenAddress?: Address;
      priceProviderAddress?: Address;
      tpCtarg?: BigNumberish;
      tpMintFee?: BigNumberish;
      tpRedeemFee?: BigNumberish;
      tpEma?: BigNumberish;
      tpEmaSf?: BigNumberish;
    } = {}) => {
      return mocCARC20.editPeggedToken(tpTokenAddress, {
        priceProviderAddress,
        tpCtarg,
        tpMintFee,
        tpRedeemFee,
        tpEma,
        tpEmaSf,
      });
    };

  describe("GIVEN a MocCARC20 implementation with two PeggedToken", () => {
    beforeEach(async () => {
      ({ mocImpl, mocPeggedTokens, priceProviders } = await fixtureDeployedMocRC20(2)());
    });
    describe("WHEN edit Pegged Token is invoked with an invalid pegged address", () => {
      it("THEN tx fails because address is is not indexed", async () => {
        await expect(
          mocEditPeggedToken(mocImpl)({ tpTokenAddress: priceProviders[0].target.toString() }),
        ).to.be.revertedWithCustomError(mocImpl, ERRORS.INVALID_ADDRESS);
      });
    });
    describe("WHEN a Pegged Token is edited with valid parameters", () => {
      let tx: ContractTransactionResponse;
      let editParams: any;
      beforeEach(async () => {
        editParams = {
          tpTokenAddress: mocPeggedTokens[0].target.toString(),
          priceProviderAddress: priceProviders[1].target.toString(),
          tpCtarg: tpParamsDefault.tpCtarg + 1n,
          tpMintFee: tpParamsDefault.tpMintFee + 4n,
          tpRedeemFee: tpParamsDefault.tpRedeemFee + 5n,
          tpEma: tpParamsDefault.tpEma + 6n, // -----> Note: Emma cannot be edited, intentionally added
          tpEmaSf: tpParamsDefault.tpEmaSf + 7n,
        };
        tx = await mocEditPeggedToken(mocImpl)(editParams);
      });
      it("THEN a PeggedTokenChange event is emitted", async () => {
        await expect(tx).to.emit(mocImpl, "PeggedTokenChange").withArgs(0, mocPeggedTokens[0].target.toString(), [
          priceProviders[1].target.toString(),
          editParams.tpCtarg,
          editParams.tpMintFee,
          editParams.tpRedeemFee,
          editParams.tpEma, // Note: ema should not be edited, although the event has the value it vas passed on
          editParams.tpEmaSf,
        ]);
      });
      it("THEN ema value itself has not change, only SF", async () => {
        const tpEma = await mocImpl.tpEma(0);
        expect(tpEma.ema).to.be.equal(tpParamsDefault.tpEma);
        expect(tpEma.sf).to.be.equal(editParams.tpEmaSf);
      });
      it("THEN new Pegged token ctar has changed", async () => {
        const tpCtarg = await mocImpl.tpCtarg(0);
        expect(tpCtarg).to.be.equal(editParams.tpCtarg);
      });
      it("THEN other Pegged token params have not changed", async () => {
        const tpCtarg = await mocImpl.tpCtarg(1);
        const tpEma = await mocImpl.tpEma(1);
        expect(tpCtarg).to.be.equal(tpParamsDefault.tpCtarg);
        expect(tpEma.sf).to.be.equal(tpParamsDefault.tpEmaSf);
      });
    });
  });
});
