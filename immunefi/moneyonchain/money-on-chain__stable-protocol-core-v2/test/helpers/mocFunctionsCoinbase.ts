// @ts-nocheck
import hre, { ethers } from "hardhat";
import { getNetworkDeployParams, noVendor } from "../../scripts/utils";
import { MoCFunctions, ethersGetBalance, pEth } from "./utils";
import { mocFunctionsCommons, toACmax } from "./mocFunctionsCommons";
import { assertPrec } from "./assertHelper";

const gasPrice = 0;

const mintTC =
  (mocImpl, tcMintExecCost: bigint) =>
  async ({
    from,
    to,
    qTC,
    qACmax = toACmax(qTC),
    vendor = noVendor,
    applyPrecision = true,
    execFee = tcMintExecCost,
    netParams = {},
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTC = pEth(qTC);
      qACmax = pEth(qACmax.toString()) + execFee;
    } else qACmax += execFee;
    netParams = { ...{ gasPrice }, ...netParams, ...{ value: qACmax } };
    return mocImpl.connect(signer).mintTC(qTC, to || from, vendor, netParams);
  };

const mintTP =
  (mocImpl, mocPeggedTokens, tpMintExecCost: bigint) =>
  async ({
    i = 0,
    tp,
    from,
    to,
    qTP,
    qACmax = toACmax(qTP),
    vendor = noVendor,
    applyPrecision = true,
    execFee = tpMintExecCost,
    netParams = {},
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTP = pEth(qTP);
      qACmax = pEth(qACmax.toString()) + execFee;
    } else qACmax += execFee;
    tp = tp || mocPeggedTokens[i].target.toString();
    netParams = { ...{ gasPrice }, ...netParams, ...{ value: qACmax } };
    return mocImpl.connect(signer).mintTP(tp, qTP, to || from, vendor, netParams);
  };

const mintTCandTP =
  (mocImpl, mocPeggedTokens, mintTCandTPExecCost: bigint) =>
  async ({
    i = 0,
    tp,
    from,
    to,
    qTP,
    qACmax = toACmax(qTP),
    vendor = noVendor,
    applyPrecision = true,
    execFee = mintTCandTPExecCost,
    netParams = {},
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTP = pEth(qTP);
      qACmax = pEth(qACmax.toString()) + execFee;
    } else qACmax += execFee;
    tp = tp || mocPeggedTokens[i].target.toString();
    netParams = { ...{ gasPrice }, ...netParams, ...{ value: qACmax } };
    return mocImpl.connect(signer).mintTCandTP(tp, qTP, to || from, vendor, netParams);
  };

const swapTPforTP =
  (mocImpl, mocPeggedTokens, swapTPforTPExecCost: bigint) =>
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
    applyPrecision = true,
    execFee = swapTPforTPExecCost,
    netParams = {},
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTP = pEth(qTP);
      qTPmin = pEth(qTPmin);
      qACmax = pEth(qACmax.toString()) + execFee;
    } else qACmax += execFee;
    tpFrom = tpFrom || mocPeggedTokens[iFrom];
    tpTo = tpTo || mocPeggedTokens[iTo];
    await tpFrom.connect(signer).increaseAllowance(mocImpl.target.toString(), qTP);
    netParams = { ...{ gasPrice }, ...netParams, ...{ value: qACmax } };
    return mocImpl
      .connect(signer)
      .swapTPforTP(tpFrom.target.toString(), tpTo.target.toString(), qTP, qTPmin, to || from, vendor, netParams);
  };

const swapTPforTC =
  (mocImpl, mocPeggedTokens, swapTPforTCExecCost: bigint) =>
  async ({
    i = 0,
    tp,
    from,
    to,
    qTP,
    qTCmin = 0,
    qACmax = toACmax(qTP),
    vendor = noVendor,
    applyPrecision = true,
    execFee = swapTPforTCExecCost,
    netParams = {},
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTP = pEth(qTP);
      qTCmin = pEth(qTCmin);
      qACmax = pEth(qACmax.toString()) + execFee;
    } else qACmax += execFee;
    tp = tp || mocPeggedTokens[i];
    await tp.connect(signer).increaseAllowance(mocImpl.target.toString(), qTP);
    netParams = { ...{ gasPrice }, ...netParams, ...{ value: qACmax } };
    return mocImpl.connect(signer).swapTPforTC(tp.target.toString(), qTP, qTCmin, to || from, vendor, netParams);
  };

const swapTCforTP =
  (mocImpl, mocCollateralToken, mocPeggedTokens, swapTCforTPExecCost: bigint) =>
  async ({
    i = 0,
    tp,
    from,
    to,
    qTC,
    qTPmin = 0,
    qACmax = toACmax(qTC),
    vendor = noVendor,
    applyPrecision = true,
    execFee = swapTCforTPExecCost,
    netParams = {},
  }) => {
    const signer = await ethers.getSigner(from);
    if (applyPrecision) {
      qTC = pEth(qTC);
      qTPmin = pEth(qTPmin);
      qACmax = pEth(qACmax.toString()) + execFee;
    } else qACmax += execFee;
    tp = tp || mocPeggedTokens[i].target.toString();
    await mocCollateralToken.connect(signer).increaseAllowance(mocImpl.target.toString(), qTC);
    netParams = { ...{ gasPrice }, ...netParams, ...{ value: qACmax } };
    return mocImpl.connect(signer).swapTCforTP(tp, qTC, qTPmin, to || from, vendor, netParams);
  };

const assertACResult =
  () =>
  execFee =>
  (...args) => {
    if (typeof args[0] === "number" || typeof args[0] === "string") {
      args[0] = pEth(args[0]);
    }
    return assertPrec(args[0] + execFee, ...args.slice(1));
  };

export const mocFunctionsCoinbase = async ({
  mocImpl,
  mocMultiCollateralGuard,
  mocCollateralToken,
  mocPeggedTokens,
  priceProviders,
}): Promise<MoCFunctions> => {
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
    mintTC: execWrap(execFee.tcMintExecCost, mintTC(mocImpl, execFee.tcMintExecCost)),
    mintTP: execWrap(execFee.tpMintExecCost, mintTP(mocImpl, mocPeggedTokens, execFee.tpMintExecCost)),
    mintTCandTP: execWrap(
      execFee.mintTCandTPExecCost,
      mintTCandTP(mocImpl, mocPeggedTokens, execFee.mintTCandTPExecCost),
    ),
    swapTPforTP: execWrap(
      execFee.swapTPforTPExecCost,
      swapTPforTP(mocImpl, mocPeggedTokens, execFee.swapTPforTPExecCost),
    ),
    swapTPforTC: execWrap(
      execFee.swapTPforTCExecCost,
      swapTPforTC(mocImpl, mocPeggedTokens, execFee.swapTPforTCExecCost),
    ),
    swapTCforTP: execWrap(
      execFee.swapTCforTPExecCost,
      swapTCforTP(mocImpl, mocCollateralToken, mocPeggedTokens, execFee.swapTCforTPExecCost),
    ),
    assetBalanceOf: ethersGetBalance,
    acBalanceOf: ethersGetBalance,
    acTransfer: commonFncs.coinbaseTransfer,
    assertACResult: assertACResult(),
    refreshACBalance: () => {},
    ...commonFncs,
  };
};
