import { expect } from "chai";
import { ethers, getNamedAccounts } from "hardhat";
import { Contract, ContractFactory, ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { fixtureDeployedMulticollateral } from "../../multicollateral/fixture";
import { IGovernor, MocMultiCollateralGuard, MocRC20, PriceProviderMock } from "../../../typechain";
import {
  ERRORS,
  tpParams,
  deployAeropagusGovernor,
  tpParamsDefault,
  MINTER_ROLE,
  BURNER_ROLE,
  DEFAULT_ADMIN_ROLE,
} from "../../helpers/utils";
import { deployChangerClosure } from "./addPeggedTokenChanger-test";

describe("Feature: Governance protected Pegged Token addition - MultiCollateral", () => {
  async function fixture() {
    return fixtureDeployedMulticollateral(tpParams.length, tpParams);
  }
  let mocContracts: any;
  let buckets: any;
  let mocBucketContracts: any;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let governor: IGovernor;
  let changeContract: Contract;
  let mocPeggedToken: MocRC20;
  let priceProvider: PriceProviderMock;
  let deployChanger: any;
  let changer: ContractFactory;
  let deployer: Address;
  before(async () => {
    ({ deployer } = await getNamedAccounts());
    mocContracts = await loadFixture(fixture);
    ({ mocMultiCollateralGuard, mocBucketContracts } = mocContracts);
    buckets = mocBucketContracts.map((mocBucketContract: any) => mocBucketContract.mocImpl);
    // set a real governor
    governor = await deployAeropagusGovernor(deployer);

    await Promise.all([...buckets, mocMultiCollateralGuard].map(it => it.changeGovernor(governor.target.toString())));

    ({
      deployAddChanger: deployChanger,
      mocPeggedToken,
      priceProvider,
    } = await deployChangerClosure(mocMultiCollateralGuard, buckets)());
    changer = await ethers.getContractFactory("AddPeggedTokenChangerTemplate");
  });
  describe("WHEN trying to setup a Changer with invalid TP parameters length", () => {
    it("THEN tx fails because unequal length", async () => {
      await expect(deployChanger({ overwriteBuckets: [buckets[0]] })).to.be.revertedWithCustomError(
        changer,
        ERRORS.UNEQUAL_LENGTH,
      );
    });
  });
  describe("WHEN trying to setup a Changer with a bucket that is not set on the MultiCollateralGuard", () => {
    it("THEN tx fails because bucket does not exist", async () => {
      const fakeBucket = { target: deployer };
      await expect(
        deployChanger({ overwriteBuckets: [...buckets.slice(0, -1), fakeBucket] }),
      ).to.be.revertedWithCustomError(changer, ERRORS.BUCKET_DOES_NOT_EXIST);
    });
  });
  describe("WHEN trying to setup a Changer with a bucket duplicated on the params", () => {
    it("THEN tx fails because bucket param duplicated", async () => {
      const duplicatedBucket = buckets[0];
      await expect(
        deployChanger({ overwriteBuckets: [...buckets.slice(0, -1), duplicatedBucket] }),
      ).to.be.revertedWithCustomError(changer, ERRORS.BUCKET_PARAM_DUPLICATED);
    });
  });
  describe("GIVEN a Changer contract is set up to add a new Pegged Token", () => {
    before(async () => {
      changeContract = await deployChanger(); // with default params
    });
    describe("WHEN the governor executes the changer contract", () => {
      let execTx: ContractTransactionResponse;
      let prevTpAmount: bigint;
      before(async () => {
        prevTpAmount = await buckets[0].getTpAmount();
        execTx = await governor.executeChange(changeContract.target.toString());
      });
      it("THEN the new Pegged Token is added on all the buckets", async function () {
        for (const bucket of buckets) {
          await expect(execTx)
            .to.emit(bucket, "PeggedTokenChange")
            .withArgs(tpParams.length, mocPeggedToken.target.toString(), [
              priceProvider.target.toString(),
              tpParamsDefault.tpCtarg,
              tpParamsDefault.tpMintFee,
              tpParamsDefault.tpRedeemFee,
              tpParamsDefault.tpEma,
              tpParamsDefault.tpEmaSf,
            ]);
        }
      });
      it("THEN getTPAmount returns is increased on all the buckets", async function () {
        const newTPAmount = await Promise.all(buckets.map((it: any) => it.getTpAmount()));
        // all the TP amount are the same
        expect(new Set(newTPAmount.map((it: any) => Number(it))).size).to.equal(1);
        // TP amount increased
        expect(prevTpAmount + 1n).to.be.equal(newTPAmount[0]);
      });
      it("THEN all the buckets have TP minter role", async function () {
        const minterRole = await Promise.all(
          buckets.map((it: any) => mocPeggedToken.hasRole(MINTER_ROLE, it.target.toString())),
        );
        expect(new Set(minterRole).size).to.equal(1);
        expect(await mocPeggedToken.getRoleMemberCount(MINTER_ROLE)).to.be.equal(buckets.length);
      });
      it("THEN all the buckets have TP burner role", async function () {
        const burnerRole = await Promise.all(
          buckets.map((it: any) => mocPeggedToken.hasRole(BURNER_ROLE, it.target.toString())),
        );
        expect(new Set(burnerRole).size).to.equal(1);
        expect(await mocPeggedToken.getRoleMemberCount(BURNER_ROLE)).to.be.equal(buckets.length);
      });
      it("THEN only one bucket has TP admin role", async function () {
        const adminRole = await Promise.all(
          buckets.map((it: any) => mocPeggedToken.hasRole(DEFAULT_ADMIN_ROLE, it.target.toString())),
        );
        expect(adminRole.some((value: any) => value)).to.be.true;
        expect(await mocPeggedToken.getRoleMemberCount(DEFAULT_ADMIN_ROLE)).to.be.equal(1);
      });
    });
  });
});
