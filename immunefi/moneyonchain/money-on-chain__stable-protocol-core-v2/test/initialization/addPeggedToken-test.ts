import { expect } from "chai";
import { BigNumberish, ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { ERRORS, deployPeggedToken, deployPriceProvider, pEth, timedDescribe, tpParamsDefault } from "../helpers/utils";
import { MocCARC20, MocRC20, PriceProviderMock } from "../../typechain";
import { fixtureDeployedMocRC20 } from "../rc20/fixture";

timedDescribe("Feature: MocCARC20 add Pegged Token", function () {
  let mocImpl: MocCARC20;
  let mocPeggedToken: MocRC20;
  let priceProvider: PriceProviderMock;
  const mocAddPeggedToken =
    (mocCARC20: MocCARC20) =>
    ({
      tpTokenAddress = mocPeggedToken.target.toString(),
      priceProviderAddress = priceProvider.target.toString(),
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
      return mocCARC20.addPeggedToken(tpTokenAddress, {
        priceProviderAddress,
        tpCtarg,
        tpMintFee,
        tpRedeemFee,
        tpEma,
        tpEmaSf,
      });
    };

  describe("GIVEN a MocCARC20 implementation deployed", () => {
    beforeEach(async () => {
      ({ mocImpl } = await fixtureDeployedMocRC20(0)());
      const governorAddress = await mocImpl.governor();
      mocPeggedToken = await deployPeggedToken({ adminAddress: mocImpl.target.toString(), governorAddress });
      priceProvider = await deployPriceProvider(pEth(1));
    });
    describe("WHEN a Pegged Token is added with valid parameters", () => {
      let tx: ContractTransactionResponse;
      beforeEach(async () => {
        tx = await mocAddPeggedToken(mocImpl)();
      });
      it("THEN a PeggedTokenChange event is emitted", async () => {
        await expect(tx)
          .to.emit(mocImpl, "PeggedTokenChange")
          .withArgs(0, mocPeggedToken.target.toString(), [
            priceProvider.target.toString(),
            tpParamsDefault.tpCtarg,
            tpParamsDefault.tpMintFee,
            tpParamsDefault.tpRedeemFee,
            tpParamsDefault.tpEma,
            tpParamsDefault.tpEmaSf,
          ]);
      });
      describe("AND try to add it again", () => {
        it("THEN tx fails because Pegged Token is already added", async () => {
          await expect(mocAddPeggedToken(mocImpl)()).to.be.revertedWithCustomError(
            mocImpl,
            ERRORS.PEGGED_TOKEN_ALREADY_ADDED,
          );
        });
      });
    });
  });
});
