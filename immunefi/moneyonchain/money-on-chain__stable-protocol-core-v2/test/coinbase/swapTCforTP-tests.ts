import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { swapTCforTPQueueBehavior } from "../behaviors/queue/swapTCforTPQueue.behavior";
import { swapTCforTPBehavior } from "../behaviors/swapTCforTP.behavior";
import { Balance, ERROR_SELECTOR, OperId, OperType, pEth, timedDescribe, tpParams, noVendor } from "../helpers/utils";
import { MocCACoinbase, MocMultiCollateralGuard, MocQueue, MocRC20, NonPayableMock } from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase swap TC for TP", function () {
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsCoinbase(mocContracts);
      return { mocContracts, mocFunctions };
    }
    swapTCforTPBehavior(setup);
  });

  describe("GIVEN a MocCoinbase implementation deployed behind MocQueue", function () {
    let mocImpl: MocCACoinbase;
    let mocCollateralToken: MocRC20;
    let tp: MocRC20;
    let mocQueue: MocQueue;
    let mocMultiCollateralGuard: MocMultiCollateralGuard;
    let mocFunctions: any;
    let deployer: Address;
    async function setup() {
      ({ deployer } = await getNamedAccounts());
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueBasefeeMock");
      const mocContracts = await fixtureDeploy();
      mocFunctions = await mocFunctionsCoinbase(mocContracts);
      ({
        mocImpl,
        mocQueue,
        mocMultiCollateralGuard,
        mocCollateralToken,
        mocPeggedTokens: [tp],
      } = mocContracts);
      return { mocContracts, mocFunctions };
    }
    swapTCforTPQueueBehavior(setup);

    describe("AND a non payable contract", () => {
      let nonPayable: NonPayableMock;
      let operId: OperId;
      const qACSent = pEth(100);
      async function nonPayableSetup() {
        await loadFixture(setup);
        const factory = await ethers.getContractFactory("NonPayableMock");
        nonPayable = await factory.deploy();
      }
      describe("WHEN it registers a swapTCforTP operation with exceeded amount of coinbase", () => {
        async function registerSwapTCForTPSetup() {
          await loadFixture(nonPayableSetup);
          // mint TC to non payable contract
          await mocFunctions.mintTC({ from: deployer, to: nonPayable.target.toString(), qTC: 1000 });
          // non payable contract sends TC approval to Moc
          let data = mocCollateralToken.interface.encodeFunctionData("approve", [mocImpl.target.toString(), pEth(1)]);
          await nonPayable.forward(mocCollateralToken.target.toString(), data);

          operId = await mocQueue.operIdCount();
          // non payable contract registers swapTCforTP operation
          data = mocImpl.interface.encodeFunctionData("swapTCforTP", [
            tp.target.toString(),
            pEth(1),
            0,
            deployer,
            noVendor,
          ]);
          await nonPayable.forward(mocImpl.target.toString(), data, {
            value: (await mocQueue.execCost(OperType.swapTCforTP)) + qACSent,
          });
        }
        describe("AND execution is evaluated", () => {
          let execTx: ContractTransactionResponse;
          let prevTCBalance: Balance;
          let prevACBalance: Balance;
          before(async function () {
            await loadFixture(registerSwapTCForTPSetup);
            prevTCBalance = await mocFunctions.tcBalanceOf(nonPayable.target.toString());
            prevACBalance = await mocFunctions.assetBalanceOf(deployer);
            execTx = await mocMultiCollateralGuard.execute();
          });
          it("THEN Operations fails with Unhandled Error as non payable contract cannot receive the surplus AC", async () => {
            await expect(execTx).to.emit(mocQueue, "UnhandledError").withArgs(operId, ERROR_SELECTOR.TRANSFER_FAILED);
          });
          it("THEN TC is returned", async () => {
            assertPrec(prevTCBalance + pEth(1), await mocFunctions.tcBalanceOf(nonPayable.target.toString()));
          });
          it("THEN ACUnlockFailed event is emitted", async function () {
            await expect(execTx).to.emit(mocQueue, "ACUnlockFailed").withArgs(operId, nonPayable, qACSent);
          });
          it("THEN AC is locked on mocCore and tracked on mocQueue", async () => {
            assertPrec(prevACBalance, await mocFunctions.assetBalanceOf(deployer));
            assertPrec(await mocQueue.senderLockedFunds(nonPayable), qACSent);
            assertPrec(await mocQueue.totalLockedFunds(), qACSent);
            assertPrec(await mocImpl.qACLockedInPending(), qACSent);
          });
        });
      });
    });
  });
});
