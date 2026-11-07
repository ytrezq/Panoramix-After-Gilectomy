## Definitions:

- asset: The underlying token managed by the Vault.
  Has units defined by the corresponding EIP-20 contract.
- share: The token of the Vault. Has a ratio of underlying assets
  exchanged on mint/deposit/withdraw/redeem (as defined by the Vault).
- fee: An amount of assets or shares charged to the user by the Vault. Fees can exists for
  deposits, yield, AUM, withdrawals, or anything else prescribed by the Vault.
- slippage: Any difference between advertised share price and economic realities of
  deposit to or withdrawal from the Vault, which is not accounted by fees.

## Methods:

### totalAssets

```
SHOULD include any compounding that occurs from yield.

MUST be inclusive of any fees that are charged against assets in the Vault.

MUST _NOT_ revert.
```

**implementation:**

- Vault total deposited amount + strategies positive yield - strategies negative yield 

=> Vault total AUM with yield & inclusive of performance/protocol fees.

### convertToShares

```
MUST NOT be inclusive of any fees that are charged against assets in the Vault.

MUST NOT show any variations depending on the caller.

MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.

MUST NOT revert unless due to integer overflow caused by an unreasonably large input.

MUST round down towards 0.
```

**implementation:**

- Assets * vault totalSupply / vault total deposited amount + strategies positive yield - strategies negative yield

=> A straightforward conversion based on exchange rate, using real time vault AUM, not inclusive of any fees or on-chain conditions

### convertToAssets

```
MUST NOT be inclusive of any fees that are charged against assets in the Vault.

MUST NOT show any variations depending on the caller.

MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.

MUST NOT revert unless due to integer overflow caused by an unreasonably large input.

MUST round down towards 0.
```

**implementation:**

- Shares * vault total deposited amount + strategies positive yield - strategies negative yield / vault totalSupply

=> A straightforward conversion based on exchange rate, using real time vault AUM, not inclusive of any fees or on-chain conditions

### maxDeposit

```
MUST return the maximum amount of assets `deposit` would allow to be deposited for `receiver` and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary). This assumes that the user has infinite assets, i.e. MUST NOT rely on `balanceOf` of `asset`.

MUST factor in both global and user-specific limits, like if deposits are entirely disabled (even temporarily) it MUST return 0.

MUST return `2 ** 256 - 1` if there is no limit on the maximum amount of assets that may be deposited.

MUST NOT revert.
```

**implementation:**

type(uint224).max

### previewDeposit

```
MUST return as close to and no more than the exact amount of Vault shares that would be minted in a `deposit` call in the same transaction. I.e. `deposit` should return the same or more `shares` as `previewDeposit` if called in the same transaction.

MUST NOT account for deposit limits like those returned from maxDeposit and should always act as though the deposit would be accepted, regardless if the user has enough tokens approved, etc.

MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.

MUST NOT revert due to vault specific user/global limits. MAY revert due to other conditions that would also cause `deposit` to revert.
```

**implementation:**

- Execute previewAccrueYield() to get expected up-to-date total assets and total supply (inclusive of fees)
- assets * expected totalSupply / expected total assets

### maxMint

```
MUST return the maximum amount of shares `mint` would allow to be deposited to `receiver` and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary). This assumes that the user has infinite assets, i.e. MUST NOT rely on `balanceOf` of `asset`.

MUST factor in both global and user-specific limits, like if mints are entirely disabled (even temporarily) it MUST return 0.

MUST return `2 ** 256 - 1` if there is no limit on the maximum amount of shares that may be minted.

MUST NOT revert.
```

**implementation:**
type(uint224).max

### previewMint

```
MUST return as close to and no fewer than the exact amount of assets that would be deposited in a `mint` call in the same transaction. I.e. `mint` should return the same or fewer `assets` as `previewMint` if called in the same transaction.

MUST NOT account for mint limits like those returned from maxMint and should always act as though the mint would be accepted, regardless if the user has enough tokens approved, etc.

MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.

MUST NOT revert due to vault specific user/global limits. MAY revert due to other conditions that would also cause `mint` to revert.
```

**implementation:**

- Execute previewAccrueYield() to get expected up-to-date total assets and total supply (inclusive of fees)
- Calculate: shares * expected total assets / expected totalSupply

### maxWithdraw

```
MUST return the maximum amount of assets that could be transferred from `owner` through `withdraw` and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary).

MUST factor in both global and user-specific limits, like if withdrawals are entirely disabled (even temporarily) it MUST return 0.

MUST NOT revert.
```

**implementation:**

- Get all user shares balance
- Preview yield accrual to get expected up-to-date total assets and total supply (inclusive of fees)
- Calculate the max amount of assets a user can get: shares * vault total deposited amount + strategies positive yield - strategies negative yield / vault totalSupply
- Simulate a withdraw to check if the vault can fill the requested amount, either using idle funds or if underlying strategies are available to withdraw from, if the requested amount is un-fillable, return the max amount the vault can fill.

### previewWithdraw

```
MUST return as close to and no fewer than the exact amount of Vault shares that would be burned in a `withdraw` call in the same transaction. I.e. `withdraw` should return the same or fewer `shares` as `previewWithdraw` if called in the same transaction.

MUST NOT account for withdrawal limits like those returned from maxWithdraw and should always act as though the withdrawal would be accepted, regardless if the user has enough shares, etc.

MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.

MUST NOT revert due to vault specific user/global limits. MAY revert due to other conditions that would also cause `withdraw` to revert.
```

**implementation:**

- Preview yield accrual to get expected up-to-date total assets and total supply (inclusive of fees)
- Calculate: assets * expected vault totalSupply / expected vault total assets

#### maxRedeem

```
MUST return the maximum amount of shares that could be transferred from `owner` through `redeem` and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary).

MUST factor in both global and user-specific limits, like if redemption is entirely disabled (even temporarily) it MUST return 0.

MUST NOT revert.
```

**implementation:**

- Using maxWithdraw to:
  - Get all user shares balance
  - Preview yield accrual to get expected up-to-date total assets and total supply (inclusive of fees)
  - Calculate the max amount of assets a user can get: shares * vault total deposited amount + strategies positive yield - strategies negative yield / vault totalSupply
  - Simulate a withdraw to check if the vault can fill the requested amount, either using idle funds or if underlying strategies are available to withdraw from, if the requested amount is un-fillable, return the max amount the vault can fill.
- Through maxWithdraw results, which are the max assets, expected total supply and expected total assets amounts, calculate: assets * expected vault totalSupply / expected vault total assets

### previewRedeem

```
MUST return as close to and no more than the exact amount of assets that would be withdrawn in a `redeem` call in the same transaction. I.e. `redeem` should return the same or more `assets` as `previewRedeem` if called in the same transaction.

MUST NOT account for redemption limits like those returned from maxRedeem and should always act as though the redemption would be accepted, regardless if the user has enough shares, etc.

MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.

MUST NOT revert due to vault specific user/global limits. MAY revert due to other conditions that would also cause `redeem` to revert.
```

**implementation:**

- Preview yield accrual to get expected up-to-date total assets and total supply (inclusive of fees)
- Calculate: shares * expected vault total assets / expected vault totalSupply
