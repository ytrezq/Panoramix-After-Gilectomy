import { expect } from "chai";
import hre, { getNamedAccounts } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { Balance, ethersGetBalance, getNetworkDeployParams, timedDescribe } from "../helpers/utils";
import { fixtureCase1 } from "./fixture";

timedDescribe("Feature: multicollateral max operations per batch", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let deployer: Address;
  const {
    queueParams: { execCostParams },
    multiCollateralParams: { coinbaseExecFeeRecipient },
  } = getNetworkDeployParams(hre);

  describe("GIVEN 3 Moc implementations deployed", function () {
    before(async function () {
      ({ deployer } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixtureCase1);
      ({ mocBucketContracts: buckets } = mocContracts);
      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });
    });
    describe("WHEN more than max batch size valid operations are queued", function () {
      let execFeeRecipientBalanceBefore: Balance;
      let execTx: ContractTransactionResponse;
      const maxSize = 15;
      const operEnqueued = 20;
      before(async function () {
        await Promise.all(
          Array.from(Array(operEnqueued).keys()).map(i =>
            mocFunctions[i % 2].mintTC({ from: deployer, qTC: i, execute: false }),
          ),
        );
      });
      describe("AND queues are executed", function () {
        before(async function () {
          execFeeRecipientBalanceBefore = await ethersGetBalance(coinbaseExecFeeRecipient);
          execTx = await mocFunctions[0].executeQueue();
        });
        it("THEN only max batch size operations are executed", async function () {
          const receipt = await execTx.wait();
          const expectedTopic = buckets[0].mocQueue.interface.getEvent("OperationExecuted").topicHash;
          const operExecutedEvents = receipt?.logs?.filter(event => event.topics[0] === expectedTopic) || [];
          expect(operExecutedEvents.length).to.be.equal(maxSize);
        });
        describe("AND queues are executed again", function () {
          before(async function () {
            execTx = await mocFunctions[0].executeQueue();
          });
          it("THEN the remaining operations are executed", async function () {
            const receipt = await execTx.wait();
            const expectedTopic = buckets[0].mocQueue.interface.getEvent("OperationExecuted").topicHash;
            const operExecutedEvents = receipt?.logs?.filter(event => event.topics[0] === expectedTopic) || [];
            expect(operExecutedEvents.length).to.be.equal(operEnqueued - maxSize);
          });
          it("THEN execution Fees are delivered to the receiver account", async function () {
            const execFeeRecipientBalanceAfter = await ethersGetBalance(coinbaseExecFeeRecipient);
            expect(execFeeRecipientBalanceAfter - execFeeRecipientBalanceBefore).to.be.equal(
              execCostParams.tcMintExecCost * BigInt(operEnqueued),
            );
          });
        });
      });
    });
  });
});
