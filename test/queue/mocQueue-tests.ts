import { expect } from "chai";
import hre, { getNamedAccounts, ethers } from "hardhat";
import { ContractTransactionResponse, Signer } from "ethers";
import { Address } from "hardhat-deploy/types";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import {
  Balance,
  ERRORS,
  OperId,
  OperType,
  ethersGetBalance,
  tpParams,
  getNetworkDeployParams,
  timedDescribe,
  setNextBlockBaseFeePerGas,
  pEth,
  noVendor,
} from "../helpers/utils";
import { ERC20Mock, MocCARC20, MocMultiCollateralGuard, MocQueue, NonPayableMock } from "../../typechain";
import { fixtureDeployedMocRC20 } from "../rc20/fixture";

timedDescribe("Feature: MocQueue with a MocCARC20 bucket", function () {
  const BASEFEE = 20n;
  const gasPrice = BASEFEE * 10n;
  const {
    queueParams: { execCostParams },
    multiCollateralParams: { coinbaseExecFeeRecipient },
  } = getNetworkDeployParams(hre);
  const tcMintExecCost = BigInt(execCostParams.tcMintExecCost);
  const netParams = { value: tcMintExecCost * BASEFEE, gasPrice };
  let mocFunctions: any;
  let executor: Address;
  let txFee: Balance;

  describe("GIVEN a MocQueue MocCARC20 implementation deployed", function () {
    let mocImpl: MocCARC20;
    let mocQueue: MocQueue;
    let mocMultiCollateralGuard: MocMultiCollateralGuard;
    let tp: Address;
    let operId: OperId;
    let alice: Address;
    let aliceSigner: Signer;
    let bob: Address;
    let bobSigner: Signer;
    let executorBalanceBefore: Balance;
    let execFeeRecipientBalanceBefore: Balance;
    let execQueueWithBaseFee: (basefee?: bigint) => Promise<{ tx: ContractTransactionResponse; fee: bigint }>;
    let expectEnqueuerRevert: (queueTx: Promise<ContractTransactionResponse>) => any;
    let commonParams: { sender: Address; recipient: Address; vendor: Address };
    beforeEach(async function () {
      ({ executor, alice, bob } = await getNamedAccounts());
      [aliceSigner, bobSigner] = await Promise.all([alice, bob].map(async it => await ethers.getSigner(it)));
      const fixtureDeploy = fixtureDeployedMocRC20(tpParams.length, tpParams, "MocQueue");
      const mocContracts = await fixtureDeploy();
      mocFunctions = await mocFunctionsRC20(mocContracts);
      let collateralAsset: ERC20Mock;
      ({ mocImpl, mocQueue, mocMultiCollateralGuard, collateralAsset } = mocContracts);
      tp = mocContracts.mocPeggedTokens[0].target.toString();
      commonParams = { sender: alice, recipient: bob, vendor: noVendor };
      mocMultiCollateralGuard = await mocMultiCollateralGuard.connect(await ethers.getSigner(executor));
      // Give CA allowance for Alice and Bob so they can operate
      await Promise.all(
        [aliceSigner, bobSigner].map(async it =>
          collateralAsset.connect(it).increaseAllowance(mocImpl.target.toString(), pEth(1000)),
        ),
      );
      execQueueWithBaseFee = async (baseFee: bigint = BASEFEE) => {
        await setNextBlockBaseFeePerGas(baseFee);
        const tx = await mocMultiCollateralGuard.execute({ gasPrice });

        const txReceipt = await tx.wait();
        return { tx, fee: txReceipt ? txReceipt.gasUsed * txReceipt.gasPrice : 0n };
      };
      await mocQueue.initOperId(42, 42);
      expectEnqueuerRevert = queuePromise =>
        expect(queuePromise).to.be.revertedWithCustomError(mocQueue, ERRORS.NOT_BUCKET);
    });
    describe("WHEN the queue is empty", function () {
      it("THEN isEmpty returns true", async function () {
        expect(await mocQueue.isEmpty()).to.be.true;
      });
      it("THEN readyToExecute return false", async function () {
        expect(await mocMultiCollateralGuard.readyToExecute()).to.be.false;
      });
      it("THEN executing it has no effect", async function () {
        await mocMultiCollateralGuard.execute();
      });
    });
    describe("WHEN an unauthorized account tries to queue a mint TC Operation", function () {
      it("THEN transaction fails with missing role error", async function () {
        await expectEnqueuerRevert(mocQueue.queueMintTC({ qTC: 1, qACmax: 1, ...commonParams }));
      });
    });
    describe("WHEN an unauthorized account tries to queue a redeem TC Operation", function () {
      it("THEN transaction fails with missing role error", async function () {
        await expectEnqueuerRevert(mocQueue.queueRedeemTC({ qTC: 1, qACmin: 1, ...commonParams }));
      });
    });
    describe("WHEN an unauthorized account tries to queue a mint TP Operation", function () {
      it("THEN transaction fails with missing role error", async function () {
        await expectEnqueuerRevert(mocQueue.queueMintTP({ tp, qTP: 1, qACmax: 1, ...commonParams }));
      });
    });
    describe("WHEN an unauthorized account tries to queue a redeem TP Operation", function () {
      it("THEN transaction fails with missing role error", async function () {
        await expectEnqueuerRevert(mocQueue.queueRedeemTP({ tp, qTP: 1, qACmin: 1, ...commonParams }));
      });
    });
    describe("WHEN an unauthorized account tries to queue a mint TPandTC Operation", function () {
      it("THEN transaction fails with missing role error", async function () {
        await expectEnqueuerRevert(mocQueue.queueMintTCandTP({ tp, qTP: 1, qACmax: 1, ...commonParams }));
      });
    });
    describe("WHEN an unauthorized account tries to queue a redeem TPandTC Operation", function () {
      it("THEN transaction fails with missing role error", async function () {
        await expectEnqueuerRevert(mocQueue.queueRedeemTCandTP({ tp, qTC: 1, qTP: 1, qACmin: 1, ...commonParams }));
      });
    });
    describe("WHEN an unauthorized account tries to queue a swap TCforTP Operation", function () {
      it("THEN transaction fails with missing role error", async function () {
        await expectEnqueuerRevert(mocQueue.queueSwapTCforTP({ tp, qTC: 1, qTPmin: 1, qACmax: 1, ...commonParams }));
      });
    });
    describe("WHEN an unauthorized account tries to queue a swap TPforTC Operation", function () {
      it("THEN transaction fails with missing role error", async function () {
        await expectEnqueuerRevert(mocQueue.queueSwapTPforTC({ tp, qTP: 1, qTCmin: 1, qACmax: 1, ...commonParams }));
      });
    });
    describe("WHEN an unauthorized account tries to queue a swap TPforTP Operation", function () {
      it("THEN transaction fails with missing role error", async function () {
        await expectEnqueuerRevert(
          mocQueue.queueSwapTPforTP({ tpFrom: tp, tpTo: tp, qTP: 1, qTPmin: 1, qACmax: 1, ...commonParams }),
        );
      });
    });
    describe("WHEN both Alice and Bob queue a valid operation each", function () {
      let queueTxAlice: ContractTransactionResponse;
      let queueTxBob: ContractTransactionResponse;
      let execTx: ContractTransactionResponse;
      beforeEach(async function () {
        operId = await mocQueue.operIdCount();
        const qTC = pEth(10);
        const qACmax = pEth(100);
        await setNextBlockBaseFeePerGas(BASEFEE);
        queueTxAlice = await mocImpl.connect(aliceSigner).mintTC(qTC, qACmax, alice, noVendor, netParams);
        await setNextBlockBaseFeePerGas(BASEFEE);
        queueTxBob = await mocImpl.connect(bobSigner).mintTC(qTC, qACmax, bob, noVendor, netParams);
      });
      it("THEN readyToExecute return true", async function () {
        expect(await mocMultiCollateralGuard.readyToExecute()).to.be.true;
      });
      it("THEN two operation queued event are emitted", async function () {
        await expect(queueTxAlice)
          .to.emit(mocQueue, "OperationQueued")
          .withArgs(mocImpl.target.toString(), operId, OperType.mintTC);
        await expect(queueTxBob)
          .to.emit(mocQueue, "OperationQueued")
          .withArgs(mocImpl.target.toString(), operId + 1n, OperType.mintTC);
      });
      it("THEN mocMultiCollateralGuardBalance receives coinbase for those two operations", async function () {
        const mocMultiCollateralGuardBalance = await ethersGetBalance(mocMultiCollateralGuard.target.toString());
        expect(mocMultiCollateralGuardBalance).to.be.equal(tcMintExecCost * 2n * BASEFEE);
      });
      describe("AND an authorized user tries to receive the execution fee on a non payable contract", () => {
        let nonPayable: NonPayableMock;
        beforeEach(async () => {
          const factory = await ethers.getContractFactory("NonPayableMock");
          nonPayable = await factory.deploy({ gasPrice });
          await mocMultiCollateralGuard.setCoinbaseExecFeeRecipient(nonPayable.target, { gasPrice });
        });
        it("THEN CoinbaseExecFeePaymentFailed event is emitted because contract cannot receive the execution fee", async () => {
          ({ tx: execTx } = await execQueueWithBaseFee());
          await expect(execTx)
            .to.emit(mocMultiCollateralGuard, "CoinbaseExecFeePaymentFailed")
            .withArgs(tcMintExecCost * 2n * BASEFEE);
          // execution fees remain in the mocMultiCollateralGuard
          const mocMultiCollateralGuardBalance = await ethersGetBalance(mocMultiCollateralGuard.target.toString());
          expect(mocMultiCollateralGuardBalance).to.be.equal(tcMintExecCost * 2n * BASEFEE);
        });
      });
      describe("AND queue is executed", function () {
        beforeEach(async function () {
          executorBalanceBefore = await ethersGetBalance(executor);
          execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
          ({ tx: execTx, fee: txFee } = await execQueueWithBaseFee());
        });
        it("THEN two operation executed event are emitted", async function () {
          await expect(execTx).to.emit(mocQueue, "OperationExecuted").withArgs(executor, operId);
          await expect(execTx)
            .to.emit(mocQueue, "OperationExecuted")
            .withArgs(executor, operId + 1n);
        });
        it("THEN execution Fees are delivered", async function () {
          const mocMultiCollateralGuardBalance = await ethersGetBalance(mocMultiCollateralGuard.target.toString());
          expect(mocMultiCollateralGuardBalance).to.be.equal(0);
          const exeFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
          const expectedBalance = execFeeRecipientBalanceBefore + tcMintExecCost * 2n * BASEFEE;
          expect(exeFeeRecipientBalanceAfter).to.be.equal(expectedBalance);
        });
        it("THEN executor is charged with tx fee and does not receive execution fee", async function () {
          const executorBalanceAfter = await ethersGetBalance(executor);
          expect(executorBalanceAfter).to.be.equal(executorBalanceBefore - txFee);
        });
        it("THEN readyToExecute return false", async function () {
          expect(await mocMultiCollateralGuard.readyToExecute()).to.be.false;
        });
      });
      describe("WHEN updateExecutionCosts is invoked increasing the fee", () => {
        let newTcMintExecCost: bigint;
        beforeEach(async function () {
          newTcMintExecCost = (await mocQueue.execCost(OperType.mintTC)) + 1000n;
          const execCostParamsToUpdate = Object.assign({}, execCostParams, { tcMintExecCost: newTcMintExecCost });
          await mocQueue.updateExecutionCosts(execCostParamsToUpdate, { gasPrice });
        });
        it("THEN exec fee gets updated", async function () {
          const actualTcMintExecCost = await mocQueue.execCost(OperType.mintTC);
          expect(newTcMintExecCost, "tcMintExecCost").to.be.equal(actualTcMintExecCost);
        });
        describe("AND queue is executed", function () {
          beforeEach(async function () {
            execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
            ({ fee: txFee } = await execQueueWithBaseFee());
          });
          it("THEN old execution fees are delivered and mocMultiCollateralGuard balance is 0", async function () {
            const mocMultiCollateralGuardBalance = await ethersGetBalance(mocMultiCollateralGuard.target.toString());
            expect(mocMultiCollateralGuardBalance).to.be.equal(0);
            const execFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
            // prev balance + execFee * BASEFEE paid by two TcMint Operations
            const expectedBalance = execFeeRecipientBalanceBefore + tcMintExecCost * 2n * BASEFEE;
            expect(execFeeRecipientBalanceAfter).to.be.equal(expectedBalance);
          });
        });
        describe("AND funds are sent to mocMultiCollateralGuard to to cover the fees difference", () => {
          beforeEach(async function () {
            const [deployer] = await ethers.getSigners();
            await deployer.sendTransaction({
              to: mocMultiCollateralGuard.target.toString(),
              value: 2000n * BASEFEE,
              gasPrice,
            });
          });
          describe("AND queue is executed", function () {
            beforeEach(async function () {
              execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
              ({ fee: txFee } = await execQueueWithBaseFee());
            });
            it("THEN new execution fees are delivered and mocMultiCollateralGuard balance is 0", async function () {
              const mocMultiCollateralGuardBalance = await ethersGetBalance(mocMultiCollateralGuard.target.toString());
              expect(mocMultiCollateralGuardBalance).to.be.equal(0);
              const execFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
              // prev balance + execFee * BASEFEE paid by two TcMint Operations
              const expectedBalance = execFeeRecipientBalanceBefore + newTcMintExecCost * 2n * BASEFEE;
              expect(execFeeRecipientBalanceAfter).to.be.equal(expectedBalance);
            });
          });
        });
      });
      describe("WHEN updateExecutionCosts is invoked decreasing the fee", () => {
        let newTcMintExecCost: bigint;
        beforeEach(async function () {
          newTcMintExecCost = tcMintExecCost - 1000n;
          const execCostParamsToUpdate = Object.assign({}, execCostParams, { tcMintExecCost: newTcMintExecCost });
          await mocQueue.updateExecutionCosts(execCostParamsToUpdate, { gasPrice });
        });
        it("THEN exec fee gets updated", async function () {
          const actualTcMintExecCost = await mocQueue.execCost(OperType.mintTC);
          expect(newTcMintExecCost, "tcMintExecCost").to.be.equal(actualTcMintExecCost);
        });
        describe("AND queue is executed", function () {
          beforeEach(async function () {
            execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
            ({ fee: txFee } = await execQueueWithBaseFee());
          });
          it("THEN old execution fees are delivered and the difference remains in the mocMultiCollateralGuard", async function () {
            const mocMultiCollateralGuardBalance = await ethersGetBalance(mocMultiCollateralGuard.target.toString());
            expect(mocMultiCollateralGuardBalance).to.be.equal((tcMintExecCost - newTcMintExecCost) * 2n * BASEFEE);
            const execFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
            // prev balance + execFee * BASEFEE paid by two TcMint Operations
            const expectedBalance = execFeeRecipientBalanceBefore + newTcMintExecCost * 2n * BASEFEE;
            expect(execFeeRecipientBalanceAfter).to.be.equal(expectedBalance);
          });
        });
      });
    });
    describe("WHEN Bob tries to register an operation, sending less execution fees than expected", function () {
      it("THEN Tx fails with wrong execution fee", async function () {
        const queueTx = mocFunctions.mintTC({ from: bob, qTC: 10, qACmax: 1, execute: false, netParams: { value: 1 } });
        await expect(queueTx).to.be.revertedWithCustomError(mocQueue, ERRORS.WRONG_EXEC_FEES);
      });
    });
    describe("WHEN Alice tries to register an operation, sending far more execution fees than expected", function () {
      let queueTx: ContractTransactionResponse;
      beforeEach(async function () {
        queueTx = mocFunctions.mintTC({ from: alice, qTC: 10, qACmax: 1, execute: false, netParams: { value: 5e10 } });
      });
      it("THEN Tx fails with wrong execution fee", async function () {
        await expect(queueTx).to.be.revertedWithCustomError(mocQueue, ERRORS.WRONG_EXEC_FEES);
      });
    });
    describe("WHEN Bob registers an invalid operation, and Alice a valid afterwards", function () {
      let execTx: ContractTransactionResponse;
      // Alice base fee had a 10% increase
      const newBasefee = BigInt(Number(BASEFEE) * 1.1);
      beforeEach(async function () {
        execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
        operId = await mocQueue.operIdCount();
        const qTC = pEth(10);
        let qACmax = pEth(1);
        await setNextBlockBaseFeePerGas(BASEFEE);
        let tx = await mocImpl.connect(bobSigner).mintTC(qTC, qACmax, bob, noVendor, netParams);
        await tx.wait();
        qACmax = pEth(100);
        await setNextBlockBaseFeePerGas(newBasefee);
        const newNetParams = { value: tcMintExecCost * newBasefee, gasPrice };
        tx = await mocImpl.connect(aliceSigner).mintTC(qTC, qACmax, alice, noVendor, newNetParams);
        await tx.wait();
      });
      describe("AND queue is executed", function () {
        beforeEach(async function () {
          ({ tx: execTx, fee: txFee } = await execQueueWithBaseFee(newBasefee));
        });
        it("THEN one OperationError event is emitted for Bob", async function () {
          await expect(execTx).to.emit(mocQueue, "OperationError");
        });
        it("THEN two operation executed event are emitted", async function () {
          await expect(execTx).to.emit(mocQueue, "OperationExecuted").withArgs(executor, operId);
          await expect(execTx)
            .to.emit(mocQueue, "OperationExecuted")
            .withArgs(executor, operId + 1n);
        });
        it("THEN execution Fees are delivered the same", async function () {
          const mocMultiCollateralGuardBalance = await ethersGetBalance(mocMultiCollateralGuard.target.toString());
          expect(mocMultiCollateralGuardBalance).to.be.equal(0);
          const execFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
          // prev balance + execFee * BASEFEE paid by two TcMint Operations
          const expectedBalance = execFeeRecipientBalanceBefore + tcMintExecCost * (BASEFEE + newBasefee);
          expect(execFeeRecipientBalanceAfter).to.be.equal(expectedBalance);
        });
      });
    });
    describe("WHEN if more than max batch size valid operations are queued", function () {
      let execTx: ContractTransactionResponse;
      const maxSize = 15n;
      beforeEach(async function () {
        operId = await mocQueue.operIdCount();
        // queues maxSize + 1 mintTC operations
        for (let i = 0; i < Number(maxSize) + 1; i++) {
          await setNextBlockBaseFeePerGas(BASEFEE);
          let signer = i % 2 == 0 ? aliceSigner : bobSigner;
          await (
            await mocImpl.connect(signer).mintTC(i, i * 100, i % 2 == 0 ? alice : bob, noVendor, netParams)
          ).wait();
        }
      });
      describe("AND queue is executed", function () {
        beforeEach(async function () {
          ({ tx: execTx } = await execQueueWithBaseFee());
        });
        it("THEN only max batch size operations are executed", async function () {
          await expect(execTx)
            .to.emit(mocQueue, "OperationExecuted")
            .withArgs(executor, operId + (maxSize - 1n));
          expect(await mocQueue.firstOperId()).to.be.equal(operId + maxSize);
        });
        describe("AND if queue is executed again after a basefee increase", function () {
          const newBasefee = BigInt(Number(BASEFEE) * 1.2);
          beforeEach(async function () {
            executorBalanceBefore = await ethersGetBalance(executor);
            execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
            ({ tx: execTx, fee: txFee } = await execQueueWithBaseFee(newBasefee));
          });
          it("THEN the remaining operations are executed", async function () {
            await expect(execTx)
              .to.emit(mocQueue, "OperationExecuted")
              .withArgs(executor, operId + maxSize);
            expect(await mocQueue.firstOperId()).to.be.equal(operId + maxSize + 1n);
          });
          it("THEN accumulated execution Fees are delivered to the receiver account", async function () {
            const execFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
            const expectedBalance = execFeeRecipientBalanceBefore + tcMintExecCost * BASEFEE;
            expect(execFeeRecipientBalanceAfter).to.be.equal(expectedBalance);
          });
          it("THEN executor is only charged with tx fee", async function () {
            const executorBalanceAfter = await ethersGetBalance(executor);
            expect(executorBalanceAfter).to.be.equal(executorBalanceBefore - txFee);
          });
        });
        describe("AND if queue is executed again after a basefee decrease", function () {
          const newBasefee = BigInt(Number(BASEFEE) * 0.7);
          beforeEach(async function () {
            execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
            ({ tx: execTx, fee: txFee } = await execQueueWithBaseFee(newBasefee));
          });
          it("THEN the remaining operations are executed", async function () {
            await expect(execTx)
              .to.emit(mocQueue, "OperationExecuted")
              .withArgs(executor, operId + maxSize);
            expect(await mocQueue.firstOperId()).to.be.equal(operId + maxSize + 1n);
          });
          it("THEN less than accumulated execution Fees are delivered to the receiver account", async function () {
            const execFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
            const expectedBalance = execFeeRecipientBalanceBefore + tcMintExecCost * newBasefee;
            expect(execFeeRecipientBalanceAfter).to.be.equal(expectedBalance);
          });
          it("THEN the base fee difference remain in the MC contract", async function () {
            const mcBalanceAfter = await ethersGetBalance(mocMultiCollateralGuard.target.toString());
            const expectedMcBalance = tcMintExecCost * (BASEFEE - newBasefee);
            expect(mcBalanceAfter).to.be.equal(expectedMcBalance);
          });
        });
      });
    });
  });
});
