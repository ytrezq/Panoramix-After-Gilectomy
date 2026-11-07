# Money On Chain Price Sources on Rootstock

This document summarizes the recommended on-chain price sources for Money On Chain users and integrators interested in `DOC` and `BPRO` prices on Rootstock.

All the contracts referenced below are verified on Blockscout. Readers should use the Blockscout links to inspect the verified source code and interact with each contract.

Money On Chain documentation often uses `BTC` and `RBTC` interchangeably at the economic level. On Rootstock, the on-chain collateral asset is `RBTC`.

## Table of contents

- [BTC/USD](#btcusd)
- [DOC/USD](#docusd)
- [DOC/USD (Chainlink-compatible)](#docusd-chainlink-compatible)
- [USDRIF/USD](#usdrifusd)
- [USDRIF/USD (Chainlink-compatible)](#usdrifusd-chainlink-compatible)
- [BPRO/BTC](#bprobtc)
- [BPRO/USD](#bprousd)
- [Off-chain price sources](#off-chain-price-sources)

## Recommended on-chain sources

For MoC users that need a protocol-aligned on-chain price, the recommended sources are:

- `BTC/USD` from `CoinPairPriceFree`
- `DOC/USD` from `PriceProviderDocUsd`
- `DOC/USD` (Chainlink-compatible) from `DocUsdPriceChainlinkCompat`
- `USDRIF/USD` from `PriceProviderUsdRifUsd`
- `USDRIF/USD` (Chainlink-compatible) from `UsdRifUsdPriceChainlinkCompat`
- `BPRO/BTC` from the protocol-derived BPRO price provider
- `BPRO/USD` from the protocol-derived BPRO price provider

## BTC/USD

Contract: `CoinPairPriceFree`  
Address: `0xe2927A0620b82A66D67F678FC9b826B0E01B1bFD`

This is the `BTC/USD` price used by the MoC protocol. It is published on-chain through the OMoC decentralized oracle infrastructure.

Publication follows an off-chain consensus process among OMoC oracle providers. More than half of the participating oracle providers must agree on the `BTC/USD` value before a new price is published on-chain.

The underlying `BTC/USD` feed is built from multiple high-volume exchanges. In the Money On Chain price library, the current reference configuration is documented as a weighted multi-exchange aggregation over:

- `Coinbase` with weight `0.25`
- `Bitstamp` with weight `0.22`
- `Bitfinex` with weight `0.18`
- `Kraken` with weight `0.18`
- `Gemini` with weight `0.17`

Reference: <https://github.com/money-on-chain/moc_prices_source/blob/master/docs/supported_coinpairs.md#for-coinpair-btcusd-from-bitcoin-to-dollar>

### How to use `peek()`

The main read method is:

```solidity
peek() returns (bytes32 price, bool valid)
```

Semantics:

- `price` is the currently exposed `BTC/USD` price.
- `valid = true` means the returned price is the currently accepted operational price and can be used to execute protocol operations.
- In practice, this is the price currently used by MoC for mints and redemptions.
- `valid = false` means the value returned is the last seen price before the oracle data became stale or otherwise invalid.
- When `valid = false`, the number can still be used as a reference, but it should not be treated as an executable protocol price.

Blockscout:

- Verified source: <https://rootstock.blockscout.com/address/0xe2927A0620b82A66D67F678FC9b826B0E01B1bFD?tab=contract_code>
- Read and write interface: <https://rootstock.blockscout.com/address/0xe2927A0620b82A66D67F678FC9b826B0E01B1bFD?tab=read_write_contract>

## DOC/USD

Contract: `PriceProviderDocUsd`  
Address: `0x6a343488338b944c6FCc89906646Fac1e8e91cE5`

This contract provides the `DOC/USD` price for the DoC bucket (how many USD per DOC)

Operationally, the value is usually `1e18`, meaning `1 DOC = 1 USD`. The provider does not simply hardcode `1`. Internally it reads MoC state plus the protocol's existing `BTC/USD` provider and computes the DoC price from protocol TVL. If the protocol were to lose its peg, the value would be a fraction of 1, with 18 decimal places, ie: 0.9 USD per DOC.

The implementation obtains the upstream BTC price provider from the main MoC state contract via `mocState.getBtcPriceProvider()`, then uses that oracle price together with the `C0` bucket balances to derive `DOC/USD`.

At a high level, the contract computes:

```text
DOC/USD = min(1, (nBTC * BTC/USD) / nDOC)
```

Where:

- `nBTC` is the amount of RBTC in the DoC bucket
- `nDOC` is the amount of DOC issued in that bucket

This means:

- when the bucket is fully covered or overcollateralized, the result is capped at `1e18`
- when coverage is insufficient, the result falls below `1e18`. Given how the Money on Chain is over-collateralized, the peg is unlikely to ever be lost, and has never been lost, but using this price provider you are protected regardless.

### How to use `peek()`

The main read method is:

```solidity
peek() returns (bytes32 price, bool valid)
```

Semantics:

- `price` is the `DOC/USD` price, encoded with 18 decimals
- `valid = true` means the returned value is usable as the current protocol-aligned `DOC/USD` price
- `valid = false` means the provider could still return a numeric value, but it should not be treated as an operationally valid price

The implementation marks the result valid only when:

- the upstream `BTC/USD` oracle is valid
- the upstream `BTC/USD` price is non-zero
- the computed `DOC/USD` price is non-zero

Blockscout:

- Verified source: <https://rootstock.blockscout.com/address/0x6a343488338b944c6FCc89906646Fac1e8e91cE5?tab=contract_code>
- Read and write interface: <https://rootstock.blockscout.com/address/0x6a343488338b944c6FCc89906646Fac1e8e91cE5?tab=read_write_contract>

## DOC/USD (Chainlink-compatible)

Contract: `DocUsdPriceChainlinkCompat`  
Testnet address: `0x12218198496f8e725af4FD353ab8D1e5eC6633C3`  
Mainnet address: `0xe64B6D86aA766dafbB957c32B215A64Fa3A632D8`

This adapter exposes the same MoC-derived DOC/USD price through a Chainlink-shaped interface for external consumers that expect `latestAnswer()` and `latestRoundData()`. The price is returned with **8 decimals** and is truncated toward zero from the underlying 18-decimal MoC value.

The adapter also exposes `updatedAt` and `startedAt` through `latestRoundData()`. For Rootstock compatibility, those timestamps are estimated from the upstream publication block and the configured average block time. In this repository the deployment script passes **24 seconds** as the average block time.

This keeps the on-chain price source aligned with MoC while presenting the read surface expected by Chainlink-style integrations.

Blockscout:

- Testnet verified source: <https://rootstock-testnet.blockscout.com/address/0x12218198496f8e725af4FD353ab8D1e5eC6633C3?tab=contract_code>
- Mainnet verified source: <https://rootstock.blockscout.com/address/0xe64B6D86aA766dafbB957c32B215A64Fa3A632D8?tab=contract_code>

### How to use `latestRoundData()`

The main read method is:

```solidity
latestRoundData() returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
```

Semantics:

- `answer` is `DOC/USD` with 8 decimals
- `roundId` tracks the upstream publication block as the current round identifier
- `startedAt` and `updatedAt` are the block-time estimate for that publication
- `answeredInRound` equals the current round identifier
- `getRoundData()` serves the current round and reverts for unsupported historical round IDs

Blockscout:

- Testnet read and write interface: <https://rootstock-testnet.blockscout.com/address/0x12218198496f8e725af4FD353ab8D1e5eC6633C3?tab=read_write_contract>
- Mainnet read and write interface: <https://rootstock.blockscout.com/address/0xe64B6D86aA766dafbB957c32B215A64Fa3A632D8?tab=read_write_contract>

## USDRIF/USD

Contract: `PriceProviderUsdRifUsd`
Testnet address: `0x6Ca13A1050Dddcc507D615Fd2306F591834D7Cdc`
Mainnet address: `0xa5A9874559936B32CDE23591e6E7533d665118F2`

This provider returns the value of one USDRIF expressed in USD, with 18 decimals. Its value is
`min(1, Rif on Chain combined coverage)`: it normally returns `1e18`, meaning `1 USDRIF = 1 USD`,
and returns less than `1e18` if the protocol lacks enough aggregate collateral to honor the full
one-dollar peg.

The implementation is optimized for the normal fully covered state while always reporting real
price metadata. It reads every component provider's last-known price, validity, and publication
block. As soon as a bucket's price row is complete, it calculates that bucket's coverage from those
prices. If every bucket has coverage of at least one, the provider returns one dollar without
running the multi-collateral guard's more expensive combined calculation.

If any bucket is undercovered, the provider continues collecting all remaining prices and metadata,
then passes the already-built price matrix to the guard to calculate exact combined coverage. Stale
values are still used for valuation while the returned validity flag is `false`. Both the normal and
undercovered paths report the actual oldest component-price publication block.

Blockscout:

- Testnet: <https://rootstock-testnet.blockscout.com/address/0x6Ca13A1050Dddcc507D615Fd2306F591834D7Cdc>
- Mainnet: <https://rootstock.blockscout.com/address/0xa5A9874559936B32CDE23591e6E7533d665118F2>

## USDRIF/USD (Chainlink-compatible)

Contract: `UsdRifUsdPriceChainlinkCompat`
Testnet address: `0x94DC29C3e461Bf19b285F309c8c505b325F19F4B`
Mainnet address: `0x4C1D744C46e9A4551137Ed02Fae82c41CB90E29f`

This adapter exposes the same collateral-backed USDRIF/USD value through Chainlink-shaped methods
with 8 decimals. The actual oldest component-price publication block becomes `roundId` and
`answeredInRound`; `startedAt` and `updatedAt` estimate that block's timestamp using the configured
average Rootstock block time. The repository's Ignition deployment configures that estimate as
**30 seconds**.

Since the chainlink interface does not have a validity flag, the age tolerance is to be decided by the user.
Our suggestion for implementors is to consider a price 15 minutes old to be a warning, and 20 minutes old to be an alert.

Blockscout:

- Testnet: <https://rootstock-testnet.blockscout.com/address/0x94DC29C3e461Bf19b285F309c8c505b325F19F4B>
- Mainnet: <https://rootstock.blockscout.com/address/0x4C1D744C46e9A4551137Ed02Fae82c41CB90E29f>

## BPRO/BTC

Address: `0xDa6E28971E01671D93246A69D8aB4aea54df2F9E`

This is the recommended on-chain `BPRO/BTC` source.

The `BPRO/BTC` price is calculated from the protocol itself. Conceptually, the protocol:

1. Looks at the BTC TVL in the system.
2. Subtracts the BTC amount required to allow redemption of all issued DOC.
3. Divides the remaining BTC by the total BPRO supply.

The result is how much residual BTC each BPRO is entitled to, expressed as `BTC per BPRO`.

In the MoC contracts this is exposed through `MoCState.bproTecPrice()`, and the on-chain price provider wraps that value behind the standard `peek()` interface while reusing the protocol BTC oracle as the freshness gate.

### How to use `peek()`

The main read method is:

```solidity
peek() returns (bytes32 price, bool valid)
```

Semantics:

- `price` is `BTC per BPRO`
- the return value uses 18 decimals
- `valid = true` means the protocol BTC oracle is currently valid and the resulting `BPRO/BTC` value should be treated as the current protocol-aligned price
- `valid = false` means the adapter can still return the last computable value, but it should be treated as reference-only

For the exact implementation details and edge cases, readers should inspect the verified source code on Blockscout.

Blockscout:

- Verified source: <https://rootstock.blockscout.com/address/0xDa6E28971E01671D93246A69D8aB4aea54df2F9E?tab=contract_code>
- Read and write interface: <https://rootstock.blockscout.com/address/0xDa6E28971E01671D93246A69D8aB4aea54df2F9E?tab=read_write_contract>

## BPRO/USD

Address: `0x3955BBA7bBbbF10e350Df341dB5f40842870d63a`

This is the recommended on-chain `BPRO/USD` source.

It is also protocol-derived. The provider uses the same `BTC/USD` price source already used by the protocol and combines it with the protocol's `BPRO/BTC` logic so that `BPRO/USD` remains coherent with the rest of MoC pricing.

At a high level:

```text
BPRO/USD = (BPRO/BTC) * (BTC/USD)
```

This preserves consistency between:

- the BPRO residual claim logic
- the BTC/USD oracle used by MoC
- the resulting `BPRO/USD` value exposed on-chain

### How to use `peek()`

The main read method is:

```solidity
peek() returns (bytes32 price, bool valid)
```

Semantics:

- `price` is `USD per BPRO`
- the return value uses 18 decimals
- `valid = true` means the protocol BTC oracle is valid and the computed `BPRO/USD` value is operationally aligned with MoC
- `valid = false` means the adapter can still return the last computable value, but it should not be used as an executable protocol price

Blockscout:

- Verified source: <https://rootstock.blockscout.com/address/0x3955BBA7bBbbF10e350Df341dB5f40842870d63a?tab=contract_code>
- Read and write interface: <https://rootstock.blockscout.com/address/0x3955BBA7bBbbF10e350Df341dB5f40842870d63a?tab=read_write_contract>

## Off-chain price sources

### Money On Chain price library

Besides the recommended on-chain sources above, Money On Chain also maintains a general-purpose off-chain price library in Python: `moc_prices_source`.

This library exposes current prices retrieved from online sources and also supports computed, smoothed, and averaged variants. It covers a broad collection of pairs, including:

- the weighted `BTC/USD` reference used by the OMoC oracle infrastructure
- `RIF/USD` variants based on depth-weighted pricing
- `BPRO/BTC` as an on-chain sourced pair
- many other direct, inverted, computed, and on-chain pairs

The project also includes a CLI executable that can be used to fetch prices in the same way Money On Chain tooling does.

This is useful for teams that want to build separate infrastructures which mirror the price methodology used by the OMoC oracle stack, even when their final consumer is not the MoC protocol itself.

References:

- Supported coinpairs: <https://github.com/money-on-chain/moc_prices_source/blob/master/docs/supported_coinpairs.md>
- CLI documentation: <https://github.com/money-on-chain/moc_prices_source/blob/master/docs/cli.md>

## Practical guidance

If the goal is to integrate with the live MoC protocol on Rootstock, prefer the on-chain providers described in this document.

Use the Python price library when:

- you need off-chain observability or monitoring
- you need to replicate the same price-building methodology outside the protocol
- you are building a separate infrastructure that should stay coherent with MoC's oracle conventions
