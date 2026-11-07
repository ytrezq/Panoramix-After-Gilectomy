// @ts-nocheck
import hre, { ethers } from "hardhat";
import { getNetworkDeployParams, noVendor } from "../../scripts/utils";
import { MoCFunctions, pEth } from "./utils";
import { mocFunctionsCommons, toACmax, tBalanceOf } from "./mocFunctionsCommons";
import { assertPrec } from "./assertHelper";

const mintTC =
  (mocImpl, collateralAsset, useAllowance: boolean) =>
  async ({ from, to, qTC, qACmax = toACmax(qTC), vendor = noVendor, netParams = {}, applyPrecision = true }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTC = pEth(qTC);
      qACmax = pEth(qACmax.toString());
    }
    if (useAllowance) await collateralAsset.connect(signer).increaseAllowance(mocImpl.target.toString(), qACmax);
    return mocImpl.connect(signer).mintTC(qTC, qACmax, to || from, vendor, netParams);
  };

const mintTP =
  (mocImpl, collateralAsset, mocPeggedTokens, useAllowance: boolean) =>
  async ({
    i = 0,
    tp,
    from,
    to,
    qTP,
    qACmax = toACmax(qTP),
    vendor = noVendor,
    netParams = {},
    applyPrecision = true,
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTP = pEth(qTP);
      qACmax = pEth(qACmax.toString());
    }
    if (useAllowance) await collateralAsset.connect(signer).increaseAllowance(mocImpl.target.toString(), qACmax);
    tp = tp || mocPeggedTokens[i].target.toString();
    return mocImpl.connect(signer).mintTP(tp, qTP, qACmax, to || from, vendor, netParams);
  };

const mintTCandTP =
  (mocImpl, collateralAsset, mocPeggedTokens, useAllowance: boolean) =>
  async ({
    i = 0,
    tp,
    from,
    to,
    qTP,
    qACmax = toACmax(qTP),
    vendor = noVendor,
    netParams = {},
    applyPrecision = true,
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTP = pEth(qTP);
      qACmax = pEth(qACmax.toString());
    }
    tp = tp || mocPeggedTokens[i].target.toString();
    if (useAllowance) await collateralAsset.connect(signer).increaseAllowance(mocImpl.target.toString(), qACmax);
    return mocImpl.connect(signer).mintTCandTP(tp, qTP, qACmax, to || from, vendor, netParams);
  };

const swapTPforTP =
  (mocImpl, collateralAsset, mocPeggedTokens, useAllowance: boolean) =>
  async ({
    iFrom = 0,
    iTo = 1,
    tpFrom,
    tpTo,
    from,
    to,
    qTP,
    qTPmin = 0,
    qACmax = toACmax(qTP),
    vendor = noVendor,
    netParams = {},
    applyPrecision = true,
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTP = pEth(qTP);
      qTPmin = pEth(qTPmin);
      qACmax = pEth(qACmax.toString());
    }
    if (useAllowance) await collateralAsset.connect(signer).increaseAllowance(mocImpl.target.toString(), qACmax);
    tpFrom = tpFrom || mocPeggedTokens[iFrom];
    tpTo = tpTo || mocPeggedTokens[iTo];
    if (useAllowance) await tpFrom.connect(signer).increaseAllowance(mocImpl.target.toString(), qTP);
    return mocImpl
      .connect(signer)
      .swapTPforTP(
        tpFrom.target.toString(),
        tpTo.target.toString(),
        qTP,
        qTPmin,
        qACmax,
        to || from,
        vendor,
        netParams,
      );
  };

const swapTPforTC =
  (mocImpl, collateralAsset, mocPeggedTokens, useAllowance: boolean) =>
  async ({
    i = 0,
    tp,
    from,
    to,
    qTP,
    qTCmin = 0,
    qACmax = toACmax(qTP),
    vendor = noVendor,
    netParams = {},
    applyPrecision = true,
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTP = pEth(qTP);
      qTCmin = pEth(qTCmin);
      qACmax = pEth(qACmax.toString());
    }
    if (useAllowance) await collateralAsset.connect(signer).increaseAllowance(mocImpl.target.toString(), qACmax);
    tp = tp || mocPeggedTokens[i];
    if (useAllowance) await tp.connect(signer).increaseAllowance(mocImpl.target.toString(), qTP);
    return mocImpl
      .connect(signer)
      .swapTPforTC(tp.target.toString(), qTP, qTCmin, qACmax, to || from, vendor, netParams);
  };

const swapTCforTP =
  (mocImpl, collateralAsset, mocCollateralToken, mocPeggedTokens, useAllowance: boolean) =>
  async ({
    i = 0,
    tp,
    from,
    to,
    qTC,
    qTPmin = 0,
    qACmax = toACmax(qTC),
    vendor = noVendor,
    netParams = {},
    applyPrecision = true,
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTC = pEth(qTC);
      qTPmin = pEth(qTPmin);
      qACmax = pEth(qACmax.toString());
    }
    tp = tp || mocPeggedTokens[i].target.toString();
    if (useAllowance) await mocCollateralToken.connect(signer).increaseAllowance(mocImpl.target.toString(), qTC);
    if (useAllowance) await collateralAsset.connect(signer).increaseAllowance(mocImpl.target.toString(), qACmax);
    return mocImpl.connect(signer).swapTCforTP(tp, qTC, qTPmin, qACmax, to || from, vendor, netParams);
  };

export const mocFunctionsRC20 = async (
  { mocImpl, mocMultiCollateralGuard, collateralAsset, mocCollateralToken, mocPeggedTokens, priceProviders },
  useAllowance: boolean = true,
): Promise<MoCFunctions> => {
  const { execCostParams: execFee } = getNetworkDeployParams(hre).queueParams;
  const commonFncs = await mocFunctionsCommons({
    mocImpl,
    mocMultiCollateralGuard,
    mocCollateralToken,
    mocPeggedTokens,
    priceProviders,
    execFee,
  });
  const execWrap = commonFncs.execWrap;
  return {
    mintTC: execWrap(execFee.tcMintExecCost, mintTC(mocImpl, collateralAsset, useAllowance)),
    mintTP: execWrap(execFee.tpMintExecCost, mintTP(mocImpl, collateralAsset, mocPeggedTokens, useAllowance)),
    mintTCandTP: execWrap(
      execFee.mintTCandTPExecCost,
      mintTCandTP(mocImpl, collateralAsset, mocPeggedTokens, useAllowance),
    ),
    swapTPforTP: execWrap(
      execFee.swapTPforTPExecCost,
      swapTPforTP(mocImpl, collateralAsset, mocPeggedTokens, useAllowance),
    ),
    swapTPforTC: execWrap(
      execFee.swapTPforTCExecCost,
      swapTPforTC(mocImpl, collateralAsset, mocPeggedTokens, useAllowance),
    ),
    swapTCforTP: execWrap(
      execFee.swapTCforTPExecCost,
      swapTCforTP(mocImpl, collateralAsset, mocCollateralToken, mocPeggedTokens, useAllowance),
    ),
    assetBalanceOf: tBalanceOf(collateralAsset),
    acBalanceOf: tBalanceOf(collateralAsset),
    assertACResult: () => assertPrec,
    acTransfer: commonFncs.tTransfer(collateralAsset),
    refreshACBalance: () => mocImpl.refreshACBalance(),
    ...commonFncs,
  };
};
