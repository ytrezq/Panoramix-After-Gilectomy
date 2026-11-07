<p align="center">
  <img src="doc/img/concrete-logo.png" alt="Concrete logo" width="200" />
</p>

# Earn V2 

## 1. Overview

Concrete Earn V2 is a protocol for permissionless vault deployment with multi-strategy yield aggregation. The protocol enables curators to deploy ERC4626-compliant vaults that allocate funds across multiple yield-generating strategies with built-in fee management, upgradability, and advanced withdrawal systems.

**Key Features:**
- 🏭 **Factory-based deployment**: Permissionless vault creation with version management
- 🏦 **Multi-strategy vaults**: Allocate funds across multiple strategies for optimized yields
- 💰 **Fee management**: Built-in management and performance fees with configurable recipients
- ⚡ **Async withdrawals**: Queue-based withdrawal system for better liquidity management
- 🔄 **Upgradeable**: UUPS proxy pattern for vault and factory upgrades
- 🎣 **Hooks system**: Custom validation logic at key vault operation points

---

## 2. Documentation

### Core Documentation

- **[Architecture](./doc/Architecture.md)** - Comprehensive system architecture covering factory, vaults, strategies, hooks, and fee mechanisms
- **[Testing](./doc/Testing.md)** - Complete testing guide including unit tests, fuzz tests, invariant tests, E2E tests, and testing utilities

### Technical Specifications

- **[ConcreteAsyncVaultImpl Specification](./doc/spec/ConcreteAsyncVaultImpl.md)** - Detailed specification of the asynchronous withdrawal system with state machines, sequence diagrams, and mathematical proofs

### Quick Links by Topic

**Understanding the System:**
- Start with [Architecture Overview](./doc/Architecture.md#overview)
- Learn about [Vault Implementations](./doc/Architecture.md#26-concrete-vault-implmentations)
- Understand [Factory Deployment](./doc/Architecture.md#11-vault-deployment)

**About Tests:**
- [Testing Guidelines](./doc/Testing.md#1-testing-guidelines) - Best practices for writing tests
- [Unit Tests](./doc/Testing.md#2-unit-testing)
- [Fuzz Tests](./doc/Testing.md#3-fuzz-testing)
- [E2E Tests](./doc/Testing.md#4-end-to-end-testing)
- [Testing Utilities Reference](./doc/Testing.md#5-testing-utilities)

**Advanced Topics:**
- [Asynchronous Vault Details](./doc/spec/ConcreteAsyncVaultImpl.md)
- [Access Control & Roles](./doc/Architecture.md#25-access-control-and-vault-operations)
- [Fee System](./doc/Architecture.md#24-fees)
- [Strategies](./doc/Architecture.md#31-strategies)

---

## 3. Getting Started

### 3.1 Pre-requisites

#### Node.js and npm

**Required versions:**
- Node.js ≥ 20
- npm ≥ 10

**How to install:**

Option 1: Download from [nodejs.org](https://nodejs.org/)

Option 2: Using nvm (recommended):
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 20
nvm use 20
```

#### Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

**Solidity version used:** 0.8.27

**How to install:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Foundry consists of:
- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools)
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network
- **Chisel**: Fast, utilitarian, and verbose solidity REPL

**Documentation:** https://book.getfoundry.sh/


### 3.2 Commands

**Install dependencies:**
```bash
npm install
```
Or if using yarn:
```bash
yarn install
```

**Build the project:**
```bash
forge build
```

**Run tests:**
```bash
# All tests
forge test

# With verbosity
forge test -vvv

# Specific test types
forge test --match-path test/unit-test/      # Unit tests
forge test --match-path test/fuzz/           # Fuzz tests
forge test --match-path test/E2E/            # E2E tests
FOUNDRY_PROFILE=invariant forge test -vv    # Invariant tests
```

**Check coverage:**
```bash 
FOUNDRY_PROFILE=coverage forge coverage --ir-minimum
```

---

## 4. Repository Structure

```
src/
├── common/           # Shared base contracts (UpgradeableVault)
├── factory/          # Factory for vault deployment and upgrades
├── implementation/   # Vault implementations (Standard, Async, Bridged, Predeposit)
├── interface/        # Contract interfaces
├── lib/              # Shared libraries and utilities
├── module/           # Allocation module
└── periphery/        # Peripheral contracts (strategies, hooks, fee splitters)

test/
├── common/           # Base test setups and utilities
├── mock/             # Mock contracts for testing
├── unit-test/        # Unit tests (core and periphery)
├── fuzz/             # Fuzz tests
├── invariant/        # Invariant tests with handlers
├── E2E/              # End-to-end scenario tests
└── property/         # Property-based tests

doc/
├── Architecture.md                      # System architecture documentation
├── Testing.md                           # Testing guide and reference
└── spec/
    └── ConcreteAsyncVaultImpl.md       # Async vault technical specification

deployment-scripts/
└── config/
    ├── 1/            # Ethereum Mainnet deployments
    └── 42161/        # Arbitrum deployments
```

---

## 5. Key Contracts

### Core Contracts

| Contract | Location | Description |
|----------|----------|-------------|
| `ConcreteFactory` | `src/factory/` | Factory for deploying and upgrading vaults |
| `VaultProxy` | `src/factory/` | ERC1967 proxy for vault implementations |
| `UpgradeableVault` | `src/common/` | Base contract handling vault upgrades |
| `ConcreteStandardVaultImpl` | `src/implementation/` | Standard multi-strategy ERC4626 vault |
| `ConcreteAsyncVaultImpl` | `src/implementation/` | Async vault with queue-based withdrawals |
| `AllocateModule` | `src/module/` | Handles fund allocation to strategies |

### Peripheral Contracts

| Contract | Location | Description |
|----------|----------|-------------|
| `BaseStrategy` | `src/periphery/strategies/` | Base strategy implementation |
| `SimpleStrategy` | `src/periphery/strategies/` | Simple strategy with direct fund management |
| `MultisigStrategy` | `src/periphery/strategies/` | Strategy forwarding funds to multisig |
| `TwoWayFeeSplitter` | `src/periphery/auxiliary/` | Fee distribution between two recipients |
| `Hooks` | `src/lib/` | Hook system for custom vault logic |

---

## 6. Deployments

### Ethereum Mainnet (Chain ID: 1)

#### Core Infrastructure

| Contract | Address | Description |
|----------|---------|-------------|
| **ConcreteFactory** | [`0x0265d73a8E61F698d8EB0dfeb91Ddce55516844C`](https://etherscan.io/address/0x0265d73a8E61F698d8EB0dfeb91Ddce55516844C) | Factory proxy for vault deployment |

#### Production Vaults

| Vault | Address | Symbol |
|-------|---------|--------|
| **Stable USDT Pre-Deposit** | [`0x6503de9FE77d256d9d823f2D335Ce83EcE9E153f`](https://etherscan.io/address/0x6503de9FE77d256d9d823f2D335Ce83EcE9E153f) | ctStableUSDT |
| **Stable Frax USD Pre-Deposit** | [`0x4DeF5abCfBa7Babe04472EE4835f459DAf4bD45f`](https://etherscan.io/address/0x4DeF5abCfBa7Babe04472EE4835f459DAf4bD45f) | ctStablefrxUSD |

---

## 7. Contributing

Please read our [CONTRIBUTING.md](./CONTRIBUTING.md) guidelines before submitting pull requests. It covers our branch management policy, release process, and important requirements for code contributions.

---

## License

AGPL-3.0
