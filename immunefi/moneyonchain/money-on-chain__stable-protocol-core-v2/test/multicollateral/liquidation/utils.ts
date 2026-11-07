import { ethers } from "hardhat";
import {
  DataProviderMock__factory,
  MocMultiCollateralGuard,
  MocSwapperV3__factory,
  WrapperMock__factory,
} from "../../../typechain";
import { pEth } from "../../helpers/utils";

export async function calcBucketScore(bucket: any) {
  const [bucketCoverage, bucketACAvailable, bucketCtargema] = await Promise.all([
    bucket.mocImpl.getCglb(),
    bucket.mocImpl.getTotalACavailable(),
    bucket.mocImpl.getCtargemaCA(),
  ]);
  return (bucketCoverage * bucketACAvailable) / bucketCtargema;
}

export async function addSwappers(mocMultiCollateralGuard: MocMultiCollateralGuard, buckets: any[]) {
  const fee = 3000n;
  const [signer] = await ethers.getSigners();
  // by default the buckets have a maxACtoSwap of 10000
  const dataProviderMock = await (await ethers.getContractFactory("DataProviderMock")).deploy(pEth(10000));
  const v3SwapRouterMock = await (await ethers.getContractFactory("V3SwapRouterMock")).deploy();
  const coinbaseWrapperMock = await (await ethers.getContractFactory("WrapperMock")).deploy();
  const mocSwapperV3Impl = await (await ethers.getContractFactory("MocSwapperV3")).deploy();
  const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
  const erc1967Proxy = await erc1967ProxyFactory.deploy(await mocSwapperV3Impl.target.toString(), "0x");
  // deploy MocSwapperV3 with bucket 0 and 1
  const mocSwapperV3 = MocSwapperV3__factory.connect(await erc1967Proxy.target.toString(), signer);
  await mocSwapperV3.initialize(
    await mocMultiCollateralGuard.governor(),
    await mocMultiCollateralGuard.pauser(),
    v3SwapRouterMock.target.toString(),
    coinbaseWrapperMock.target.toString(),
  );

  // set MocSwapperV3 on bucket 0 and 1
  await mocMultiCollateralGuard.setMocSwapper(
    buckets[0].mocImpl.target.toString(),
    buckets[1].mocImpl.target.toString(),
    mocSwapperV3.target.toString(),
  );
  for (let i = 0; i < buckets.length; i++) {
    for (let j = 0; j < buckets.length; j++) {
      if (i != j) {
        await mocSwapperV3.setPool(
          await buckets[i].mocImpl.acToken(),
          await buckets[j].mocImpl.acToken(),
          fee,
          dataProviderMock.target.toString(),
        );
        await mocSwapperV3.setPool(
          await buckets[j].mocImpl.acToken(),
          await buckets[i].mocImpl.acToken(),
          fee,
          dataProviderMock.target.toString(),
        );
        await mocMultiCollateralGuard.setMocSwapper(
          buckets[j].mocImpl.target.toString(),
          buckets[i].mocImpl.target.toString(),
          mocSwapperV3.target.toString(),
        );
      }
    }
  }
  return {
    maxACtoSwapProvider: DataProviderMock__factory.connect(dataProviderMock.target.toString(), signer),
    coinbaseRC20Wrapper: WrapperMock__factory.connect(coinbaseWrapperMock.target.toString(), signer),
    mocSwapperV3,
  };
}
