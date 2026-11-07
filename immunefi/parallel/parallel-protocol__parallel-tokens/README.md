# Parallel Tokens

## Summary

This repository contains all the contracts of Parallel Tokens with associated contract.

## Architecture

- [TokenP](./contracts/tokens/TokenP/TokenP.sol) contract is the ERC20 stablecoin.
- [BridgeableTokenP](./contracts/tokens/BridgeableTokenP/BridgeableTokenP.sol) is an OFT (layerZero standard) contract that unlock the power of TokenP to be bridgeable between specific chains.
- [FlashParallelToken](./contracts/flashloan/FlashParallelToken.sol) is the flashloan contract on top of TokenP's contracts.

## Documentation Links

## Deployment Addresses

### Mainnet

USDp is live on the 24 chains listed below.

#### Ethereum

| Contract           | Explore                                                                                                               |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x9B3a8f7CEC208e247d97dEE13313690977e24459](https://etherscan.io/address/0x9B3a8f7CEC208e247d97dEE13313690977e24459) |
| FlashParallelToken | [0xC9B6279baa19dBB8bCc3250c89cAa093AaBA0bfc](https://etherscan.io/address/0xC9B6279baa19dBB8bCc3250c89cAa093AaBA0bfc) |
| BridgeableUSDp     | [0x78BB4882b77D74aD9B04Ab71fE8e61f72595823C](https://etherscan.io/address/0x78BB4882b77D74aD9B04Ab71fE8e61f72595823C) |

#### Polygon

| Contract           | Explore                                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| USDp               | [0x1250304F66404cd153fA39388DDCDAec7E0f1707](https://polygonscan.com/address/0x1250304F66404cd153fA39388DDCDAec7E0f1707) |
| FlashParallelToken | [0xC15Fd01A21E8f6625f709b16f6b3562d2848Da5f](https://polygonscan.com/address/0xC15Fd01A21E8f6625f709b16f6b3562d2848Da5f) |
| BridgeableUSDp     | [0x9aFDB5A5eC2BBDDdAa4573BAA25CAA4e4e4a2CA9](https://polygonscan.com/address/0x9aFDB5A5eC2BBDDdAa4573BAA25CAA4e4e4a2CA9) |

#### Base

| Contract           | Explore                                                                                                               |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x76A9A0062ec6712b99B4f63bD2b4270185759dd5](https://basescan.org/address/0x76A9A0062ec6712b99B4f63bD2b4270185759dd5) |
| FlashParallelToken | [0x08417cdb7F52a5021bB4eb6E0deAf3f295c3f182](https://basescan.org/address/0x08417cdb7F52a5021bB4eb6E0deAf3f295c3f182) |
| BridgeableUSDp     | [0x4Dde0e308CFB60515218C6ad2DF1134Fc48531FC](https://basescan.org/address/0x4Dde0e308CFB60515218C6ad2DF1134Fc48531FC) |

#### Optimism

| Contract           | Explore                                                                                                                          |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x90337e484B1Cb02132fc150d3Afa262147348545](https://optimistic.etherscan.io/address/0x90337e484B1Cb02132fc150d3Afa262147348545) |
| FlashParallelToken | [0x3EBE332d2AA8cCB5dDc051c9925D9A41708e54D9](https://optimistic.etherscan.io/address/0x3EBE332d2AA8cCB5dDc051c9925D9A41708e54D9) |
| BridgeableUSDp     | [0x76A9A0062ec6712b99B4f63bD2b4270185759dd5](https://optimistic.etherscan.io/address/0x76A9A0062ec6712b99B4f63bD2b4270185759dd5) |

#### Arbitrum

| Contract           | Explore                                                                                                              |
| ------------------ | -------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x76A9A0062ec6712b99B4f63bD2b4270185759dd5](https://arbiscan.io/address/0x76A9A0062ec6712b99B4f63bD2b4270185759dd5) |
| FlashParallelToken | [0x08417cdb7F52a5021bB4eb6E0deAf3f295c3f182](https://arbiscan.io/address/0x08417cdb7F52a5021bB4eb6E0deAf3f295c3f182) |
| BridgeableUSDp     | [0x4Dde0e308CFB60515218C6ad2DF1134Fc48531FC](https://arbiscan.io/address/0x4Dde0e308CFB60515218C6ad2DF1134Fc48531FC) |

#### Sonic

| Contract           | Explore                                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x08417cdb7F52a5021bB4eb6E0deAf3f295c3f182](https://sonicscan.org/address/0x08417cdb7F52a5021bB4eb6E0deAf3f295c3f182) |
| FlashParallelToken | [0x2cb56dF31b909854B01D4B1EAd5676cf90e885E7](https://sonicscan.org/address/0x2cb56dF31b909854B01D4B1EAd5676cf90e885E7) |
| BridgeableUSDp     | [0xDa818995DdEee3AC36BF492133E1FeAE1FA377E6](https://sonicscan.org/address/0xDa818995DdEee3AC36BF492133E1FeAE1FA377E6) |

#### Sei

| Contract           | Explore                                                                                                               |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x048C4e07D170eEdEE8772cA76AEE1C4e2D133d5c](https://seitrace.com/address/0x048C4e07D170eEdEE8772cA76AEE1C4e2D133d5c) |
| FlashParallelToken | [0xc0e62F863bbD9dab9d2F79e4EcC248e60c4fE3FA](https://seitrace.com/address/0xc0e62F863bbD9dab9d2F79e4EcC248e60c4fE3FA) |
| BridgeableUSDp     | [0x7b54f3D993d3bcA077946034Ea710F9c07420C72](https://seitrace.com/address/0x7b54f3D993d3bcA077946034Ea710F9c07420C72) |

#### Avalanche

| Contract           | Explore                                                                                                               |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x9eE1963f05553eF838604Dd39403be21ceF26AA4](https://snowtrace.io/address/0x9eE1963f05553eF838604Dd39403be21ceF26AA4) |
| FlashParallelToken | [0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277](https://snowtrace.io/address/0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277) |
| BridgeableUSDp     | [0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec](https://snowtrace.io/address/0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec) |

#### BSC

| Contract           | Explore                                                                                                              |
| ------------------ | -------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x048C4e07D170eEdEE8772cA76AEE1C4e2D133d5c](https://bscscan.com/address/0x048C4e07D170eEdEE8772cA76AEE1C4e2D133d5c) |
| FlashParallelToken | [0xc0e62F863bbD9dab9d2F79e4EcC248e60c4fE3FA](https://bscscan.com/address/0xc0e62F863bbD9dab9d2F79e4EcC248e60c4fE3FA) |
| BridgeableUSDp     | [0x7b54f3D993d3bcA077946034Ea710F9c07420C72](https://bscscan.com/address/0x7b54f3D993d3bcA077946034Ea710F9c07420C72) |

#### Berachain

| Contract           | Explore                                                                                                               |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x9eE1963f05553eF838604Dd39403be21ceF26AA4](https://berascan.com/address/0x9eE1963f05553eF838604Dd39403be21ceF26AA4) |
| FlashParallelToken | [0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277](https://berascan.com/address/0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277) |
| BridgeableUSDp     | [0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec](https://berascan.com/address/0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec) |

#### Scroll

| Contract           | Explore                                                                                                                 |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x9eE1963f05553eF838604Dd39403be21ceF26AA4](https://scrollscan.com/address/0x9eE1963f05553eF838604Dd39403be21ceF26AA4) |
| FlashParallelToken | [0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277](https://scrollscan.com/address/0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277) |
| BridgeableUSDp     | [0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec](https://scrollscan.com/address/0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec) |

#### Gnosis

| Contract           | Explore                                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x9eE1963f05553eF838604Dd39403be21ceF26AA4](https://gnosisscan.io/address/0x9eE1963f05553eF838604Dd39403be21ceF26AA4) |
| FlashParallelToken | [0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277](https://gnosisscan.io/address/0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277) |
| BridgeableUSDp     | [0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec](https://gnosisscan.io/address/0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec) |

#### Unichain

| Contract           | Explore                                                                                                              |
| ------------------ | -------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x9eE1963f05553eF838604Dd39403be21ceF26AA4](https://uniscan.xyz/address/0x9eE1963f05553eF838604Dd39403be21ceF26AA4) |
| FlashParallelToken | [0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277](https://uniscan.xyz/address/0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277) |
| BridgeableUSDp     | [0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec](https://uniscan.xyz/address/0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec) |

#### Ink

| Contract           | Explore                                                                                                                          |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x9eE1963f05553eF838604Dd39403be21ceF26AA4](https://explorer.inkonchain.com/address/0x9eE1963f05553eF838604Dd39403be21ceF26AA4) |
| FlashParallelToken | [0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277](https://explorer.inkonchain.com/address/0x9e0DCF7a33bBde6689560C5c807dd2a3dF991277) |
| BridgeableUSDp     | [0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec](https://explorer.inkonchain.com/address/0x9fFaCB3dB5cB74BdD4C68af3b7CF203130c699ec) |

#### HyperEVM

| Contract           | Explore                                                                                                                    |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0xBE65F0F410A72BeC163dC65d46c83699e957D588](https://www.hyperscan.com/address/0xBE65F0F410A72BeC163dC65d46c83699e957D588) |
| FlashParallelToken | [0x15452454A9735D68df430879B2941316a09295B1](https://www.hyperscan.com/address/0x15452454A9735D68df430879B2941316a09295B1) |
| BridgeableUSDp     | [0xC3BEF21Ea7dEB5C34CF33E918c8e28972C8048eD](https://www.hyperscan.com/address/0xC3BEF21Ea7dEB5C34CF33E918c8e28972C8048eD) |

#### Tac

| Contract           | Explore                                                                                                                     |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x4DeF531c3060686948f00EcC7504f2E0b71EDa14](https://explorer.tac.build/address/0x4DeF531c3060686948f00EcC7504f2E0b71EDa14) |
| FlashParallelToken | [0x76A9A0062ec6712b99B4f63bD2b4270185759dd5](https://explorer.tac.build/address/0x76A9A0062ec6712b99B4f63bD2b4270185759dd5) |
| BridgeableUSDp     | [0xB3DbecE41acDD6aD76d037b8Da2e53C58826746c](https://explorer.tac.build/address/0xB3DbecE41acDD6aD76d037b8Da2e53C58826746c) |

#### Plasma

| Contract           | Explore                                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0xC2f8B5d893217462aE9c9879c9285A5a3AAbcb8F](https://plasmascan.to/address/0xC2f8B5d893217462aE9c9879c9285A5a3AAbcb8F) |
| FlashParallelToken | [0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2](https://plasmascan.to/address/0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2) |
| BridgeableUSDp     | [0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7](https://plasmascan.to/address/0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7) |

#### xLayer

| Contract           | Explore                                                                                                                            |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x8fCf9118fdD359f6277cDd143c2Da206e64140F3](https://www.oklink.com/fr/x-layer/address/0x8fCf9118fdD359f6277cDd143c2Da206e64140F3) |
| FlashParallelToken | [0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2](https://www.oklink.com/fr/x-layer/address/0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2) |
| BridgeableUSDp     | [0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7](https://www.oklink.com/fr/x-layer/address/0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7) |

#### Plume

| Contract           | Explore                                                                                                                     |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x8fCf9118fdD359f6277cDd143c2Da206e64140F3](https://explorer.plume.org/address/0x8fCf9118fdD359f6277cDd143c2Da206e64140F3) |
| FlashParallelToken | [0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2](https://explorer.plume.org/address/0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2) |
| BridgeableUSDp     | [0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7](https://explorer.plume.org/address/0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7) |

#### Katana

| Contract           | Explore                                                                                                                 |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x8fCf9118fdD359f6277cDd143c2Da206e64140F3](https://katanascan.com/address/0x8fCf9118fdD359f6277cDd143c2Da206e64140F3) |
| FlashParallelToken | [0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2](https://katanascan.com/address/0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2) |
| BridgeableUSDp     | [0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7](https://katanascan.com/address/0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7) |

#### Fraxtal

| Contract           | Explore                                                                                                               |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x8fCf9118fdD359f6277cDd143c2Da206e64140F3](https://fraxscan.com/address/0x8fCf9118fdD359f6277cDd143c2Da206e64140F3) |
| FlashParallelToken | [0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2](https://fraxscan.com/address/0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2) |
| BridgeableUSDp     | [0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7](https://fraxscan.com/address/0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7) |

#### Linea

| Contract           | Explore                                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| USDp               | [0x8fCf9118fdD359f6277cDd143c2Da206e64140F3](https://lineascan.build/address/0x8fCf9118fdD359f6277cDd143c2Da206e64140F3) |
| FlashParallelToken | [0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2](https://lineascan.build/address/0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2) |
| BridgeableUSDp     | [0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7](https://lineascan.build/address/0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7) |

#### Hemi

| Contract           | Explore                                                                                                                    |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x8fCf9118fdD359f6277cDd143c2Da206e64140F3](https://explorer.hemi.xyz/address/0x8fCf9118fdD359f6277cDd143c2Da206e64140F3) |
| FlashParallelToken | [0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2](https://explorer.hemi.xyz/address/0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2) |
| BridgeableUSDp     | [0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7](https://explorer.hemi.xyz/address/0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7) |

#### Worldchain

| Contract           | Explore                                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0x8fCf9118fdD359f6277cDd143c2Da206e64140F3](https://worldscan.org/address/0x8fCf9118fdD359f6277cDd143c2Da206e64140F3) |
| FlashParallelToken | [0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2](https://worldscan.org/address/0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2) |
| BridgeableUSDp     | [0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7](https://worldscan.org/address/0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7) |

### Testnet

#### Sepolia

| Contract           | Explore                                                                                                                       |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| USDp               | [0xe8a3DA6f5ed1cf04c58ac7f6A7383641e877517b](https://sepolia.etherscan.io/address/0xe8a3DA6f5ed1cf04c58ac7f6A7383641e877517b) |
| FlashParallelToken | [0x8B899796b4a442e7723E02f8b5B65a39F27EDAf1](https://sepolia.etherscan.io/address/0x8B899796b4a442e7723E02f8b5B65a39F27EDAf1) |
| BridgeableUSDp     | [0xFeFc8635edf0fAAD83312A713Cb67722D049C9Bc](https://sepolia.etherscan.io/address/0xFeFc8635edf0fAAD83312A713Cb67722D049C9Bc) |

#### Arbitrum Sepolia

| Contract       | Explore                                                                                                                      |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| USDp           | [0xA7eb076F57960E265B91514c03d1d1281055a75c](https://sepolia.arbiscan.io/address/0xA7eb076F57960E265B91514c03d1d1281055a75c) |
| BridgeableUSDp | [0xA8FE9843B4Cc2aAB136209B49E2c3E2A7ebD5CFA](https://sepolia.arbiscan.io/address/0xA8FE9843B4Cc2aAB136209B49E2c3E2A7ebD5CFA) |

## Security

### Assumptions

- Every restricted access is managed by an [AccessManager](https://github.com/parallel-protocol/parallel-core/blob/main/contracts/access/AccessManager.sol) contract following the OpenZeppelin standard
- The owner of [BridgeableTokenP](./contracts/tokens/BridgeableTokenP/BridgeableTokenP.sol) will be the AccessManager contract or a multisig.

### Known Issues

- When updating the FlashloanFeeRecipient current fees are not sent to the current recipient before update (to prevent that this function could be restricted with a timelock role on the AccessManager).
- In BridgeableTokenP, LZ messages can be received (causing tokens to be credited) even when the contract is paused. DAO must unlink peers with others chains when pausing a BridgeableTokenP.
- Fee rate changes can lead to unexpected number of received tokens if fees are updated during an ongoing bridge.
- When feesRate=0 in the BridgeableToken, bridge can be done repeatedly to DOS swaps from
  LZ->Principal token. However, user will still pay fees to LZ.

### Audits

#### Bailsec

Audited by Bailsec in March/April 2025:

- [1st report](./docs/audits/Bailsec%20-%20Parallel%20Protocol%20-%20V3%20Core%20-%201st%20Report.pdf)
- [final report](./docs/audits/Bailsec%20-%20Parallel%20Protocol%20-%20V3%20Core%20-%20Final%20Report.pdf)

#### Certora

Formal Verification by Certora in March/April 2025:

- [1st report](./docs/audits/Certora_Draft_Report_Parallel_Parallelizer_BridgeToken.pdf)
- [final report](./docs/audits/Certora_Report_Parallel_Parallelizer_BridgeToken_final.pdf)

## Development

### Foundry

[Install foundry follow the instructions.](https://book.getfoundry.sh/getting-started/installation)

### Install js dependencies

```bash
bun install
```

### Setup `.env` file

In order to interact with non local networks, you must create an `.env` that has:

```bash
PRIVATE_KEY="PRIVATE_KEY"
ALCHEMY_API_KEY="ALCHEMY_API_KEY"
MAINNET_ETHERSCAN_API_KEY="MAINNET_ETHERSCAN_API_KEY"
```

For additional keys, you can check the `.env.example` file.

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

## Licensing

The primary license for this repository is the MIT license. See [`LICENSE`](./LICENSE).
Minus the following exceptions:

- tests files are under UNLICENSED license
- mocks contracts are under UNLICENSED license

Each of these files states their license type.
