# Concrete Earn v2 - Invariant Testing Suite

This directory contains a comprehensive invariant testing suite for the Concrete Earn v2 protocol, implemented using Foundry's `forge invariant` testing framework with handler-based testing approach.

## Concrete V2 Invariants

For detailed information about the system invariants being tested, refer to the implementation-specific documentation:

- **[ConcreteStandardVaultImpl](./ConcreteStandardVaultImplInvariants.md)**: Multi-strategy Concrete Standard vault implementation invariants

## 🏗️ Test Suite Architecture

### Core Components

- **`InvariantTestBase.t.sol`**: Base contract providing comprehensive setup with multi-user, multi-strategy scenarios
- **`VaultInvariant.t.sol`**: Main invariant test contract containing all implemented invariants
- **`handlers/`**: Handler contracts for different operation types
- **`helpers/`**: Utility libraries for calculations and validations

## 🎭 Actor Management (`ActorUtil`)

The `ActorUtil` contract manages multiple users and role-based access in the testing environment:

### Features
- **Multi-User Support**: Manages 5 regular users + 3 system roles (vault manager, strategy operator, allocator)
- **Role-Based Access**: Each user has specific permissions for realistic testing scenarios
- **Actor Selection**: `fetchActor(seed)` and `initiateExactActorCall(index, target, calldata)` for controlled operations

### Usage Pattern
```solidity
// Fetch a random actor based on seed
(address actor, uint256 actorIndex) = actorUtil.fetchActor(seed);

// Execute call as specific actor
(address actor, bool success, bytes memory returnData) = actorUtil.initiateExactActorCall(
    actorIndex, 
    target, 
    calldata
);
```

### Actor Roles
- **Index 0**: Vault Manager (DEFAULT_ADMIN_ROLE, VAULT_MANAGER_ADMIN, STRATEGY_MANAGER_ADMIN, ALLOCATOR_ADMIN)
- **Index 1**: Strategy Manager (STRATEGY_MANAGER role)
- **Index 2**: Allocator (ALLOCATOR role)
- **Index 3-7**: Regular Users (no special roles, used for deposits/withdrawals)

## Handler-Based Testing

### Handler Architecture

The suite uses handler contracts to:
- **Bound inputs to realistic ranges**: Prevent unrealistic edge cases
- **Track state changes**: Monitor operations and their effects
- **Perform complex multi-step operations**: Simulate real user behavior patterns
- **Manage actor permissions**: Ensure proper role-based access

### ConcreteStandardVaultHandler Operations

#### User Operations
- **`deposit(actorSeed, assets)`**: Deposit assets into vault
- **`mint(actorSeed, shares)`**: Mint shares from vault
- **`withdraw(actorSeed, assets)`**: Withdraw assets from vault
- **`redeem(actorSeed, shares)`**: Redeem shares for assets

#### Strategy Management
- **`allocateToStrategy(strategyIndex, amount)`**: Allocate funds to strategy
- **`deallocateFromStrategy(strategyIndex, amount)`**: Deallocate funds from strategy
- **`addNewStrategy()`**: Add new strategy to vault
- **`removeStrategy(strategyIndex)`**: Remove strategy from vault

#### Yield Simulation
- **`simulateYield(strategyIndex, yieldAmount)`**: Simulate yield generation
- **`simulateLoss(strategyIndex, lossAmount)`**: Simulate strategy losses
- **`accrueYield()`**: Trigger yield accrual operation

## Utility Functions (`InvariantUtils`)

### Core Functions

- **`calculateAvailableLiquidity(vault)`**: Computes idle assets + withdrawable from all active strategies
- **`convertToAssets/Shares(amount, totalSupply, totalAssets, rounding)`**: Uses exact vault math for precise calculations
- **`calculateTotalWithdrawable(vault)`**: Sums maxWithdraw() from all active strategies
- **`calculateTotalReportedValue(vault)`**: Sums totalAllocatedValue() from all non-inactive strategies

## Running Tests

### Basic Commands

```bash
# Run all invariant tests
FOUNDRY_PROFILE=invariant forge test -vv

# Run specific invariant
FOUNDRY_PROFILE=invariant forge test -vv --match-test invariant_vault_solvency
```

## Development Workflow

### Adding New Invariants

1. **Define Mathematical Property**: Write the invariant as a mathematical statement
2. **Implement in VaultInvariant.t.sol**:
   ```solidity
   function invariant_new_property() public view {
       // Implementation with clear assertion messages
       assertEq(actual, expected, "INVARIANT: Clear description");
   }
   ```
3. **Add to Documentation**: Update the relevant invariants `.md` file
4. **Test Thoroughly**: Verify the invariant holds under various scenarios

### Adding New Handlers

1. **Create Handler Contract**: Extend from `Test` with proper setup
2. **Implement Bounded Operations**: Use `bound()` for realistic inputs
3. **Add Actor Management**: Use `ActorUtil` for multi-user scenarios
4. **Target in Main Test**: Add to `targetContract()` in `VaultInvariant.t.sol`

## Known Limitations

1. **Strategy Limits**: Bounded to 10 strategies for performance reasons
2. **Yield Simulation**: Simplified yield/loss simulation for testing purposes
3. **Cross-Chain**: Single-chain focused testing (strategies don't cross chains)

## Best Practices

### Handler Development
- **Bound all inputs** to prevent unrealistic edge cases
- **Use descriptive revert messages** for debugging

### Invariant Writing
- **Use clear assertion messages** with "INVARIANT:" prefix
- **Document assumptions** clearly

## References

- [Foundry Invariant Testing Guide](https://book.getfoundry.sh/forge/invariant-testing)