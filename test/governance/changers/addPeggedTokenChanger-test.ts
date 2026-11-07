import { expect } from "chai";
import { ethers, getNamedAccounts } from "hardhat";
import { BigNumberish, Contract, ContractFactory, ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { fixtureDeployedMocCoinbase } from "../../coinbase/fixture";
import {
  IChangeContract__factory,
  IGovernor,
  MocCACoinbase,
  MocCARC20,
  MocMultiCollateralGuard,
  MocRC20,
  PriceProviderMock,
} from "../../../typechain";
import {
  BURNER_ROLE,
  DEFAULT_ADMIN_ROLE,
  MINTER_ROLE,
  ERRORS,
  deployPeggedToken,
  deployPriceProvider,
  pEth,
  CONSTANTS,
  tpParamsDefault,
  tpParams,
  deployAeropagusGovernor,
  timedDescribe,
} from "../../helpers/utils";
import { assertPrec } from "../../helpers/assertHelper";

export function deployChangerClosure(
  mocMultiCollateralGuard: MocMultiCollateralGuard,
  buckets: MocCACoinbase[] | MocCARC20[],
) {
  return async () => {
    const changerFactory = await ethers.getContractFactory("AddPeggedTokenChangerTemplate");
    const governorAddress = await mocMultiCollateralGuard.governor();
    const mocPeggedToken = await deployPeggedToken({ adminAddress: buckets[0].target.toString(), governorAddress });
    const priceProvider = await deployPriceProvider(pEth(1));

    const deployAddChanger = ({
      overwriteBuckets,
      tpTokenAddress = mocPeggedToken.target.toString(),
      priceProviderAddress = priceProvider.target.toString(),
      tpCtarg = tpParamsDefault.tpCtarg,
      tpMintFee = tpParamsDefault.tpMintFee,
      tpRedeemFee = tpParamsDefault.tpRedeemFee,
      tpEma = tpParamsDefault.tpEma,
      tpEmaSf = tpParamsDefault.tpEmaSf,
    }: {
      overwriteBuckets?: MocCACoinbase[] | MocCARC20[];
      tpTokenAddress?: Address;
      priceProviderAddress?: Address;
      tpCtarg?: BigNumberish;
      tpMintFee?: BigNumberish;
      tpRedeemFee?: BigNumberish;
      tpEma?: BigNumberish;
      tpEmaSf?: BigNumberish;
    } = {}) => {
      const bucketsOverwrite = overwriteBuckets ? overwriteBuckets : buckets;
      const paramsArray = bucketsOverwrite.map(bucket => ({
        bucket: bucket.target.toString(),
        peggedTokenParams: {
          priceProviderAddress,
          tpCtarg,
          tpMintFee,
          tpRedeemFee,
          tpEma,
          tpEmaSf,
        },
      }));
      return changerFactory.deploy(mocMultiCollateralGuard.target.toString(), tpTokenAddress, paramsArray);
    };
    return { mocPeggedToken, priceProvider, deployAddChanger };
  };
}

timedDescribe("Feature: Governance protected Pegged Token addition ", () => {
  let mocProxy: MocCACoinbase;
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let governor: IGovernor;
  let changeContract: Contract;
  let mocPeggedToken: MocRC20;
  let priceProvider: PriceProviderMock;
  let deployChanger: any;
  let deployer: Address;
  before(async () => {
    ({ deployer } = await getNamedAccounts());
    const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams);
    ({ mocImpl: mocProxy, mocMultiCollateralGuard } = await fixtureDeploy());

    // set a real governor
    governor = await deployAeropagusGovernor(deployer);
    await mocProxy.changeGovernor(governor.target.toString());
    await mocMultiCollateralGuard.changeGovernor(governor.target.toString());

    ({
      deployAddChanger: deployChanger,
      mocPeggedToken,
      priceProvider,
    } = await deployChangerClosure(mocMultiCollateralGuard, [mocProxy])());
  });
  describe("WHEN trying to setup a Changer with invalid target coverage value", () => {
    it("THEN tx fails because target coverage is below ONE", async () => {
      await expect(deployChanger({ tpCtarg: CONSTANTS.ONE - 1n })).to.be.revertedWithCustomError(
        mocProxy,
        ERRORS.INVALID_VALUE,
      );
    });
  });
  describe("WHEN trying to setup a Changer with invalid mint fee value", () => {
    it("THEN tx fails because mint fee is above ONE", async () => {
      await expect(deployChanger({ tpMintFee: CONSTANTS.ONE + 1n })).to.be.revertedWithCustomError(
        mocProxy,
        ERRORS.INVALID_VALUE,
      );
    });
  });
  describe("WHEN trying to setup a Changer with invalid redeem fee value", () => {
    it("THEN tx fails because redeem fee is above ONE", async () => {
      await expect(deployChanger({ tpRedeemFee: CONSTANTS.ONE + 1n })).to.be.revertedWithCustomError(
        mocProxy,
        ERRORS.INVALID_VALUE,
      );
    });
  });
  describe("WHEN trying to setup a Changer with invalid ema smoothing factor value", () => {
    it("THEN tx fails because ema smoothing factor is above ONE", async () => {
      await expect(deployChanger({ tpEmaSf: CONSTANTS.ONE })).to.be.revertedWithCustomError(
        mocProxy,
        ERRORS.INVALID_VALUE,
      );
    });
  });
  describe("GIVEN a new Pegged Token with roles assigned to the deployer", () => {
    let fakePeggedToken: MocRC20;
    let changer: ContractFactory;
    let transferRole: (role: string) => Promise<void>;
    beforeEach(async () => {
      fakePeggedToken = await deployPeggedToken({
        adminAddress: deployer,
        governorAddress: await mocProxy.governor(),
      });
      changer = await ethers.getContractFactory("AddPeggedTokenChangerTemplate");
      transferRole = async (role: string) => {
        await fakePeggedToken.grantRole(role, mocProxy.target.toString());
        await fakePeggedToken.renounceRole(role, deployer);
      };
    });
    describe("WHEN mints some TPs before setting the Changer", () => {
      it("THEN tx fails because TP total supply > 0", async () => {
        await fakePeggedToken.mint(deployer, 1);
        await transferRole(MINTER_ROLE);
        await transferRole(BURNER_ROLE);
        await transferRole(DEFAULT_ADMIN_ROLE);
        await expect(
          deployChanger({ tpTokenAddress: fakePeggedToken.target.toString() }),
        ).to.be.revertedWithCustomError(changer, ERRORS.TP_TOTAL_SUPPLY_NOT_ZERO);
      });
    });
    describe("WHEN trying to setup a Changer without transferring Minter role to MocCore", () => {
      it("THEN tx fails because MocCore hasn't got the Minter roles", async () => {
        await transferRole(BURNER_ROLE);
        await transferRole(DEFAULT_ADMIN_ROLE);
        await expect(
          deployChanger({ tpTokenAddress: fakePeggedToken.target.toString() }),
        ).to.be.revertedWithCustomError(changer, ERRORS.INVALID_ROLES);
      });
    });
    describe("WHEN trying to setup a Changer without transferring Burner role to MocCore", () => {
      it("THEN tx fails because MocCore hasn't got the Burner roles", async () => {
        await transferRole(MINTER_ROLE);
        await transferRole(DEFAULT_ADMIN_ROLE);
        await expect(
          deployChanger({ tpTokenAddress: fakePeggedToken.target.toString() }),
        ).to.be.revertedWithCustomError(changer, ERRORS.INVALID_ROLES);
      });
    });
    describe("WHEN trying to setup a Changer without transferring Admin role to MocCore", () => {
      it("THEN tx fails because MocCore hasn't got the Admin roles", async () => {
        await transferRole(MINTER_ROLE);
        await transferRole(BURNER_ROLE);
        await expect(
          deployChanger({ tpTokenAddress: fakePeggedToken.target.toString() }),
        ).to.be.revertedWithCustomError(changer, ERRORS.INVALID_ROLES);
      });
    });
    describe("WHEN trying to setup a Changer without renouncing Minter role", () => {
      it("THEN tx fails because MocCore is not the only one with Minter role", async () => {
        await fakePeggedToken.grantRole(MINTER_ROLE, mocProxy.target.toString());
        await transferRole(BURNER_ROLE);
        await transferRole(DEFAULT_ADMIN_ROLE);
        await expect(
          deployChanger({ tpTokenAddress: fakePeggedToken.target.toString() }),
        ).to.be.revertedWithCustomError(changer, ERRORS.INVALID_ROLES);
      });
    });
    describe("WHEN trying to setup a Changer without renouncing Burner role", () => {
      it("THEN tx fails because MocCore is not the only one with Burner role", async () => {
        await fakePeggedToken.grantRole(BURNER_ROLE, mocProxy.target.toString());
        await transferRole(MINTER_ROLE);
        await transferRole(DEFAULT_ADMIN_ROLE);
        await expect(
          deployChanger({ tpTokenAddress: fakePeggedToken.target.toString() }),
        ).to.be.revertedWithCustomError(changer, ERRORS.INVALID_ROLES);
      });
    });
    describe("WHEN trying to setup a Changer without renouncing Admin role", () => {
      it("THEN tx fails because MocCore is not the only one with Admin role", async () => {
        await fakePeggedToken.grantRole(DEFAULT_ADMIN_ROLE, mocProxy.target.toString());
        await transferRole(MINTER_ROLE);
        await transferRole(BURNER_ROLE);
        await expect(
          deployChanger({ tpTokenAddress: fakePeggedToken.target.toString() }),
        ).to.be.revertedWithCustomError(changer, ERRORS.INVALID_ROLES);
      });
    });
  });
  describe("GIVEN a new Pegged Token with a different governor set", () => {
    let fakePeggedToken: MocRC20;
    before(async () => {
      fakePeggedToken = await deployPeggedToken({
        adminAddress: mocProxy.target.toString(),
        governorAddress: deployer,
      });
    });
    describe("WHEN trying to setup a Changer", () => {
      it("THEN tx fails because has a different governor", async () => {
        await expect(
          deployChanger({ tpTokenAddress: fakePeggedToken.target.toString() }),
        ).to.be.revertedWithCustomError(
          await ethers.getContractFactory("AddPeggedTokenChangerTemplate"),
          ERRORS.INVALID_GOVERNOR,
        );
      });
    });
  });
  describe("GIVEN a Changer contract is set up to add a new Pegged Token", () => {
    before(async () => {
      changeContract = await deployChanger(); // with default params
    });
    describe("WHEN an unauthorized account executed the changer", () => {
      it("THEN it fails", async function () {
        const [signer] = await ethers.getSigners();
        const changerTemplate = IChangeContract__factory.connect(changeContract.target.toString(), signer);
        await expect(changerTemplate.execute()).to.be.revertedWithCustomError(mocProxy, ERRORS.NOT_AUTH_CHANGER);
      });
    });
    describe("WHEN the governor executes the changer contract", () => {
      let execTx: ContractTransactionResponse;
      let prevTpAmount: bigint;
      before(async () => {
        prevTpAmount = await mocProxy.getTpAmount();
        execTx = await governor.executeChange(changeContract.target.toString());
      });
      it("THEN the new Pegged Token is added", async function () {
        await expect(execTx)
          .to.emit(mocProxy, "PeggedTokenChange")
          .withArgs(tpParams.length, mocPeggedToken.target.toString(), [
            priceProvider.target.toString(),
            tpParamsDefault.tpCtarg,
            tpParamsDefault.tpMintFee,
            tpParamsDefault.tpRedeemFee,
            tpParamsDefault.tpEma,
            tpParamsDefault.tpEmaSf,
          ]);
      });
      it("THEN we can access getPACtp", async function () {
        assertPrec(1, await mocProxy.getPACtp(mocPeggedToken.target.toString()));
      });
      it("THEN getTPAmount returns is increased", async function () {
        expect(prevTpAmount + 1n).to.be.equal(await mocProxy.getTpAmount());
      });
    });
  });
});
