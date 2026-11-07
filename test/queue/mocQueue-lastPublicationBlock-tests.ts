import { expect } from "chai";
import { ethers, getNamedAccounts, network } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ContractTransactionResponse } from "ethers";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { CONSTANTS, getSigner, mineNBlocks, timedDescribe, tpParams } from "../helpers/utils";
import { MocMultiCollateralGuard } from "../../typechain";
import { assertPrec } from "../helpers/assertHelper";
import { fixtureDeployedMulticollateral } from "../multicollateral/fixture";

timedDescribe("Feature: MocQueue execute using last publication block", () => {
  let mocFunctions = new Array<any>(2);
  let buckets = new Array<any>(2);
  let tps = new Array<any>(2);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let alice: Address;
  let tp0: Address;
  let tp1: Address;
  const minOperWaitingBlk = 4n;
  const maxOperWaitingBlk = 10n;
  const gasLimit = 1_000_000;
  // we use a common shared mintTC params
  let mintTcParams: { from: string; qTC: number; execute: boolean; netParams: { gasLimit: number } };

  let initialBlockNumber: number;
  let op1BlockNumber: number;
  let op2BlockNumber: number;
  let op3BlockNumber: number;
  let op4BlockNumber: number;

  const waitTx = async (op: ContractTransactionResponse) => {
    await mineNBlocks(1, 30);
    return (await op.wait())?.blockNumber || 0;
  };

  describe("GIVEN MocQueues with min waiting set to 4 blocks and max waiting set to 10", function () {
    async function fixture() {
      return fixtureDeployedMulticollateral(2, tpParams);
    }
    before(async () => {
      ({ alice } = await getNamedAccounts());
      mintTcParams = { from: alice, qTC: 1, execute: false, netParams: { gasLimit } };
      const mocContracts = await loadFixture(fixture);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);
      // To simplify single Tx per Operation, we disable automatic allowance and later give full allowance to Alice
      const useAllowance = false;
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts }, useAllowance);
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      tp0 = tps[0].target.toString();
      tp1 = tps[1].target.toString();

      // Give alice infinite allowance to Operate
      await buckets[0].collateralAsset
        .connect(await getSigner(alice))
        .increaseAllowance(buckets[0].mocImpl.target.toString(), CONSTANTS.MAX_UINT256);

      // outside the Promise.all because could revert if min is set before the max
      await buckets[0].mocQueue.setMaxOperWaitingBlk(maxOperWaitingBlk);
      await buckets[0].mocQueue.setMinOperWaitingBlk(minOperWaitingBlk);

      await buckets[1].mocQueue.setMaxOperWaitingBlk(maxOperWaitingBlk);
      await buckets[1].mocQueue.setMinOperWaitingBlk(minOperWaitingBlk);

      initialBlockNumber = await ethers.provider.getBlockNumber();
      await Promise.all([
        // initialize lastUpdateBlock for each price provider
        buckets[0].priceProviders[tp0].setLastPublicationBlock(initialBlockNumber),
        buckets[0].priceProviders[tp1].setLastPublicationBlock(initialBlockNumber),
        buckets[1].priceProviders[tp0].setLastPublicationBlock(initialBlockNumber),
        buckets[1].priceProviders[tp1].setLastPublicationBlock(initialBlockNumber),
      ]);

      // stop hardhat auto mine configuration
      await network.provider.send("evm_setAutomine", [false]);
    });
    after(async () => {
      // re-start hardhat auto mine configuration
      await network.provider.send("evm_setAutomine", [true]);
    });
    describe("GIVEN the useMaxLastPublicationBlock set on true", () => {
      before(async () => {
        await waitTx(await mocMultiCollateralGuard.setUseMaxLastPublicationBlock(true, { gasLimit }));
      });
      describe("AND 2 operations are enqueued and TP0 price is updated", () => {
        before(async () => {
          const tx1 = await mocFunctions[0].mintTC(mintTcParams);
          op1BlockNumber = await waitTx(tx1);

          const tx2 = await mocFunctions[0].mintTC(mintTcParams);
          op2BlockNumber = await waitTx(tx2);

          await buckets[0].priceProviders[tp0].setLastPublicationBlock(op2BlockNumber, { gasLimit });
        });
        describe("AND minOperWaitingBlk passed, 2 operations are enqueued and TP1 price is updated", () => {
          before(async () => {
            // this operation will be executed with price update but after the minOperWaitingBlk
            await mineNBlocks(minOperWaitingBlk);
            const tx3 = await mocFunctions[0].mintTC(mintTcParams);
            op3BlockNumber = await waitTx(tx3);

            await buckets[0].priceProviders[tp1].setLastPublicationBlock(op3BlockNumber, { gasLimit });

            // this operation will be executed without price update by maxOperWaitingBlk
            const tx4 = await mocFunctions[0].mintTC(mintTcParams);
            op4BlockNumber = await waitTx(tx4);
          });
          it("THEN ops 1 and 2 were before the max last publication block, op3 in the same block and op 4 after it", async () => {
            const lastPublicationBlock = await mocMultiCollateralGuard.getLastPublicationBlock(
              true /*useMaxLastPublicationBlock*/,
            );
            expect(op1BlockNumber).to.be.lt(lastPublicationBlock);
            expect(op2BlockNumber).to.be.lt(lastPublicationBlock);
            expect(op3BlockNumber).to.be.eq(lastPublicationBlock);
            expect(op4BlockNumber).to.be.gt(lastPublicationBlock);
          });
          it("THEN min last publication block is the initial block because some TP prices were no updated", async () => {
            const lastPublicationBlock = await mocMultiCollateralGuard.getLastPublicationBlock(
              false /*useMaxLastPublicationBlock*/,
            );
            expect(initialBlockNumber).to.be.eq(lastPublicationBlock);
          });
          it("THEN readyToExecute return true, op1 and 2 can be executed", async function () {
            expect(await mocMultiCollateralGuard.readyToExecute()).to.be.true;
          });
          describe("WHEN queue is executed", () => {
            before(async () => {
              const queueTx = await mocMultiCollateralGuard.execute({ gasLimit });
              await waitTx(queueTx);
            });
            it("THEN op1 and 2 were executed, op 3 was on the queue less than min blocks and op4 was enqueued after last price update", async () => {
              assertPrec(await mocFunctions[0].tcBalanceOf(alice), 2);
            });
            describe("AND queue is executed after minOperWaitingBlk", () => {
              before(async () => {
                await mineNBlocks(minOperWaitingBlk);
                await waitTx(await mocMultiCollateralGuard.execute({ gasLimit }));
              });
              it("THEN op 3 was executed, op4 is still pending", async () => {
                assertPrec(await mocFunctions[0].tcBalanceOf(alice), 3);
              });
              it("THEN readyToExecute return false, op4 cannot be executed", async function () {
                expect(await mocMultiCollateralGuard.readyToExecute()).to.be.false;
              });
              describe("AND queue is executed after maxOperWaitingBlk", () => {
                before(async () => {
                  await mineNBlocks(maxOperWaitingBlk);
                  await waitTx(await mocMultiCollateralGuard.execute({ gasLimit }));
                });
                it("THEN op 4 was executed, queue is empty", async () => {
                  assertPrec(await mocFunctions[0].tcBalanceOf(alice), 4);
                  expect(await buckets[0].mocQueue.isEmpty()).to.be.true;
                });
              });
            });
          });
        });
      });
    });

    describe("GIVEN the useMaxLastPublicationBlock set on false", () => {
      before(async () => {
        await waitTx(await mocMultiCollateralGuard.setUseMaxLastPublicationBlock(false, { gasLimit }));
      });
      describe("AND 3 operations are enqueued and all prices are updated except one (on the same block that the 3th operation)", () => {
        before(async () => {
          const tx1 = await mocFunctions[1].mintTC(mintTcParams);
          op1BlockNumber = await waitTx(tx1);

          const tx2 = await mocFunctions[1].mintTC(mintTcParams);
          op2BlockNumber = await waitTx(tx2);

          // this operation will be executed with price update but after the minOperWaitingBlk
          await mineNBlocks(minOperWaitingBlk);
          const tx3 = await mocFunctions[1].mintTC(mintTcParams);
          op3BlockNumber = await waitTx(tx3);
          await Promise.all([
            buckets[0].priceProviders[tp0].setLastPublicationBlock(op3BlockNumber, { gasLimit }),
            buckets[0].priceProviders[tp1].setLastPublicationBlock(op3BlockNumber, { gasLimit }),
            buckets[1].priceProviders[tp0].setLastPublicationBlock(op3BlockNumber, { gasLimit }),
          ]);
        });
        it("THEN readyToExecute return false, no operations can be executed", async function () {
          expect(await mocMultiCollateralGuard.readyToExecute()).to.be.false;
        });
        describe("WHEN queue is executed", () => {
          before(async () => {
            const execTx = await mocMultiCollateralGuard.execute({ gasLimit });
            await waitTx(execTx);
          });
          it("THEN all operations remain in the queue", async () => {
            assertPrec(await mocFunctions[1].tcBalanceOf(alice), 0);
          });
        });
        describe("AND the last price is updated AND 1 more operation is enqueued", () => {
          before(async () => {
            await buckets[1].priceProviders[tp1].setLastPublicationBlock(op3BlockNumber, {
              gasLimit,
            });
            // this operation will be executed without price update by maxOperWaitingBlk
            const tx4 = await mocFunctions[1].mintTC(mintTcParams);
            op4BlockNumber = await waitTx(tx4);
          });
          it("THEN ops 1 and 2 were before min last publication block, op3 in the same block and op 4 after it", async () => {
            const lastPublicationBlock = await mocMultiCollateralGuard.getLastPublicationBlock(
              false /*useMaxLastPublicationBlock*/,
            );
            expect(op1BlockNumber).to.be.lt(lastPublicationBlock);
            expect(op2BlockNumber).to.be.lt(lastPublicationBlock);
            expect(op3BlockNumber).to.be.eq(lastPublicationBlock);
            expect(op4BlockNumber).to.be.gt(lastPublicationBlock);
          });
          it("THEN readyToExecute return true, op1 and 2 can be executed", async function () {
            expect(await mocMultiCollateralGuard.readyToExecute()).to.be.true;
          });
          describe("WHEN queue is executed", () => {
            before(async () => {
              await waitTx(await mocMultiCollateralGuard.execute({ gasLimit }));
            });
            it("THEN op1 and 2 were executed, op 3 was on the queue less than min blocks and op4 was enqueued after last price update", async () => {
              assertPrec(await mocFunctions[1].tcBalanceOf(alice), 2);
            });
            describe("AND queue is executed after minOperWaitingBlk", () => {
              before(async () => {
                await mineNBlocks(minOperWaitingBlk);
                await waitTx(await mocMultiCollateralGuard.execute({ gasLimit }));
              });
              it("THEN op 3 was executed, op4 is still pending", async () => {
                assertPrec(await mocFunctions[1].tcBalanceOf(alice), 3);
              });
              it("THEN readyToExecute return false, op4 can not be executed", async function () {
                expect(await mocMultiCollateralGuard.readyToExecute()).to.be.false;
              });
              describe("AND queue is executed after maxOperWaitingBlk", () => {
                before(async () => {
                  await mineNBlocks(maxOperWaitingBlk);
                  await waitTx(await mocMultiCollateralGuard.execute({ gasLimit }));
                });
                it("THEN op 4 was executed, queue is empty", async () => {
                  assertPrec(await mocFunctions[1].tcBalanceOf(alice), 4);
                  expect(await buckets[1].mocQueue.isEmpty()).to.be.true;
                });
              });
            });
          });
        });
      });
    });
  });
});
