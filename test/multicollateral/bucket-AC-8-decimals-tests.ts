import { expect } from "chai";
import { ethers, getNamedAccounts, network } from "hardhat";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { ContractTransactionResponse } from "ethers";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { mocFunctionsRC20 } from "../helpers/mocFunctionsRC20";
import { mocFunctionsCoinbase } from "../helpers/mocFunctionsCoinbase";
import { CONSTANTS, deployAndInitTC, pEth, timedDescribe, tpParamsDefault } from "../helpers/utils";
import { MocMultiCollateralGuard, MocRC20Decimals__factory } from "../../typechain";
import { fixtureDeployedMulticollateral } from "./fixture";

timedDescribe("Feature: multicollateral bucket AC 8 decimals", function () {
  let mocFunctions = new Array<any>(3);
  let buckets = new Array<any>(3);
  let tps = new Array<any>(1);
  let mocMultiCollateralGuard: MocMultiCollateralGuard;
  let tp0: Address;
  let executionTx: ContractTransactionResponse;
  let deployer: Address;
  let alice: Address;
  const decimals = 8n;
  const shift = 10n ** decimals;
  const rightShift = (qAC: bigint) => qAC / shift;
  const leftShift = (qAC: bigint) => qAC * shift;
  const noVendor = CONSTANTS.ZERO_ADDRESS;

  describe("GIVEN 3 Moc implementations deployed with 1 TP added on every buckets. Bucket 0 uses an AC token with 8 decimals", function () {
    async function fixture() {
      const bucket0TPsToAdd = { ...tpParamsDefault, price: leftShift(pEth(1)), tpEma: leftShift(pEth(1)) };
      const bucketsTPsToAdd = [
        {
          index: 0,
          params: tpParamsDefault,
        },
      ];
      return fixtureDeployedMulticollateral(1, [bucket0TPsToAdd], 1, [bucketsTPsToAdd, bucketsTPsToAdd]);
    }
    before(async function () {
      ({ deployer, alice } = await getNamedAccounts());
      const mocContracts = await loadFixture(fixture);
      ({ mocBucketContracts: buckets, mocPeggedTokens: tps, mocMultiCollateralGuard } = mocContracts);

      tp0 = tps[0].target.toString();
      await buckets[0].collateralAsset.setDecimals(decimals);

      const mocRC20address = (
        await deployAndInitTC({
          adminAddress: await buckets[0].mocImpl.target,
          governorAddress: await buckets[0].mocImpl.governor(),
          decimals: 8n,
        })
      ).target.toString();

      // set the new TC token with 8 decimals for bucket 0
      await network.provider.send("hardhat_setStorageAt", [
        buckets[0].mocImpl.target.toString(),
        ethers.toQuantity(307), // Slot tcToken
        ethers.zeroPadValue(mocRC20address, 32),
      ]);
      buckets[0].mocCollateralToken = MocRC20Decimals__factory.connect(
        mocRC20address,
        await ethers.getSigner(deployer),
      );
      // expect the new token to be set
      expect(await buckets[0].mocImpl.tcToken()).to.be.eq(mocRC20address);

      mocFunctions[0] = await mocFunctionsRC20({ ...buckets[0], ...mocContracts });
      mocFunctions[1] = await mocFunctionsCoinbase({ ...buckets[1], ...mocContracts });
      mocFunctions[2] = await mocFunctionsRC20({ ...buckets[2], ...mocContracts });
    });
    describe("AND alice executes mintTC operations on each bucket", function () {
      const qTC = 100;
      before(async function () {
        const opArgs = { from: alice, qTC, execute: false };
        await Promise.all([
          mocFunctions[0].mintTC({ ...opArgs, qTC: rightShift(pEth(100)), applyPrecision: false }),
          mocFunctions[1].mintTC(opArgs),
          mocFunctions[2].mintTC(opArgs),
        ]);
        executionTx = await mocMultiCollateralGuard.execute();
      });
      it("THEN a TCMinted event is emitted by each bucket", async function () {
        const qAC = 100;
        const commonArgs = {
          from: alice,
          to: alice,
          qTC: pEth(qTC),
          qAC: pEth(qAC * 1.05),
          qACfee: pEth(qAC * 0.05),
          qFeeToken: 0,
          qACVendorMarkup: 0,
          qFeeTokenVendorMarkup: 0,
          vendor: noVendor,
        };
        const bucket0Args = {
          ...commonArgs,
          qTC: rightShift(commonArgs.qTC),
          qAC: rightShift(commonArgs.qAC),
          qACfee: rightShift(commonArgs.qACfee),
        };
        await Promise.all(
          buckets.map(async (bucket, index) => {
            await expect(executionTx)
              .to.emit(bucket.mocQueue, "TCMinted")
              .withArgs(...(index == 0 ? Object.values(bucket0Args) : Object.values(commonArgs)), anyValue);
          }),
        );
      });
      describe("AND alice executes mintTP operations on each bucket", function () {
        const qTP = 10;
        before(async function () {
          const opArgs = { from: alice, qTP, execute: false };
          await Promise.all([
            mocFunctions[0].mintTP(opArgs),
            mocFunctions[1].mintTP(opArgs),
            mocFunctions[2].mintTP(opArgs),
          ]);
          executionTx = await mocMultiCollateralGuard.execute();
        });
        it("THEN a TPMinted event is emitted by each bucket", async function () {
          const qAC = 10;
          const commonArgs = {
            tp: tp0,
            from: alice,
            to: alice,
            qTP: pEth(qTP),
            qAC: pEth(qAC * 1.05),
            qACfee: pEth(qAC * 0.05),
            qFeeToken: 0,
            qACVendorMarkup: 0,
            qFeeTokenVendorMarkup: 0,
            vendor: noVendor,
          };
          const bucket0Args = {
            ...commonArgs,
            qAC: rightShift(commonArgs.qAC),
            qACfee: rightShift(commonArgs.qACfee),
          };
          await Promise.all(
            buckets.map(async (bucket, index) => {
              await expect(executionTx)
                .to.emit(bucket.mocQueue, "TPMinted")
                .withArgs(...(index == 0 ? Object.values(bucket0Args) : Object.values(commonArgs)), anyValue);
            }),
          );
        });
        describe("AND TP price has changed on each bucket 0", function () {
          before(async function () {
            await buckets[0].priceProviders[tp0].poke(leftShift(pEth(2)));
            await buckets[1].priceProviders[tp0].poke(pEth(2));
            await buckets[2].priceProviders[tp0].poke(pEth(2));
          });
          describe("AND alice executes redeemTP operations on each bucket", function () {
            const qTP = 1;
            before(async function () {
              const opArgs = { from: alice, qTP, execute: false };
              await Promise.all([
                mocFunctions[0].redeemTP(opArgs),
                mocFunctions[1].redeemTP(opArgs),
                mocFunctions[2].redeemTP(opArgs),
              ]);
              executionTx = await mocMultiCollateralGuard.execute();
            });
            it("THEN a TPRedeemed event is emitted by each bucket", async function () {
              const qAC = 0.5;
              const commonArgs = {
                tp: tp0,
                from: alice,
                to: alice,
                qTP: pEth(qTP),
                qAC: pEth(qAC * 0.95),
                qACfee: pEth(qAC * 0.05),
                qFeeToken: 0,
                qACVendorMarkup: 0,
                qFeeTokenVendorMarkup: 0,
                vendor: noVendor,
              };
              const bucket0Args = {
                ...commonArgs,
                qAC: rightShift(commonArgs.qAC),
                qACfee: rightShift(commonArgs.qACfee),
              };
              await Promise.all(
                buckets.map(async (bucket, index) => {
                  await expect(executionTx)
                    .to.emit(bucket.mocQueue, "TPRedeemed")
                    .withArgs(...(index == 0 ? Object.values(bucket0Args) : Object.values(commonArgs)), anyValue);
                }),
              );
            });
            describe("AND alice executes redeemTC operations on each bucket", function () {
              const qTC = 1;
              before(async function () {
                const opArgs = { from: alice, qTC, execute: false };
                await Promise.all([
                  mocFunctions[0].redeemTC({
                    ...opArgs,
                    qTC: rightShift(pEth(qTC)),
                    applyPrecision: false,
                  }),
                  mocFunctions[1].redeemTC(opArgs),
                  mocFunctions[2].redeemTC(opArgs),
                ]);
                executionTx = await mocMultiCollateralGuard.execute();
              });
              it("THEN a TCRedeemed event is emitted by each bucket", async function () {
                const pTCac = await buckets[0].mocImpl.getPTCac();
                const qAC = BigInt(qTC) * pTCac;
                const commonArgs = {
                  from: alice,
                  to: alice,
                  qTC: pEth(qTC),
                  qAC: (qAC * 95n) / 100n,
                  qACfee: (qAC * 5n) / 100n,
                  qFeeToken: 0,
                  qACVendorMarkup: 0,
                  qFeeTokenVendorMarkup: 0,
                  vendor: noVendor,
                };
                const bucket0Args = {
                  ...commonArgs,
                  qTC: rightShift(commonArgs.qTC),
                  qAC: rightShift(commonArgs.qAC),
                  qACfee: rightShift(commonArgs.qACfee),
                };
                await Promise.all(
                  buckets.map(async (bucket, index) => {
                    await expect(executionTx)
                      .to.emit(bucket.mocQueue, "TCRedeemed")
                      .withArgs(...(index == 0 ? Object.values(bucket0Args) : Object.values(commonArgs)), anyValue);
                  }),
                );
              });
            });
          });
        });
      });
    });
  });
});
