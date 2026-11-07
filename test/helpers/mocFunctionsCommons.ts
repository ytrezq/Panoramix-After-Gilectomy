// @ts-nocheck
import { ethers, getNamedAccounts } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { MocMultiCollateralGuard } from "../../typechain";
import { getBlock, mineNBlocks, pEth, noVendor } from "./utils";

export const toACmax = q => {
  return typeof q === "number" ? BigInt(q * 10) : typeof q === "string" ? q : BigInt(q) * 10n;
};

const redeemTC =
  (mocImpl, mocCollateralToken) =>
  async ({ from, to, qTC, qACmin = 0, vendor = noVendor, netParams = { gasPrice: 0 }, applyPrecision = true }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTC = pEth(qTC);
      qACmin = pEth(qACmin);
    }
    await mocCollateralToken.connect(signer).increaseAllowance(mocImpl.target.toString(), qTC);
    return mocImpl.connect(signer).redeemTC(qTC, qACmin, to || from, vendor, netParams);
  };

const redeemTP =
  (mocImpl, mocPeggedTokens) =>
  async ({
    i = 0,
    tp,
    from,
    to,
    qTP,
    qACmin = 0,
    vendor = noVendor,
    netParams = { gasPrice: 0 },
    applyPrecision = true,
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTP = pEth(qTP);
      qACmin = pEth(qACmin);
    }
    tp = tp || mocPeggedTokens[i];
    await tp.connect(signer).increaseAllowance(mocImpl.target.toString(), qTP);
    return mocImpl.connect(signer).redeemTP(tp.target.toString(), qTP, qACmin, to || from, vendor, netParams);
  };

const redeemTCandTP =
  (mocImpl, mocCollateralToken, mocPeggedTokens) =>
  async ({
    i = 0,
    tp,
    from,
    to,
    qTC,
    qTP,
    qACmin = 0,
    vendor = noVendor,
    netParams = { gasPrice: 0 },
    applyPrecision = true,
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTP = pEth(qTP);
      qTC = pEth(qTC);
      qACmin = pEth(qACmin);
    }
    tp = tp || mocPeggedTokens[i];
    await tp.connect(signer).increaseAllowance(mocImpl.target.toString(), qTP);
    await mocCollateralToken.connect(signer).increaseAllowance(mocImpl.target.toString(), qTC);
    return mocImpl.connect(signer).redeemTCandTP(tp.target.toString(), qTC, qTP, qACmin, to || from, vendor, netParams);
  };

const liqRedeemTP =
  (mocImpl, mocPeggedTokens) =>
  async ({ i = 0, tp, from, to }) => {
    const signer = await ethers.getSigner(from);
    tp = tp || mocPeggedTokens[i].target.toString();
    return mocImpl.connect(signer).liqRedeemTP(tp, to || from, { gasPrice: 0 });
  };

export const tBalanceOf = token => async account => token.balanceOf(account);
const tpBalanceOf = mocPeggedTokens => async (i, account) => tBalanceOf(mocPeggedTokens[i])(account);
const pokePrice = priceProviders => async (i, newPrice) => priceProviders[i].poke(pEth(newPrice));

const tpTransfer =
  mocPeggedTokens =>
  async ({ i = 0, ...args }) => {
    return tTransfer(mocPeggedTokens[i])(args);
  };

const tTransfer =
  token =>
  async ({ from, to, amount, applyPrecision = true }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      amount = pEth(amount);
    }
    return token.connect(signer).transfer(to, amount, { gasPrice: 0 });
  };

const coinbaseTransfer = async ({ from, to, amount, applyPrecision = true }) => {
  const signer = await ethers.getSigner(from);
  if (applyPrecision) {
    amount = pEth(amount);
  }
  return signer.sendTransaction({
    to,
    value: amount,
  });
};

/**
 * startFromBucket params allows to deterministically execute the queue starting from a given bucket
 */
const executeQueue =
  (mocMultiCollateralGuard: MocMultiCollateralGuard) =>
  async ({
    from,
    startFromBucket = 0,
  }: { from?: Address; recipient?: Address; startFromBucket?: number | "any" } = {}) => {
    let signer;
    if (!from) {
      from = (await getNamedAccounts()).deployer;
    }
    signer = await ethers.getSigner(from);
    // This helps the tests to be more deterministic, as they'll all start execution on the same bucket
    if (startFromBucket != "any") {
      const bucketsAmount = Number(await mocMultiCollateralGuard.getBucketAmount());
      if (bucketsAmount != 1) {
        const block = await getBlock("latest");
        const blocksToMine = (bucketsAmount - ((block.number + 1) % bucketsAmount) + startFromBucket) % bucketsAmount;
        if (blocksToMine) await mineNBlocks(blocksToMine);
      }
    }
    return mocMultiCollateralGuard.connect(signer).execute();
  };

const execWrap = mocMultiCollateralGuard => (execFee, f) => async args => {
  // if not value provided, send enough coinbase to pay execution fee
  if (args.netParams === undefined) args.netParams = { value: execFee };
  else if (args.netParams.value === undefined) args.netParams.value = execFee;
  if (args.execute === false) {
    return f(args);
  }
  await f(args);
  return executeQueue(mocMultiCollateralGuard)();
};

/// Functions shared across different CA implementations
export const mocFunctionsCommons = async ({
  mocImpl,
  mocMultiCollateralGuard,
  mocCollateralToken,
  mocPeggedTokens,
  priceProviders,
  execFee,
}) => {
  const execWrapFnc = execWrap(mocMultiCollateralGuard);
  return {
    redeemTC: execWrapFnc(execFee.tcRedeemExecCost, redeemTC(mocImpl, mocCollateralToken)),
    redeemTP: execWrapFnc(execFee.tpRedeemExecCost, redeemTP(mocImpl, mocPeggedTokens)),
    redeemTCandTP: execWrapFnc(
      execFee.redeemTCandTPExecCost,
      redeemTCandTP(mocImpl, mocCollateralToken, mocPeggedTokens),
    ),
    liqRedeemTP: liqRedeemTP(mocImpl, mocPeggedTokens),
    tcBalanceOf: tBalanceOf(mocCollateralToken),
    tpBalanceOf: tpBalanceOf(mocPeggedTokens),
    tcTransfer: tTransfer(mocCollateralToken),
    tpTransfer: tpTransfer(mocPeggedTokens),
    coinbaseTransfer,
    tTransfer,
    pokePrice: pokePrice(priceProviders),
    executeQueue: executeQueue(mocMultiCollateralGuard),
    execWrap: execWrapFnc,
  };
};
