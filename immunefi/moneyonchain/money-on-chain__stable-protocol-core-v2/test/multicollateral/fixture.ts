import { deployments, ethers, getNamedAccounts } from "hardhat";
import {
  ERC20Mock,
  ERC20Mock__factory,
  MocMultiCollateralGuard,
  MocMultiCollateralGuard__factory,
  MocQueue,
  MocQueue__factory,
  MocRC20,
  MocVendors,
  MocVendors__factory,
  PriceProviderMock,
  PriceProviderMock__factory,
  MocCARC20,
  MocCARC20__factory,
  MocCACoinbase,
  MocCACoinbase__factory,
  MocRC20__factory,
} from "../../typechain";
import { CONSTANTS, deployAndAddPeggedTokens, deployBucket, pEth, time, tpParams } from "../helpers/utils";

export const fixtureDeployedMulticollateral = async (
  amountPegTokens: number,
  tpParams?: any,
  amountExtraRC20Buckets: number = 0,
  tpsToAdd?: any,
): Promise<{
  mocBucketContracts: {
    mocImpl: MocCARC20 | MocCACoinbase;
    mocQueue: MocQueue;
    mocCollateralToken: MocRC20;
    priceProviders: { [key: string]: PriceProviderMock };
    collateralAsset?: ERC20Mock;
  }[];
  mocMultiCollateralGuard: MocMultiCollateralGuard;
  mocPeggedTokens: MocRC20[];
  feeToken: ERC20Mock;
  feeTokenPriceProvider: PriceProviderMock;
  mocVendors: MocVendors;
}> => {
  await deployments.fixture();
  const { deployer, alice, bob, charlie, vendor } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);
  let mocBucketContracts: {
    mocImpl: MocCARC20 | MocCACoinbase;
    mocQueue: MocQueue;
    mocCollateralToken: MocRC20;
    priceProviders: { [key: string]: PriceProviderMock };
    collateralAsset?: ERC20Mock;
  }[] = [];

  const fillPriceProviders = (tps: MocRC20[], values: any[]): { [key: string]: any } => {
    const keys = tps.map(tp => tp.target.toString());
    return keys.reduce(
      (acc, key, index) => {
        acc[key] = index < values.length ? values[index] : undefined;
        acc[index] = acc[key];
        return acc;
      },
      {} as { [key: string]: any },
    );
  };

  const deployedMocCARCContract = await deployments.getOrNull("MocCARC20Proxy");
  if (!deployedMocCARCContract) throw new Error("No MocCARC20Proxy deployed.");
  const mocCARC20: MocCARC20 = MocCARC20__factory.connect(deployedMocCARCContract.address, signer);

  const deployedMocCACoinbaseContract = await deployments.getOrNull("MocCACoinbaseProxy");
  if (!deployedMocCACoinbaseContract) throw new Error("No MocCACoinbaseProxy deployed.");
  const mocCACoinbase: MocCACoinbase = MocCACoinbase__factory.connect(deployedMocCACoinbaseContract.address, signer);

  const deployedMultiCollateralGuard = await deployments.getOrNull("MocMultiCollateralGuardCARC20Proxy");
  if (!deployedMultiCollateralGuard) throw new Error("No MocMultiCollateralGuardCARC20Proxy deployed.");
  const mocMultiCollateralGuard: MocMultiCollateralGuard = MocMultiCollateralGuard__factory.connect(
    deployedMultiCollateralGuard.address,
    signer,
  );

  // all buckets have the same addresses
  const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
  if (!deployedMocExpansionContract) throw new Error("No MocCARC20Expansion deployed.");

  const governorAddress = await mocCARC20.governor();
  const mocVendors: MocVendors = MocVendors__factory.connect(await mocCARC20.mocVendors(), signer);
  const feeToken = ERC20Mock__factory.connect(await mocCARC20.feeToken(), signer);
  const feeTokenPriceProvider = PriceProviderMock__factory.connect(await mocCARC20.feeTokenPriceProvider(), signer);
  const acToken = ERC20Mock__factory.connect(await mocCARC20.acToken(), signer);
  // Fill users accounts with balance so that they can operate
  await Promise.all([deployer, alice, bob, charlie].map(address => acToken.mint(address, pEth(1000000000000))));

  // base bucket has all the TPs
  const { mocPeggedTokens, priceProviders: mocCARC20PriceProviders } = await deployAndAddPeggedTokens(
    mocCARC20,
    amountPegTokens,
    tpParams,
  );

  const peggedTokensToAdd = (tpsToAdd && tpsToAdd[0].map((tp: any) => mocPeggedTokens[tp.index])) || mocPeggedTokens;

  const { priceProviders: mocCACoinbasePriceProviders } = await deployAndAddPeggedTokens(
    mocCACoinbase,
    peggedTokensToAdd.length,
    (tpsToAdd && tpsToAdd[0].map((tp: any) => tp.params)) || tpParams,
    peggedTokensToAdd,
  );

  mocBucketContracts.push({
    mocImpl: mocCARC20,
    mocQueue: MocQueue__factory.connect(await mocCARC20.mocQueue(), signer),
    mocCollateralToken: MocRC20__factory.connect(await mocCARC20.tcToken(), signer),
    priceProviders: fillPriceProviders(mocPeggedTokens, mocCARC20PriceProviders),
    collateralAsset: acToken,
  });

  mocBucketContracts.push({
    mocImpl: mocCACoinbase,
    mocQueue: MocQueue__factory.connect(await mocCACoinbase.mocQueue(), signer),
    mocCollateralToken: MocRC20__factory.connect(await mocCACoinbase.tcToken(), signer),
    priceProviders: fillPriceProviders(peggedTokensToAdd, mocCACoinbasePriceProviders),
  });

  // use same liquidation params for all the buckets
  const liqParams = {
    acCoinbasePriceProvider: await mocMultiCollateralGuard.acCoinbasePriceProvider(mocCARC20.target.toString()),
    rebalanceExecFeeRecipient: ethers.Wallet.createRandom(),
    rtcThrld: await mocMultiCollateralGuard.rtcThrld(mocCARC20.target.toString()),
    microLiquidationThrld: await mocMultiCollateralGuard.microLiquidationThrld(mocCARC20.target.toString()),
    penaltyRate: await mocMultiCollateralGuard.penaltyRate(mocCARC20.target.toString()),
  };

  const mocSwappers = [CONSTANTS.ZERO_ADDRESS]; // simplify deployment, mocSwappers are correctly set in rebalance tests
  // add MoC Coinbase bucket to the MultiCollateralGuard
  await mocMultiCollateralGuard.addBucket(mocCACoinbase.target.toString(), liqParams, mocSwappers);
  // Assign RRC20 mocMultiCollateralGuard to coinbase bucket, as by default, deployment uses it's own
  await mocBucketContracts[1].mocQueue.setMocMultiCollateralGuard(mocMultiCollateralGuard.target.toString());

  // set MoC Coinbase Fee Token with same than other buckets
  await mocCACoinbase.setFeeTokenParams(feeToken.target.toString(), feeTokenPriceProvider.target.toString());

  for (let i = 0; i < amountExtraRC20Buckets; i++) {
    const { mocCARC20, acToken, tcToken, mocQueue } = await deployBucket({
      governorAddress,
      mocMultiCollateralGuardAddress: mocMultiCollateralGuard.target.toString(),
      mocCoreExpansionAddress: deployedMocExpansionContract.address,
      mocVendorsAddress: mocVendors.target.toString(),
      feeTokenAddress: feeToken.target.toString(),
      feeTokenPriceProviderAddress: feeTokenPriceProvider.target.toString(),
    });

    const peggedTokensToAdd =
      (tpsToAdd && tpsToAdd[i + 1].map((tp: any) => mocPeggedTokens[tp.index])) || mocPeggedTokens;

    const { priceProviders } = await deployAndAddPeggedTokens(
      mocCARC20,
      peggedTokensToAdd.length,
      (tpsToAdd && tpsToAdd[i + 1].map((tp: any) => tp.params)) || tpParams,
      peggedTokensToAdd,
    );

    mocBucketContracts.push({
      mocImpl: mocCARC20,
      mocQueue: MocQueue__factory.connect(mocQueue.target.toString(), signer),
      collateralAsset: acToken,
      priceProviders: fillPriceProviders(peggedTokensToAdd, priceProviders),
      mocCollateralToken: tcToken,
    });

    // simplify deployment, mocSwappers are correctly set in rebalance tests
    mocSwappers.push(CONSTANTS.ZERO_ADDRESS);
    // add new MoC bucket to the MultiCollateralGuard
    await mocMultiCollateralGuard.addBucket(mocCARC20.target.toString(), liqParams, mocSwappers);
  }

  // initialize vendor with 10% markup
  await mocVendors.setVendorMarkup(vendor, pEth(0.1));
  await time.increase(await mocVendors.COOLDOWN());

  return {
    mocBucketContracts,
    mocMultiCollateralGuard,
    mocPeggedTokens,
    mocVendors,
    feeToken,
    feeTokenPriceProvider,
  };
};

const bucket1TPsToAddCase1 = [
  {
    index: 1,
    params: { ...tpParams[1], price: tpParams[1].price / 2n },
  },
  {
    index: 0,
    params: { ...tpParams[0], price: tpParams[0].price / 2n },
  },
  {
    index: 2,
    params: { ...tpParams[2], price: tpParams[2].price / 2n },
  },
];
const bucket2TPsToAddCase1 = [
  {
    index: 0,
    params: { ...tpParams[0], price: tpParams[0].price / 3n },
  },
  {
    index: 2,
    params: { ...tpParams[2], price: tpParams[2].price / 3n },
  },
  {
    index: 1,
    params: { ...tpParams[1], price: tpParams[1].price / 3n },
  },
];

export function fixtureCase1() {
  return fixtureDeployedMulticollateral(3, tpParams, 1, [bucket1TPsToAddCase1, bucket2TPsToAddCase1]);
}

export function fixtureLiquidation() {
  return fixtureDeployedMulticollateral(3, tpParams, 1, [bucket1TPsToAddCase1, bucket2TPsToAddCase1]);
}

export function fixtureLiquidation2() {
  return fixtureDeployedMulticollateral(1, tpParams, 1);
}

export function fixtureFork() {
  return fixtureDeployedMulticollateral(1);
}

export function fixtureFork2() {
  return fixtureDeployedMulticollateral(1, undefined, 1);
}

const bucket1TPsToAddCase2 = [
  {
    index: 0,
    params: { ...tpParams[0], tpCtarg: pEth(2.5) },
  },
  {
    index: 1,
    params: { ...tpParams[1], tpCtarg: pEth(8) },
  },
];

export function fixtureCase2() {
  return fixtureDeployedMulticollateral(2, tpParams, 0, [bucket1TPsToAddCase2]);
}
