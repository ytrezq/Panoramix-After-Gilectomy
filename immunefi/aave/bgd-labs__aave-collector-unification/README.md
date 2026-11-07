# Aave Collector unification

This repository contains the latest version of the Aave Collector and the proposals to sync Collector implementations across different networks and pools.

At the moment there is quite a lot of divergence between the different collectors, even if they could have the same features and interfaces across all deployments of Aave (v2/v3). As a reference, we have chosen the version from this repository (https://github.com/bgd-labs/aave-ecosystem-reserve-v2), which is currently deployed on the Ethereum V2 pool (https://etherscan.io/address/0x464c71f6c2f760dda6093dcb91c24c39e5d6e18c#readProxyContract), and made a few improvements to it, which are described in details below.

All collectors use an "imperfect" pattern at the moment, based on a "controller of collector" to solve the problem of the proxy admin only being able to call admin functions on the proxy. We are aiming to generalize that controller of the Collector with a ProxyAdmin contract. This helps if in the future more functionality is added to the Collectors, as ProxyAdmin is not limited to the methods explicitly proxied; it is generic.

![collector-permissions-overview](./collector-admin.png)

Also on the networks where two different collectors existed simultaneously for v2 and v3, accumulated assets and rewards will be transferred to the latest version of the collector and the older version will be abandoned.

<br>

## Current proxies and implementations

**Ethereum**

Proxy: [0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c](https://etherscan.io/address/0x464c71f6c2f760dda6093dcb91c24c39e5d6e18c)

Impl: [0x1aa435ed226014407Fa6b889e9d06c02B1a12AF3](https://etherscan.io/address/0x1aa435ed226014407fa6b889e9d06c02b1a12af3)

**Polygon**

Proxy v2: [0x7734280A4337F37Fbf4651073Db7c28C80B339e9](https://polygonscan.com/address/0x7734280a4337f37fbf4651073db7c28c80b339e9)

Proxy v3: [0xe8599F3cc5D38a9aD6F3684cd5CEa72f10Dbc383](https://polygonscan.com/address/0xe8599f3cc5d38a9ad6f3684cd5cea72f10dbc383)

Impl: [0xC773bf5a987b29DdEAC77cf1D48a22a4Ce5B0577](https://polygonscan.com/address/0xc773bf5a987b29ddeac77cf1d48a22a4ce5b0577)

**Avalanche**

Proxy v2: [0x467b92aF281d14cB6809913AD016a607b5ba8A36](https://snowtrace.io/address/0x467b92aF281d14cB6809913AD016a607b5ba8A3))

Impl v2: [0xFC9F4403d28D338F3a2814DF9feBF7e7F20A091C](https://snowtrace.io/address/0xfc9f4403d28d338f3a2814df9febf7e7f20a091c)

Proxy v2: [0x5ba7fd868c40c16f7aDfAe6CF87121E13FC2F7a0](https://snowtrace.io/address/0x5ba7fd868c40c16f7adfae6cf87121e13fc2f7a0)

Impl v3: [0xa6a7b56F27c9C943945E8A636C01E433240700D8](https://snowtrace.io/address/0xa6a7b56f27c9c943945e8a636c01e433240700d8)

**Optimism**
Proxy: [0xB2289E329D2F85F1eD31Adbb30eA345278F21bcf](https://optimistic.etherscan.io/address/0xb2289e329d2f85f1ed31adbb30ea345278f21bcf)

Impl: [0xa6a7b56F27c9C943945E8A636C01E433240700D8](https://optimistic.etherscan.io/address/0xa6a7b56f27c9c943945e8a636c01e433240700d8)

**Arbitrum**

Proxy: [0x053D55f9B5AF8694c503EB288a1B7E552f590710](https://arbiscan.io/address/0x053d55f9b5af8694c503eb288a1b7e552f590710)

Impl: [0xa6a7b56F27c9C943945E8A636C01E433240700D8](https://arbiscan.io/address/0xa6a7b56f27c9c943945e8a636c01e433240700d8)

**Fantom**

Proxy: [0xBe85413851D195fC6341619cD68BfDc26a25b928](https://ftmscan.com/address/0xbe85413851d195fc6341619cd68bfdc26a25b928)

Impl: [0xc0F0cFBbd0382BcE3B93234E4BFb31b2aaBE36aD](https://ftmscan.com/address/0xc0f0cfbbd0382bce3b93234e4bfb31b2aabe36ad)

<br>

## Mainnet & general changes against most up-to-date Collector

As the codebase itself mostly remained the same as in the [currently deployed version](https://github.com/bgd-labs/aave-ecosystem-reserve-v2), its structure simplified a bit and a few improvements were introduced:

- `AaveEcosystemReserveV2` was renamed `Collector`
- several interfaces were combined into one [ICollector](./src/interfaces/ICollector.sol)
- external methods `setFundsAdmin()` and `getNextStreamId()` were added
- storage layout has changed a bit, Reentrancy Guard's `status` and `fundsAdmin` were swapped; an additional method `_initGuard()` was added to rewrite variables during the upgrading of the implementation.
- shared proxy admin [0xD3cF979e676265e4f6379749DECe4708B9A22476](https://etherscan.io/address/0xd3cf979e676265e4f6379749dece4708b9a22476) is set as the admin of the collector's proxy

- [Ethereum code diff](./diffs/mainnet.md)
- [Ethereum Storage layout diff](./diffs/mainnet_layout_diff.md)

<br>

## Arbitrum, Avalanche, Fantom, Optimism, Polygon

The difference from the current version is the addition of streaming support.

- Arbitrum
  - [Code diff](./diffs/arbitrum.md)
  - [Storage layout diff](./diffs/arbitrum_layout_diff.md)
- Avalanche
  - [Code diff](./diffs/avalanche.md)
  - [Storage layout diff](./diffs/avalanche_layout_diff.md)
- Optimism
  - [Code diff](./diffs/optimism.md)
  - [Storage layout diff](./diffs/optimism_layout_diff.md)
- Polygon
  - [Code diff](./diffs/polygon.md)
  - [Storage layout diff](./diffs/polygon_layout_diff.md)

<br>

## Polygon and Avalanche v2 migration

Currently, two different versions of the Collector are used for v2 and v3 pools on Avalanche and Polygon. To combine all funds and use only one instance of the treasury, we are doing the following:

- redeploying the [aToken implementation](https://github.com/bgd-labs/protocol-v2/pull/7/files#diff-970614e9a203f546ac36da22a98f737e5ed418e6554597ddd8286ae4b474b21d) to set the new latest version of the collector. Here is the [diff](./diffs/atoken_diff.md) with the deployed version of the AToken.
- upgrading the implementation of the current v2 collector to migrate all the funds and accumulated rewards to the current treasury

<br>

## Deployment

1. [UpgradeAaveCollectorPayload.sol](./src/contracts/payloads/UpgradeAaveCollectorPayload.sol) payload, which upgrades the implementation of the collector, initializes it with the new funds admin, and sets new proxy admin.
2. [PayloadDeployment.s.sol](./scripts/PayloadDeployment.s.sol) multiple scripts to deploy the payload above on all networks.
3. [MigrateV2CollectorPayload.sol](./src/contracts/payloads/MigrateV2CollectorPayload.sol) is the payload to deploy the new version of the aToken with the updated collector and to upgrade the implementation of the collector to the [MigrationCollector](./src/contracts/payloads/AaveMigrationCollector.sol) to migrate funds and rewards.
4. [PayloadV2Deployment.s.sol](./scripts/PayloadV2Deployment.s.sol) deploys `MigrateV2CollectorPayload` on Avalanche and Polygon.
5. [ProposalDeployment.s.sol](./scripts/ProposalDeployment.s.sol) initiates the proposal for the mainnet and supported L2 networks.

<br>

## Development

This project uses [Foundry](https://getfoundry.sh). See the [book](https://book.getfoundry.sh/getting-started/installation.html) for detailed instructions on how to install and use Foundry.
The template ships with sensible default so you can use the default `foundry` commands without resorting to `MakeFile`.

### Setup

```sh
cp .env.example .env
forge install
```

### Test

```sh
forge test
```
