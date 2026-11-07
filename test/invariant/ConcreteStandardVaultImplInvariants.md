# ConcreteStandardVaultImpl - Invariant Testing

## Overview

This document describes the critical invariants implemented and tested for the ConcreteStandardVaultImpl contract using Foundry's `forge invariant` testing framework. These invariants ensure the safety, correctness, and ERC4626 compliance of the multi-strategy vault system.

## Implemented Invariants

### 1. Vault Solvency Invariant (`invariant_vault_solvency`)

**The vault must always remain solvent and able to honor all user redemptions.**

```solidity
// The vault must always have enough assets to cover all user shares
previewAccrueYield() >= previewRedeem(totalSupply())
```

This fundamental safety invariant ensures that the vault can always cover the redemption of all outstanding shares, using `previewAccrueYield()` to account for unrealized yields and losses from strategies.

### 2. Asset Conservation Invariants

These invariants ensure perfect accounting of all vault assets.

#### 2.1 Total Asset Accounting (`invariant_asset_conservation`)
```solidity
// The vault's total assets must equal idle assets plus all strategy allocations
totalAssets() == IERC20(asset()).balanceOf(address(vault)) + getTotalAllocated()
```

#### 2.2 Strategy Allocation Bounds (`invariant_strategy_allocation_bounds`)
```solidity
// Sum of all strategy allocations cannot exceed total vault assets
getTotalAllocated() <= totalAssets()
```

### 3. ERC4626 Compliance Invariants

#### 3.1 Max Function Accuracy (`invariant_erc4626_max_functions`)
```solidity
// Max functions must respect actual liquidity constraints
maxRedeem(user) == convertToShares(min(userAssets, availableLiquidity()))

where:
    userAssets = convertToAssets(balanceOf(user))
    availableLiquidity = idleAssets + sum(strategy.maxWithdraw() for strategy in activeStrategies)
```

This ensures that `maxRedeem()` reflects real withdrawal constraints, not just user balances.

### 4. Strategy Yield Accrual Synchronization (`invariant_strategy_yield_accrual_sync`)

```solidity
// After yield accrual, strategy allocated amounts should match reported values
∀ strategy ∈ activeStrategies: 
    strategyData[strategy].allocated == strategy.totalAllocatedValue(vault)
```

This invariant validates that yield accrual operations correctly synchronize strategy values and maintain accurate yield accounting across all active strategies.
