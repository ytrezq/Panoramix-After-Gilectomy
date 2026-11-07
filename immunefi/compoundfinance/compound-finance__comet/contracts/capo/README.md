# CAPO: Correlated-Assets Price Oracle

## Purpose

**CAPO** (Correlated-Assets Price Oracle) is a price oracle adapter designed to support assets that grow gradually relative to a base asset — such as liquid staking tokens (LSTs) that accumulate yield over time. It provides a mechanism to track this expected growth while protecting downstream protocol from sudden or manipulated price spikes.

The goal of CAPO is to balance two key requirements in decentralized finance (DeFi):

- **Enable organic growth** of assets over time, reflecting yield and adoption.
- **Prevent sudden, artificial price increases** that could be exploited in systems relying on price feeds.

---

## High-Level Design

CAPO wraps around two existing data sources:

- A **base price feed** for the underlying asset (e.g., ETH/USD), typically powered by a Chainlink Aggregator.
- A **ratio feed** that represents the current exchange rate between the derivative asset and the base (e.g., stETH/ETH), often exposed via protocols like ERC-4626 vaults.

CAPO combines these inputs to calculate a live price, with an enforced upper bound based on preconfigured growth parameters.

---

## How CAPO Works

At initialization, CAPO takes a **snapshot** of the exchange rate and timestamp. From this snapshot, it calculates the maximum allowed ratio at any given time using a configurable yearly growth cap (e.g., 8% or 20%).

The capped rate is derived with a linear approximation:

```typescript
max_rate(t) = snapshot_rate * (1 + max_yearly_growth * elapsed_time / 1 year)
```

This mechanism allows the asset's price to grow steadily while rejecting values that rise faster than expected, which could indicate manipulation, mispricing, or other anomalies.

If the live ratio exceeds the computed cap, CAPO returns the maximum allowed rate instead. This result is then combined with the base asset's price to produce a final output.

---

## Benefits

- **Manipulation Resistance**: CAPO helps prevent price manipulation attacks that could inflate collateral value or affect stablecoin issuance.
- **Predictable Growth Model**: Allows token issuers and protocol integrators to specify clear expectations for asset appreciation over time.
- **DeFi Compatibility**: Can be used in any system that consumes price feeds—particularly where conservative valuation is preferable.

---

## Oracle Types

CAPO provides several specialized oracle implementations for different types of correlated assets:

### 1. ERC4626CorrelatedAssetsPriceOracle

For ERC-4626 compliant vaults and yield-bearing tokens. Uses the vault's `convertToAssets()` function to get the exchange rate.

### 2. WstETHCorrelatedAssetsPriceOracle

Specifically designed for Lido's wrapped staked ETH (wstETH). Calculates the price using stETH/wstETH ratio and optionally includes stETH/ETH market rate from Chainlink.

### 3. RsETHCorrelatedAssetsPriceOracle

For Kelp DAO's rsETH (Liquid Restaked Token). Gets the rsETH price directly from Kelp's LRT Oracle.

### 4. ChainlinkCorrelatedAssetsPriceOracle

For assets where both base price and ratio are available via Chainlink feeds. Multiplies two Chainlink price feeds to get the final price.

### 5. RateBasedCorrelatedAssetsPriceOracle

For LSTs and other tokens that implement the `IRateProvider` interface (e.g., weETH, rswETH). Optionally supports market rate adjustment from Chainlink for underlying asset depegs.

---

## Integration Considerations

- CAPO is intended for use with derivative tokens that grow slowly and predictably (e.g., liquid staking tokens, interest-bearing assets).
- It is **not suited** for highly volatile or freely traded assets where price movements are unpredictable or unconstrained.
- Governance or protocol maintainers are responsible for updating snapshot data periodically to reflect current conditions.

---

## Supported Markets

The table below outlines the current and planned markets where CAPO may be integrated, along with the associated collateral types and oracle implementations.

**Note**: CAPO is under active development and not yet deployed. This list is for informational purposes only and will be updated as integration progresses.

| Network  | Market  | Collateral | Type                   | CAPO | Oracle Type                          |
| -------- | ------- | ---------- | ---------------------- | ---- | ------------------------------------ |
| Mainnet  | cWETHv3 | cbETH      | Liquid Staking Token   | ✅   | ChainlinkCorrelatedAssetsPriceOracle |
| Mainnet  | cWETHv3 | rsETH      | Liquid Restaking Token | ✅   | RsETHCorrelatedAssetsPriceOracle     |
| Mainnet  | cWETHv3 | wstETH     | Liquid Staking Token   | ✅   | WstETHCorrelatedAssetsPriceOracle    |
| Mainnet  | cWETHv3 | rswETH     | Liquid Staking Token   | ✅   | RateBasedCorrelatedAssetsPriceOracle |
| Mainnet  | cWETHv3 | weETH      | Liquid Restaking Token | ✅   | RateBasedCorrelatedAssetsPriceOracle |
| Mainnet  | cUSDTv3 | wUSDM      | ERC-4626 Yield Vault   | ✅   | ERC4626CorrelatedAssetsPriceOracle   |
| Mainnet  | cUSDTv3 | sFRAX      | ERC-4626 Yield Vault   | ✅   | ERC4626CorrelatedAssetsPriceOracle   |
| Mainnet  | cUSDTv3 | sUSDS      | ERC-4626 Yield Vault   | ✅   | ERC4626CorrelatedAssetsPriceOracle   |
| Optimism | cUSDCv3 | wUSDM      | ERC-4626 Yield Vault   | ✅   | ERC4626CorrelatedAssetsPriceOracle   |
| Arbitrum | cUSDCv3 | wUSDM      | ERC-4626 Yield Vault   | ✅   | ERC4626CorrelatedAssetsPriceOracle   |
| Base     | cAEROv3 | wstETH     | Liquid Staking Token   | ✅   | WstETHCorrelatedAssetsPriceOracle    |
| Mantle   | cUSDev3 | mETH       | Liquid Staking Token   | ✅   | ChainlinkCorrelatedAssetsPriceOracle |

---

## Example Use Cases

- Lending protocols using LSTs as collateral.
- Stablecoins backed by staking derivatives.
- On-chain risk management systems that need rate limiting on asset appreciation.

---
