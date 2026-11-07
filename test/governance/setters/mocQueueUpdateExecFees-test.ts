import { expect } from "chai";
import hre, { deployments, ethers } from "hardhat";
import { GovernorMock, GovernorMock__factory, MocQueue, MocQueue__factory } from "../../../typechain";
import { ERRORS, OperType, getNetworkDeployParams, timedDescribe } from "../../helpers/utils";
import { DeployParameters } from "../../../scripts/types";

const fixtureDeploy = async (): Promise<{
  mocQueue: MocQueue;
}> => {
  await deployments.fixture();
  const [signer] = await ethers.getSigners();

  const deployedMocQueue = await deployments.getOrNull("MocQueueCARC20Proxy");
  if (!deployedMocQueue) throw new Error("No MocQueue deployed.");
  const mocQueue: MocQueue = MocQueue__factory.connect(deployedMocQueue.address, signer);

  return {
    mocQueue,
  };
};

timedDescribe("Feature: MocQueue execution fees update", () => {
  let governorMock: GovernorMock;
  let mocQueue: MocQueue;
  const execCostKeys: { [key: string]: OperType } = {
    tcMintExecCost: OperType.mintTC,
    tcRedeemExecCost: OperType.redeemTC,
    tpMintExecCost: OperType.mintTP,
    tpRedeemExecCost: OperType.redeemTP,
    mintTCandTPExecCost: OperType.mintTCandTP,
    redeemTCandTPExecCost: OperType.redeemTCandTP,
    swapTCforTPExecCost: OperType.swapTCforTP,
    swapTPforTCExecCost: OperType.swapTPforTC,
    swapTPforTPExecCost: OperType.swapTPforTP,
  };

  before(async () => {
    ({ mocQueue } = await fixtureDeploy());
    const governorAddress = await mocQueue.governor();
    const [signer] = await ethers.getSigners();
    governorMock = GovernorMock__factory.connect(governorAddress, signer);
  });

  describe("GIVEN the Governor has authorized the change AND mocQueue is empty", () => {
    let execCostParams: DeployParameters["queueParams"]["execCostParams"];
    let expectExecutionFee: (expectedFees: any) => any;
    before(async () => {
      await governorMock.setIsAuthorized(true);
      ({ execCostParams } = getNetworkDeployParams(hre).queueParams);
      expectExecutionFee = async (expectedFees: any) => {
        return Promise.all(
          Object.keys(execCostKeys).map(execFeeKey =>
            mocQueue
              .execCost(execCostKeys[execFeeKey])
              .then((fee: any) => expect(expectedFees[execFeeKey]).to.be.equal(fee)),
          ),
        );
      };
    });
    describe("AND mocQueue is empty", () => {
      Object.keys(execCostKeys).forEach(execFeeKey => {
        describe(`WHEN updateExecutionCosts is invoked to update ${execFeeKey}`, () => {
          it(`THEN only ${execFeeKey} is updated`, async function () {
            const execCostParamsToUpdate = Object.assign({}, execCostParams, { [execFeeKey]: 42 });
            await mocQueue.updateExecutionCosts(execCostParamsToUpdate);
            await expectExecutionFee(execCostParamsToUpdate);
          });
        });
      });
    });
  });
  describe("GIVEN the Governor has not authorized the change", () => {
    before(async () => {
      await governorMock.setIsAuthorized(false);
    });
    describe("WHEN updateExecutionCosts is invoked", () => {
      it("THEN it fails, as it's protected by onlyAuthorizedChanger", async function () {
        const { execCostParams } = getNetworkDeployParams(hre).queueParams;
        await expect(mocQueue.updateExecutionCosts(execCostParams)).to.be.revertedWithCustomError(
          mocQueue,
          ERRORS.NOT_AUTH_CHANGER,
        );
      });
    });
  });
});
