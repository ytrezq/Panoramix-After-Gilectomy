import { expect } from "chai";
import { ethers, getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { fixtureDeployedMocCoinbase } from "../../coinbase/fixture";
import { assertPrec } from "../../helpers/assertHelper";
import {
  EditPeggedTokenChangerTemplate,
  EditPeggedTokenChangerTemplate__factory,
  IChangeContract__factory,
  IGovernor,
  MocCACoinbase,
  MocMultiCollateralGuard,
  MocRC20,
  PriceProviderMock,
} from "../../../typechain";
import {
  ERRORS,
  deployPriceProvider,
  pEth,
  tpParamsDefault,
  deployAeropagusGovernor,
  tpParams,
  timedDescribe,
} from "../../helpers/utils";
import { deployChangerClosure } from "./addPeggedTokenChanger-test";

timedDescribe("Feature: Governance protected Pegged Token edition ", () => {
  let mocProxy: MocCACoinbase;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let governor: IGovernor;
  let changeContract: EditPeggedTokenChangerTemplate;
  let mocPeggedToken: MocRC20;
  let priceProvider: PriceProviderMock;
  let newPriceProvider: PriceProviderMock;
  let changerFactory: any;

  before(async () => {
    const { deployer } = await getNamedAccounts();
    const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams);
    ({ mocImpl: mocProxy, mocMultiCollateralGuard } = await fixtureDeploy());

    // set a real governor
    governor = await deployAeropagusGovernor(deployer);
    await mocProxy.changeGovernor(governor.target.toString());
    await mocMultiCollateralGuard.changeGovernor(governor.target.toString());

    let deployAddChanger: any;
    ({ deployAddChanger, mocPeggedToken, priceProvider } = await deployChangerClosure(mocMultiCollateralGuard, [
      mocProxy,
    ])());
    const addChangerContract = await deployAddChanger();
    await governor.executeChange(addChangerContract.target.toString());

    changerFactory = await ethers.getContractFactory("EditPeggedTokenChangerTemplate");
  });
  describe("WHEN trying to setup an edit Changer with invalid token address value", () => {
    it("THEN tx fails because tp must be a member", async () => {
      await expect(
        changerFactory.deploy(mocProxy.target.toString(), priceProvider.target.toString()),
      ).to.be.revertedWithCustomError(mocProxy, ERRORS.INVALID_ADDRESS);
    });
  });

  describe("GIVEN a Changer contract is set up to edit a Pegged Token", () => {
    beforeEach(async () => {
      const deployedChanger = await changerFactory.deploy(mocProxy.target.toString(), mocPeggedToken.target.toString());
      const [signer] = await ethers.getSigners();

      changeContract = EditPeggedTokenChangerTemplate__factory.connect(deployedChanger.target.toString(), signer);
    });
    describe("WHEN the changer is executed", () => {
      it("THEN it fails as the param is not yet set", async function () {
        await expect(governor.executeChange(changeContract.target.toString())).to.be.revertedWithCustomError(
          changeContract,
          "InvalidParamSetCount",
        );
      });
    });
    describe("WHEN an unauthorized account tries to set the Price Provider", () => {
      it("THEN it fails", async function () {
        newPriceProvider = await deployPriceProvider(pEth(1));
        const { alice } = await getNamedAccounts();
        await expect(
          changeContract.connect(await ethers.getSigner(alice)).setPriceProvider(newPriceProvider.target.toString()),
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });
    });
    describe("GIVEN a new PriceProvider is set on the changer", () => {
      beforeEach(async () => {
        newPriceProvider = await deployPriceProvider(pEth(42));
        await changeContract.setPriceProvider(newPriceProvider.target.toString());
      });
      describe("WHEN deployer tries to set it again", () => {
        it("THEN it fails", async function () {
          await expect(
            changeContract.setPriceProvider(newPriceProvider.target.toString()),
          ).to.be.revertedWithCustomError(changeContract, "InvalidParamSetCount");
        });
      });
      describe("WHEN an unauthorized account executes the changer", () => {
        it("THEN it fails", async function () {
          const [signer] = await ethers.getSigners();
          const changerTemplate = IChangeContract__factory.connect(changeContract.target.toString(), signer);
          await expect(changerTemplate.execute()).to.be.revertedWithCustomError(mocProxy, ERRORS.NOT_AUTH_CHANGER);
        });
      });
      describe("WHEN a the governor executes the changer contract", () => {
        let execTx: ContractTransactionResponse;
        beforeEach(async function () {
          execTx = await governor.executeChange(changeContract.target.toString());
        });
        it("THEN only the Pegged Token Price Provider is changed", async function () {
          await expect(execTx)
            .to.emit(mocProxy, "PeggedTokenChange")
            .withArgs(tpParams.length, mocPeggedToken.target.toString(), [
              newPriceProvider.target.toString(), // <---- New Price Provider
              tpParamsDefault.tpCtarg,
              tpParamsDefault.tpMintFee,
              tpParamsDefault.tpRedeemFee,
              0, // Initial Emma is not set
              tpParamsDefault.tpEmaSf,
            ]);
        });
        it("THEN getPACtp returns the new price", async function () {
          assertPrec(42, await mocProxy.getPACtp(mocPeggedToken.target.toString()));
        });
        describe("AND the governor tries to execute it again", () => {
          it("THEN it fails", async function () {
            await expect(governor.executeChange(changeContract.target.toString())).to.be.revertedWithCustomError(
              changeContract,
              "InvalidParamSetCount",
            );
          });
        });
      });
    });
  });
});
