# Overview

This repository contains the source code for contracts and testing suites related to the PRL token migration from MIMO
and the way to bridge it. Details documentation can be found under the [/docs](./docs) folder.

## Repository Structure

- [Broadcast](./broadcast) folder contains Foundry transactions executed by scripts.
- [Contracts](./contracts) folder contains contracts source code.
- [Deploy](./deploy) folder contains hardhat deployment scripts.
- [Deployments](./deployments) folder contains info of contracts deployed per network.
- [Docs](./docs) folder contains all documentation related to contracts.
- [Script](./scripts) folder contains Foundry scripts to interact with onchain contracts.
- [Test](./test) folder contains all tests related to the contracts with mocks and settings.
- [Utils](./utils) folder contains helper functions.

## Contracts Overview

The repository contains 3 types of contract:

- The [`PRL`]('./contracts/principal/PRL.sol) token contract that inherit of Openzeppelin ERC20 and ERC20Permit
  standards.
- The Migrations contracts handled by the
  [`PrincipalMigrationContract`]('./contracts/principal/PrincipalMigrationContract.sol) and
  [`PeripheralMigrationContract`]('./contracts/peripheral/PeripheralMigrationContract.sol) contracts that leveraging on
  [LayerZero's OApp standard](https://docs.layerzero.network/v2/home/protocol/contract-standards#oapp) for migrating
  Mimo from anychain to PRL on anychain.
- The Bridging of PRL, handled by the [`LockBox`]('./contracts/principal/LockBox.sol) and
  [`PeripheralPRL`]('./contracts/peripheral/PeripheralPRL.sol) contracts that leveraging on fork of
  [LayerZero's OFT standard](https://docs.layerzero.network/v2/home/protocol/contract-standards#oft) for allow PRL to be
  omnichain.

See the [documentation](./docs/README.md) for more details.

## Getting Started

### Foundry

Foundry is used for testing and scripting. To
[Install foundry follow the instructions.](https://book.getfoundry.sh/getting-started/installation)

### Install js dependencies

```bash
bun i
```

### Fill the `.env` file with your data

The Foundry script relies solely on the PRIVATE_KEY. The MNEMONIC is used on the Hardhat side and will override the
PRIVATE_KEY if it is defined.

```bash
MNEMONIC=
PRIVATE_KEY=0x...
ALCHEMY_API_KEY=
```

### Compile contracts

```bash
bun run compile
```

### Run tests

```bash
bun run test
```

### Run Coverage

```bash
bun run test:coverage:report
```

You will find other useful commands in the [package.json](./package.json) file.

## Licences

All contracts is under the `MIT` License, see [`LICENSE`](./LICENSE).
