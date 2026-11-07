# Strata

[![Test](https://github.com/Strata-Money/contracts-tranches/actions/workflows/test.yml/badge.svg)](https://github.com/Strata-Money/contracts-tranches/actions/workflows/test.yml)

[![Coverage](https://codecov.io/github/Strata-Money/contracts-tranches/graph/badge.svg?token=EA81W2M8QN)](https://codecov.io/github/Strata-Money/contracts-tranches)

----

## High-Level Overview of the Protocol

The protocol is composed of two **ERC-4626 Vaults** (tranches): **Junior (Jrt)** and **Senior (Srt)**.
Both vaults are implemented as *Meta Vaults*:

* Each has a **Base Asset**.
* They can also accept additional tokens supported by the underlying **Strategy**.

  * Example: the **Ethena Strategy** uses **USDe** as the Base Asset and also accepts **sUSDe**.

All vault shares are denominated in the **Base Asset**.
User actions (`deposit`, `withdraw`, etc.) are forwarded to the **CDO contract** (the core orchestrator).

The **CDO contract** has two major components:

1. **Strategy**
2. **Accounting**

---

## Strategy

The Strategy contract is responsible for **asset management**. It receives assets from the CDO, stakes them, and must be able to return them when requested.

At any point in time, the Strategy reports its **total TVL** (incl. yield).

When returning assets, the Strategy uses different mechanisms:

* **Direct return**: e.g. `sUSDe` can be returned instantly to an Srt user.
* **ERC20 Cooldown**: Strategy locks tokens in a cooldown contract. Tokens can be finalized/withdrawn after the cooldown period.
* **Unstaking Cooldown**: e.g. for USDe, the Strategy requests withdrawal from Ethena's `sUSDe`, which itself has a cooldown period.

Each withdrawal request is handled **independently per user**. New requests do not extend or affect earlier requests.

---

## Accounting

The Accounting contract performs **pure calculations** for:

* `jrtTVL`
* `srtTVL`

From these, each vault derives its ERC-4626 `exchangeRate` and `totalAssets`.

### Update Cycle

On every protocol action (deposit, withdrawal), Accounting is updated:

1. Strategy reports current `totalTVL` at current block timestamp `t1`.
2. Accounting compares against the last saved `totalTVL` at `t0`.
3. **Strategy Gain** is calculated:

   ```
   gain = totalTVL(t1) - totalTVL(t0)
   ```

   (For `sUSDe`, this amount is always >= 0)

4. A portion of the gain may be redirected to **reserveTVL** (if the reserve percentage is set).
5. The remaining gain goes to Junior TVL.
6. Calculate Senior's desired gain and subtract from Junior's TVL.

### Gain Splitting

* **Senior Gain Desired (Target)**: Based on the Senior tranche's target index (APR target), last srtTVL and deltaT.

Two cases:

**Case A: Strategy Gain >= Senior Gain Desired**

* Seniors receive their full target.
* Juniors receive the remaining gain.
* So finally:

  ```
  jrtTVL + srtTVL + reserveTVL == totalTVL
  ```

**Case B: Strategy Gain < Senior Gain Desired**

* Any Senior APR shortfall is covered by the Junior tranche

---

## Deposit Flow (Example with Jrt)

1. **Update Accounting**

   * Refresh Strategy TVL and calculate gains for the period `t0 → t1`.
   * Adjust Junior/Senior TVLs according to Gain Splitting rules.

2. **Calculate Shares (ERC-4626)**

   * `jrtTVL` is the vault's `totalAssets()`.
   * User's deposited assets are exchanged for shares proportional to current `jrtTVL`.

3. **Forward Assets to Strategy**

   * User's tokens are passed into the Strategy for staking.
   * `jrtTVL` is incremented accordingly.

---

## Withdrawals

Withdrawals follow the same process:

* First, Accounting updates TVLs at current block `t1`.
* Then, ERC-4626 `totalAssets()` is used to determine how many assets a user receives for redeeming shares.
* Strategy may return assets directly or via cooldown mechanisms, as described above.

---

## APRs Feed

The APR Feed contract provides dynamic parameters:

* **APR Target** (base rate)
* **APR Base**

Whenever these values change, the Feed updates the **Accounting contract**, which recalculates the **Senior Target Index** accordingly.


# Test

```bash
npm i
npm run compile
# OR in watch mode
npm run watch

npm run test

# OR single file
npx atma test ./test/tranches/ERC4626.spec.ts

# OR single file in watch mode
npx atma test ./test/tranches/ERC4626.spec.ts --watch
```

# Deploy

To localhost:
```
# start hh node
npm run node
# deploy/check unchanged

npm run deploy-local
```


----
(c) 2025
