import { expect } from "chai";
import { ethers, getNamedAccounts } from "hardhat";
import { ContractTransactionResponse } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { fixtureDeployedMulticollateral } from "../../multicollateral/fixture";
import {
  EditBucketChangerTemplate,
  EditBucketChangerTemplate__factory,
  IGovernor,
  MocMultiCollateralGuard,
} from "../../../typechain";
import { ERRORS, pEth, tpParams, deployAeropagusGovernor } from "../../helpers/utils";
import { assertPrec } from "../../helpers/assertHelper";

describe("Feature: Governance protected bucket edition ", () => {
  async function fixture() {
    return fixtureDeployedMulticollateral(tpParams.length, tpParams);
  }
  let bucket: any;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let governor: IGovernor;
  let changerFactory: any;
  let changeContract: EditBucketChangerTemplate;
  before(async () => {
    const { deployer } = await getNamedAccounts();
    const mocContracts = await loadFixture(fixture);
    ({
      mocBucketContracts: [bucket],
      mocMultiCollateralGuard,
    } = mocContracts);

    // set a real governor
    governor = await deployAeropagusGovernor(deployer);
    await bucket.mocImpl.changeGovernor(governor.target.toString());
    await mocMultiCollateralGuard.changeGovernor(governor.target.toString());
    changerFactory = await ethers.getContractFactory("EditBucketChangerTemplate");
  });
  describe("WHEN trying to setup an edit Changer with invalid bucket address value", () => {
    it("THEN tx fails because tp must be a member", async () => {
      await expect(
        changerFactory.deploy(mocMultiCollateralGuard.target.toString(), mocMultiCollateralGuard.target.toString()),
      ).to.be.revertedWithCustomError(mocMultiCollateralGuard, ERRORS.BUCKET_DOES_NOT_EXIST);
    });
  });

  describe("GIVEN a Changer contract is set up to edit a bucket", () => {
    beforeEach(async () => {
      const deployedChanger = await changerFactory.deploy(
        mocMultiCollateralGuard.target.toString(),
        bucket.mocImpl.target.toString(),
      );
      const [signer] = await ethers.getSigners();
      changeContract = EditBucketChangerTemplate__factory.connect(deployedChanger.target.toString(), signer);
    });
    describe("WHEN the changer is executed", () => {
      it("THEN it fails as the param is not yet set", async function () {
        await expect(governor.executeChange(changeContract.target.toString())).to.be.revertedWithCustomError(
          changeContract,
          "InvalidParamSetCount",
        );
      });
    });
    describe("WHEN an unauthorized account tries to set the micro liquidation threshold", () => {
      it("THEN it fails", async function () {
        const { alice } = await getNamedAccounts();
        await expect(
          changeContract.connect(await ethers.getSigner(alice)).setMicroLiquidationThrld(pEth(1)),
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });
    });
    describe("GIVEN a new micro liquidation threshold set on the changer", () => {
      beforeEach(async () => {
        await changeContract.setMicroLiquidationThrld(pEth(1));
      });
      describe("WHEN deployer tries to set it again", () => {
        it("THEN it fails", async function () {
          await expect(changeContract.setMicroLiquidationThrld(pEth(1))).to.be.revertedWithCustomError(
            changeContract,
            "InvalidParamSetCount",
          );
        });
      });
      describe("WHEN an unauthorized account executes the changer", () => {
        it("THEN it fails", async function () {
          await expect(changeContract.execute()).to.be.revertedWithCustomError(
            mocMultiCollateralGuard,
            ERRORS.NOT_AUTH_CHANGER,
          );
        });
      });
      describe("WHEN a the governor executes the changer contract", () => {
        let execTx: ContractTransactionResponse;
        beforeEach(async function () {
          execTx = await governor.executeChange(changeContract.target.toString());
        });
        it("THEN BucketChange event is emitted", async function () {
          await expect(execTx).to.emit(mocMultiCollateralGuard, "BucketChange");
        });
        it("THEN microLiquidationThrld returns the new value", async function () {
          assertPrec(await mocMultiCollateralGuard.microLiquidationThrld(bucket.mocImpl.target.toString()), 1);
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
