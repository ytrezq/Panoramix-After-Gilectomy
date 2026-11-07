# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2025-11-04

### Added

- Factory-based permissionless vault deployment system with version management
- ERC4626 multi-strategy vault implementations:
  - `ConcreteStandardVaultImpl` - Standard multi-strategy vault
  - `ConcreteAsyncVaultImpl` - Vault with queue-based async withdrawals
  - `ConcreteBridgedVaultImpl` - Cross-chain vault support
  - `ConcretePreDepositVaultImpl` - Pre-deposit vault functionality
- Allocation module for optimized fund distribution across multiple strategies
- Comprehensive fee management system:
  - Management fees
  - Performance fees
  - Configurable fee recipients
  - `TwoWayFeeSplitter` for fee distribution
- Async withdrawal queue system for improved liquidity management
- UUPS proxy pattern for upgradeable vaults and factory
- Hooks system for custom validation logic at vault operation points
- Strategy implementations:
  - `BaseStrategy` - Base strategy contract
  - `SimpleStrategy` - Simple strategy with direct fund management
  - `MultisigStrategy` - Strategy with multisig forwarding
- Comprehensive testing suite:
  - Unit tests for core and periphery
  - Fuzz testing
  - Invariant testing
  - End-to-end scenario tests
- Complete documentation:
  - Architecture guide
  - Testing guide
  - ConcreteAsyncVaultImpl technical specification
- Audit reports for Standard Vault, Async Vault, and Hooks system
- Ethereum Mainnet deployment support (Chain ID: 1)
- Arbitrum deployment support (Chain ID: 42161)

[unreleased]: https://github.com/blueprint-finance/earn-v2-core/compare/v1.0.0...HEAD
[1.0.0]: https://www.npmjs.com/package/@blueprint-finance/earn-v2-core/v/1.0.0

