# Concrete Tests - Multi-Strategy ERC4626 Property Testing

This directory contains property tests for Concrete Protocol's multi-strategy vault implementation, built on top of the A16Z ERC4626 property testing framework.

## Overview

The Concrete tests extend the base A16Z ERC4626 property tests to verify that ERC4626 standard compliance is maintained when funds are allocated to strategies, strategies are rebalanced, and yields are accrued. This ensures that the multi-strategy functionality doesn't break the fundamental ERC4626 guarantees.

## Architecture

Following the A16Z pattern, the tests are split into two main files:

- **`ConcreteStandardVaultImpl.prop.sol`** - Contains property functions that define the actual test logic
- **`ConcreteStandardVaultImpl.test.sol`** - Contains test functions that set up bounds and call properties

## Key Differences from Base ERC4626 Tests

### Base A16Z ERC4626 Tests
- Test pure ERC4626 compliance on standard vaults
- Focus on caller independence, preview accuracy, and round-trip properties
- Use simple vault implementations without strategy allocation

### Concrete Enhanced Tests
- Test ERC4626 compliance **with active strategy allocation**
- Verify properties hold during strategy rebalancing operations
- Test preview function accuracy during strategy yield accrual
- Validate total assets calculation with strategy yields/losses
- Use realistic multi-strategy scenarios (1-10 strategies per test)

## New Properties Added

### 1. Enhanced Round-Trip Properties
**Purpose**: Verify that deposit/redeem and deposit/withdraw round-trips work correctly even when strategy rebalancing occurs between operations.

- `prop_RT_deposit_redeem_withRebalancing` - Tests deposit → rebalance → redeem consistency
- `prop_RT_deposit_withdraw_withRebalancing` - Tests deposit → rebalance → withdraw consistency

**Why Important**: Strategy rebalancing moves funds between strategies, which could potentially affect user withdrawals if not implemented correctly.

### 2. Preview Function Accuracy
**Purpose**: Verify that ERC4626 preview functions remain accurate during strategy operations.

- `prop_previewDeposit_withStrategyAllocation` - Tests preview accuracy before/after allocation
- `prop_previewRedeem_afterStrategyYield` - Tests preview accuracy accounts for yield

**Why Important**: Preview functions must give accurate estimates even when underlying strategies are generating yield or being rebalanced.

### 3. Strategy Constraint Properties  
**Purpose**: Verify that vault limits correctly account for strategy liquidity constraints.

- `prop_maxWithdraw_withStrategyConstraints` - Tests maxWithdraw respects strategy liquidity

**Why Important**: Users should only be able to withdraw amounts that can actually be provided given strategy liquidity constraints.

### 4. Accounting Properties
**Purpose**: Verify that vault accounting remains accurate with strategy operations.

- `prop_totalAssets_reflectsStrategyAllocations` - Tests totalAssets accuracy after allocation/yield accrual

**Why Important**: Total assets calculation must correctly account for funds allocated to strategies and any yields/losses.

## Strategy Test Scenarios

### Strategy Setup
- Randomized number of strategies (1-10 per test)
- Strategies deployed with entropy-based selection for variety
- Allocation limited to `uint120` max (strategy storage constraint)

### Strategy Operations Tested
1. **Allocation** - Moving idle vault funds to strategies
2. **Rebalancing** - Moving funds between strategies  
3. **Yield Simulation** - Strategies generating positive returns
4. **Yield Accrual** - Updating vault accounting with strategy returns

## Implementation Details

### Bounds Checking
All tests use proper bounds checking following the A16Z pattern:
```solidity
// Use minimum of all constraints
uint256 actualMax = min(userBalance, vaultMax, uint120Max);
assets = bound(assets, 0, actualMax);
```

### Strategy Allocation Limits
- All allocations respect the `uint120` limit from `StrategyData.allocated`
- Prevents overflow in strategy allocation logic
- Ensures realistic allocation amounts

### Error Handling
- Uses A16Z `vault_*` helpers that handle overflow via `vm.assume(false)`
- Graceful handling of strategy operation failures
- Follows property testing best practices

## Usage

### Extending the Tests
To use these tests in your vault implementation:

1. Inherit from `ConcreteStandardVaultImplTest`
2. Implement required abstract functions:
   - `_getAllocator()` - Return allocator address
   - `_getStrategyOperator()` - Return strategy operator address
3. Set up vault-specific configuration in your test contract

### Example Integration
```solidity
contract MyVaultPropertyTest is ConcreteStandardVaultImplTest, MyVaultBaseSetup {
    function _getAllocator() internal view override returns (address) {
        return allocator;
    }
    
    function _getStrategyOperator() internal view override returns (address) {
        return strategyOperator;
    }
}
```

## Benefits

### Comprehensive Coverage
- Tests both individual ERC4626 functions AND their interaction with strategies
- Covers realistic multi-strategy scenarios
- Validates edge cases with fuzzing

### Compliance Assurance  
- Proves ERC4626 compliance is maintained with strategy operations
- Prevents regressions in core vault functionality
- Ensures user funds remain safe during strategy operations

### Property-Based Testing
- Uses fuzzing to test wide range of inputs
- Automatically discovers edge cases
- Provides mathematical guarantees about vault behavior