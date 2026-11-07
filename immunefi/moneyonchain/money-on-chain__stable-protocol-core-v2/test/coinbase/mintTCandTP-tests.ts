import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { mintTCandTPBehavior } from "../behaviors/mintTCandTP.behavior";
import { mintTCandTPQueueBehavior } from "../behaviors/queue/mintTCandTPQueue.behavior";
import { Balance, ERROR_SELECTOR, OperId, OperType, pEth, timedDescribe, tpParams, noVendor } from "../helpers/utils";
import { MocCACoinbase, MocMultiCollateralGuard, MocQueue, MocRC20, NonPayableMock } from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";
import { fixtureDeployedMocCoinbase } from "./fixture";

timedDescribe("Feature: MocCoinbase mint TC and TP", function () {
  describe("GIVEN a MocCoinbase implementation deployed with mocQueueMock", function () {
    async function setup() {
      const fixtureDeploy = fixtureDeployedMocCoinbase(tpParams.length, tpParams, "MocQueueMock");
      const mocContracts = await fixtureDeploy();
      const mocFunctions = await mocFunctionsCoinbase(mocContracts);
      return { mocContracts, mocFunctions };
    }
    mintTCandTPBehavior(setup);
  });

  describe("GIVEN a MocCoinbase implementation deployed behind MocQueue", function () {
    let mocImpl: MocCACoinbase;
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
        mocPeggedTokens: [tp],
      } = mocContracts);
      return { mocContracts, mocFunctions };
    }
    mintTCandTPQueueBehavior(setup);

    describe("AND a non payable contract", () => {
      let nonPayable: NonPayableMock;
      let operId: OperId;
      const qACSent = pEth(100);
      async function nonPayableSetup() {
        await loadFixture(setup);
        const factory = await ethers.getContractFactory("NonPayableMock");
        nonPayable = await factory.deploy();
      }
      describe("WHEN it registers a mintTCandTP operation with exceeded amount of coinbase", () => {
        async function registerMintSetup() {
          await loadFixture(nonPayableSetup);
          operId = await mocQueue.operIdCount();
          // non payable contract registers mintTCandTP operation
          const data = mocImpl.interface.encodeFunctionData("mintTCandTP", [
            tp.target.toString(),
            pEth(1),
            deployer,
            noVendor,
          ]);
          await nonPayable.forward(mocImpl.target.toString(), data, {
            value: (await mocQueue.execCost(OperType.mintTCandTP)) + qACSent,
          });
        }
        describe("AND execution is evaluated", () => {
          let execTx: ContractTransactionResponse;
          let prevACBalance: Balance;
          before(async () => {
            await loadFixture(registerMintSetup);
            prevACBalance = await mocFunctions.assetBalanceOf(deployer);
            execTx = await mocMultiCollateralGuard.execute();
          });
          it("THEN Operations fails with Unhandled Error as non payable contract cannot receive the surplus AC", async () => {
            await expect(execTx).to.emit(mocQueue, "UnhandledError").withArgs(operId, ERROR_SELECTOR.TRANSFER_FAILED);
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
