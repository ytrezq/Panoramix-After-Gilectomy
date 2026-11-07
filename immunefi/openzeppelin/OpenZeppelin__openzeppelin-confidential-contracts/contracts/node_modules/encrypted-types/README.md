# 🔐 Encrypted Type Aliases

This repository defines encrypted type aliases.

## 📘 Overview

These Solidity `bytes32` aliases represent encrypted values, used for privacy-preserving smart contracts:

### Core Encrypted Types (e\*)

```solidity
type ebool is bytes32;

type euint8 is bytes32;
type euint16 is bytes32;
type euint24 is bytes32;
...
type euint256 is bytes32;

type eint8 is bytes32;
type eint16 is bytes32;
type eint24 is bytes32;
...
type eint256 is bytes32;

type eaddress is bytes32;

type ebytes1 is bytes32;
// ...
type ebytes32 is bytes32;

```

### External Encrypted Types (externalE\*)

```solidity
type externalExternalEbool is bytes32;

type externalEuint8 is bytes32;
type externalEuint16 is bytes32;
type externalEuint24 is bytes32;
...
type externalEuint256 is bytes32;

type externalEint8 is bytes32;
type externalEint16 is bytes32;
type externalEint24 is bytes32;
...
type externalEint256 is bytes32;

type externalEbytes1 is bytes32;
// ...
type externalEbytes32 is bytes32;
```

These types enable type-safe handling of encrypted data in contracts, support validation via proofs, and integrate with decryption oracles for confidential workflows.

## 📜 License

MIT
