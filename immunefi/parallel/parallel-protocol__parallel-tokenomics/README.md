# Parallel Tokenomics

## 1. Overview

The Parallel Tokenomics system consists of smart contracts that enable:

- Forwarding fees to the main fee distributor on the destination chain (SideChainFeeDistributor)
- Distributing protocol-generated fees to registered fee receivers (MainFeeDistributor)
- Staking PRL tokens to earn rewards through:
  - Single staking (sPRL1): Direct PRL staking with time-lock and rewards
  - Balancer Pool staking (sPRL2): 80PRL/20WETH pool tokens staked into Aura.finance
- Distributing rewards to sPRL1/sPRL2 users via off-chain calculations and merkle proofs (RewardMerkleDistributor)

### Key Features

- Time-lock staking mechanism with configurable early withdrawal penalties
- Dual staking options with different risk-reward profiles
- Cross-chain fee collection and distribution
- Merkle-based reward distribution system
- Integration with Balancer and Aura.finance protocols

### Requirements

- PRL tokens for staking (sPRL2 requires Balancer V3 and Aura.finance)
- ETH/WETH for sPRL2 liquidity provision
- Expected supported networks:
  - sPRL(s) tokens: Mainnet (as BalancerV3 and Aura.finance are required)
  - RewardMerkleDistributor: Mainnet
  - MainFeeDistributor: Mainnet
  - SideChainFeeDistributor: Polygon, Fantom

The high-level architecture of the protocol is shown below:

![High Level Architecture](./docs/assets/high-level-architecture.png)

## 2. Folder Structure

- [Broadcast](./broadcast) folder contains Foundry transactions executed by scripts.
- [Contracts](./contracts) folder contains contracts source code.
- [Deploy](./deploy) folder contains hardhat deployment scripts.
- [Deployments](./deployments) folder contains info of contracts deployed per network.
- [Docs](./docs) folder contains all documentation related to main contracts.
- [Script](./scripts) folder contains Foundry scripts to interact with onchain contracts.
- [Test](./test) folder contains all tests related to the contracts with mocks and settings.
- [Utils](./utils) folder contains helper functions.

## 3. Documentation

Additional documentation can be found in the `/docs` directory:

- [Audit Details](docs/AuditDetails.md)
- [Deployments Contracts](docs/Deployment.md)
- [Technical Specifications](docs/TechnicalSpecs.md)

## 4. Getting Started

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
export API_KEY_ALCHEMY="YOUR_API_KEY_ALCHEMY"
export API_KEY_ETHERSCAN="YOUR_API_KEY_ETHERSCAN"
export API_KEY_POLYGONSCAN="YOUR_API_KEY_POLYGONSCAN"
export MNEMONIC="YOUR_MNEMONIC"
export PRIVATE_KEY="YOUR_PRIVATE_KEY"
export FOUNDRY_PROFILE="default"
```

### Compile contracts

```bash
bun run compile
```

### Run tests

```bash
bun run test
```

You will find other useful commands in the [package.json](./package.json) file.

## Licences

All contracts is under the `MIT` License, see [`LICENSE`](./LICENSE).
