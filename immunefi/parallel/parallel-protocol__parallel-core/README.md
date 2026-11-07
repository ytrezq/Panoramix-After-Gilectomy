# Parallel Core

## Summary

This repository own all global contracts used by the Parallel Protocol

## Architecture

The Parallel Core own the following contracts:

- The [AccessManager](./contracts/access/AccessManager.sol) inherit of
  [Openzeppelin AccessManager](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/AccessManager.sol)
  contract. Handle all access for the protocol.

## Documentation Links

## Deployment Addresses

These are the core contracts, the `ParallelAccessManager` of each chain, not a list of the chains where USDp is live.
USDp itself is live on the 24 chains listed in
[parallel-tokens](https://github.com/parallel-protocol/parallel-tokens#deployment-addresses) and in the
[documentation](https://docs.parallel.best/products/parallel-v3/stablecoins-and-savings/usdp-and-susdp).

### Mainnets

#### Ethereum

| Contract              | Explore                                                                                                               |
| --------------------- | --------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0x94Ea8800444017695345156319e96bdB1E355F7a](https://etherscan.io/address/0x94Ea8800444017695345156319e96bdB1E355F7a) |

#### Polygon

| Contract              | Explore                                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| ParallelAccessManager | [0x7Df74BBB6F82eC1BCB1562a30ef5Bf5c326e2811](https://polygonscan.com/address/0x7Df74BBB6F82eC1BCB1562a30ef5Bf5c326e2811) |

#### Fantom

No USDp on Fantom. This access manager owns the legacy MIMO to PRL migration contract (`PeripheralMigrationContract`,
`0xfD28f108e95f4D41daAE9dbfFf707D677985998E`).

| Contract              | Explore                                    |
| --------------------- | ------------------------------------------ |
| ParallelAccessManager | 0x1FF33CF1607Ca109F23A3Fb9Ec5193037eB26306 |

#### Base

| Contract              | Explore                                                                                                               |
| --------------------- | --------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0x0e4e7Ca9D7b1e6293D0713EFEfB4BCA010DeBF46](https://basescan.org/address/0x0e4e7Ca9D7b1e6293D0713EFEfB4BCA010DeBF46) |

#### Optimism

| Contract              | Explore                                                                                                                          |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0x0e4e7Ca9D7b1e6293D0713EFEfB4BCA010DeBF46](https://optimistic.etherscan.io/address/0x0e4e7Ca9D7b1e6293D0713EFEfB4BCA010DeBF46) |

#### Arbitrum

| Contract              | Explore                                                                                                              |
| --------------------- | -------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0x0e4e7Ca9D7b1e6293D0713EFEfB4BCA010DeBF46](https://arbiscan.io/address/0x0e4e7Ca9D7b1e6293D0713EFEfB4BCA010DeBF46) |

#### Sonic

| Contract              | Explore                                                                                                                |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0x8eFb3DED78FbaEF2a4eFe01E01BBD911E4094b78](https://sonicscan.org/address/0x8eFb3DED78FbaEF2a4eFe01E01BBD911E4094b78) |

#### Sei

| Contract              | Explore                                                                                                               |
| --------------------- | --------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](https://seitrace.com/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

#### Avalanche

| Contract              | Explore                                                                                                               |
| --------------------- | --------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](https://snowtrace.io/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

#### BSC

| Contract              | Explore                                                                                                              |
| --------------------- | -------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](https://bscscan.com/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

#### Berachain

| Contract              | Explore                                                                                                               |
| --------------------- | --------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](https://berascan.com/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

#### Scroll

| Contract              | Explore                                                                                                                 |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](https://scrollscan.com/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

#### Mantle

Contracts deployed but never launched: no USDp on Mantle.

| Contract              | Explore                                                                                                                 |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](https://mantlescan.xyz/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

#### Gnosis

| Contract              | Explore                                                                                                                |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](https://gnosisscan.io/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

#### Unichain

| Contract              | Explore                                                                                                              |
| --------------------- | -------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](https://uniscan.xyz/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

#### Ink

| Contract              | Explore                                                                                                                          |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](https://explorer.inkonchain.com/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

#### HyperEvm

| Contract              | Explore                                                                                                                   |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](http://www.hyperscan.com/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

#### Tac

| Contract              | Explore                                                                                                                    |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](http://explorer.tac.build/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

### Testnets

#### Sepolia

| Contract              | Explore                                                                                                                       |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](https://sepolia.etherscan.io/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

#### Arbitrum Sepolia

| Contract              | Explore                                                                                                                      |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| ParallelAccessManager | [0xfD28f108e95f4D41daAE9dbfFf707D677985998E](https://sepolia.arbiscan.io/address/0xfD28f108e95f4D41daAE9dbfFf707D677985998E) |

## Security

### Assumptions

- Roles and wallets assigned to roles will must be tracked
- Admin of AccessManager must be a multisig wallet

### Audits

## Development

### Foundry

[Install foundry following the instructions.](https://book.getfoundry.sh/getting-started/installation)

### Install js dependencies

```bash
bun install
```

### Setup `.env` file

In order to interact with non local networks, you must create an `.env` that has:

```bash
PRIVATE_KEY="PRIVATE KEY"
ALCHEMY_API_KEY="ALCHEMY_API_KEY"
ETHERSCAN_API_KEY="MAINNET_ETHERSCAN_API_KEY"
```

For additional keys, you can check the [`.env.example`](/.env.example) file.

**Warning: always keep your confidential information safe**

### Compile contracts

```bash
bun run compile
```

### Run tests

```bash
bun run test
```

### [Slither](https://github.com/crytic/slither)

```bash
bun run slither
```

You will find other useful commands in the [package.json](./package.json) file.

## Contributing

If you're interested in contributing, please see our [contributions guidelines](./CONTRIBUTING.md).

## Questions & Feedback

For any question or feedback you can use [discord](https://discord.com/invite/mimodao). Don't hesitate to reach out on
[Twitter](https://twitter.com/mimo_labs) as well.

## Licences

All contracts is under the `MIT` License, see [`LICENSE`](./LICENSE).
