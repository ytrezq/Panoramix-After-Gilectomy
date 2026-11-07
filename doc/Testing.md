# Testing

## Table of Contents

- [1. Testing Guidelines](#1-testing-guidelines)
- [2. Unit Testing](#2-unit-testing)
  - [2.1 Overview](#21-overview)
  - [2.2 Factory Unit Tests](#22-factory-unit-tests)
  - [2.3 Upgradeable Vault Unit Tests](#23-upgradeable-vault-unit-tests)
  - [2.4 Vault-Specific Unit Tests](#24-vault-specific-unit-tests)
    - [2.4.1 ConcreteStandardVaultImpl](#241-concretestandardvaultimpl)
    - [2.4.2 ConcreteAsyncVaultImpl](#242-concreteasyncvaultimpl)
    - [2.4.3 ConcreteBridgedAsyncVaultImpl](#243-concretebridgedasyncvaultimpl)
    - [2.4.4 ConcretePredepositVaultImpl](#244-concretepredepositvaultimpl)
  - [2.5 Periphery Unit Tests](#25-periphery-unit-tests)
    - [2.5.1 FeeSplitter](#251-feesplitter)
    - [2.5.2 Hooks](#252-hooks)
    - [2.5.3 SimpleStrategy](#253-simplestrategy)
    - [2.5.4 MultisigStrategy](#254-multisigstrategy)
    - [2.5.5 ShareDistributor](#255-sharedistributor)
- [3. Fuzz Testing](#3-fuzz-testing)
  - [3.1 Overview](#31-overview)
  - [3.2 AllocateModule Fuzz Tests](#32-allocatemodule-fuzz-tests)
  - [3.3 ConcreteStandardVaultImpl Fuzz Tests](#33-concretestandardvaultimpl-fuzz-tests)
  - [3.4 Invariant Testing](#34-invariant-testing)
- [4. End-to-End Testing](#4-end-to-end-testing)
  - [4.1 Overview](#41-overview)
  - [4.2 Core Strategy Management Tests](#42-core-strategy-management-tests)
  - [4.3 Vault Tests](#43-vault-tests)
  - [4.4 Fee Tests](#44-fee-tests)
  - [4.5 Cross-Chain Tests](#45-cross-chain-tests)
  - [4.6 Periphery Strategy Tests](#46-periphery-strategy-tests)
- [5. Testing Utilities](#5-testing-utilities)
  - [5.1 Overview](#51-overview)
  - [5.2 Mocks](#52-mocks)
  - [5.3 Base Test Contracts](#53-base-test-contracts)
  - [5.4 Test Utilities](#54-test-utilities)

---

## 1. Testing Guidelines

Writing high-quality unit tests ensures code reliability and maintainability. Follow these best practices when writing unit tests for Concrete Earn V2:

#### Naming Conventions

- **Function names**: Must start with `test` followed by camelCase describing what is being tested
  ```solidity
  ✅ Good: testDepositWithValidAmount()
  ✅ Good: testWithdrawRevertsWhenInsufficientBalance()
  ❌ Bad: test_deposit() // Use camelCase, not snake_case
  ❌ Bad: depositTest() // Must start with "test"
  ```

- **Fuzz test naming**: Fuzz tests should use `testFuzz` prefix (not in unit tests)
  ```solidity
  ✅ Unit test: testUpdateManagementFee()
  ✅ Fuzz test: testFuzzManagementFeeAccrual()
  ```

- **Descriptive names**: Test names should clearly describe the scenario being tested
  ```solidity
  ✅ Good: testMigrateByNonVaultOwner()
  ✅ Good: testUpdateManagementFeeExceedsMaximum()
  ❌ Bad: testMigrate() // Too vague
  ```

#### Test Structure

- **One function per test**: Each test should focus on testing one public or external function
  ```solidity
  ✅ Good: Test deposit() in testDeposit(), test withdraw() in testWithdraw()
  ❌ Bad: Testing deposit() and withdraw() in the same test function
  ```

- **Single responsibility**: Each test should validate one specific behavior or edge case
  ```solidity
  ✅ Good: testDepositInvalidReceiver() tests only receiver validation
  ✅ Good: testDepositInvalidUpperLimitAmount() tests only upper bound
  ❌ Bad: testDepositValidation() testing receiver, amount, and approval
  ```

#### Assertions and Expectations

- **Must include assertions**: Every test MUST have at least one assertion or expectation
  ```solidity
  ✅ Good:
  function testDeposit() public {
      uint256 shares = vault.deposit(100e18, user1);
      assertEq(vault.balanceOf(user1), shares);
  }
  
  ❌ Bad:
  function testDeposit() public {
      vault.deposit(100e18, user1);
      // No assertion - test is incomplete
  }
  ```

- **Use appropriate assertions**: Choose the right assertion for the test
  ```solidity
  assertEq(a, b)           // Exact equality
  assertGt(a, b)           // Greater than
  assertLt(a, b)           // Less than
  assertGe(a, b)           // Greater than or equal
  assertApproxEqAbs(a, b, tolerance) // Approximate equality (for rounding)
  ```

#### Testing Reverts

- **Separate tests for reverts**: Each revert condition should have its own test
  ```solidity
  ✅ Good:
  function testDepositInvalidReceiver() public {
      vm.expectRevert(IConcreteStandardVaultImpl.InvalidReceiver.selector);
      vault.deposit(100e18, address(0));
  }
  
  function testDepositInsufficientBalance() public {
      vm.expectRevert();
      vault.deposit(type(uint256).max, user1);
  }
  
  ❌ Bad: Testing multiple revert conditions in one test
  ```

- **Use specific error selectors**: Always use typed errors with selectors when possible
  ```solidity
  ✅ Good: vm.expectRevert(IConcreteFactory.InvalidVersion.selector);
  ✅ Good: vm.expectRevert(abi.encodeWithSelector(Error.selector, arg1, arg2));
  ⚠️ Acceptable: vm.expectRevert(); // Only when error is generic or from external contract
  ```

#### Testing Events

- **Test event emissions**: Verify events are emitted with correct parameters when significant state changes occur
  ```solidity
  ✅ Good:
  function testUpdateManagementFee() public {
      vm.expectEmit(true, true, false, true);
      emit ManagementFeeUpdated(500);
      vm.prank(vaultManager);
      vault.updateManagementFee(500);
  }
  ```

- **When to test events**: 
  - State-changing operations (fee updates, strategy additions, migrations)
  - User actions (deposits, withdrawals, claims)
  - Administrative actions (role grants, configuration changes)

#### Test Setup and Isolation

- **Use setUp()**: Initialize common test state in `setUp()` function
  ```solidity
  function setUp() public override {
      super.setUp();
      user1 = makeAddr("user1");
      asset.mint(user1, 1000e18);
  }
  ```

- **Test isolation**: Each test should be independent and not rely on other tests
- **Clean state**: Use `vm.prank()` and `vm.stopPrank()` properly to avoid state pollution
  ```solidity
  ✅ Good:
  vm.prank(user1);
  vault.deposit(100e18, user1);
  // Prank automatically stops after one call
  
  ✅ Good:
  vm.startPrank(user1);
  vault.deposit(100e18, user1);
  vault.withdraw(50e18, user1, user1);
  vm.stopPrank();
  ```

#### Access Control Testing

- **Test both success and failure**: Test authorized access succeeds and unauthorized access fails
  ```solidity
  function testUpdateManagementFee() public {
      vm.prank(vaultManager);
      vault.updateManagementFee(500); // Should succeed
      assertEq(...);
  }
  
  function testUpdateManagementFeeUnauthorized() public {
      vm.expectRevert(...);
      vm.prank(user1);
      vault.updateManagementFee(500); // Should fail
  }
  ```

#### Code Organization

- **Group related tests**: Organize tests by the function they're testing
- **Use comments**: Add section comments to separate test groups
  ```solidity
  // ============================================================================
  // UPDATE MANAGEMENT FEE TESTS
  // ============================================================================
  
  function testUpdateManagementFee() public { ... }
  function testUpdateManagementFeeUnauthorized() public { ... }
  ```

- **Inherit from appropriate base**: Use the correct base test contract for your needs (see [Section 5.3](#53-base-test-contracts))

#### Common Patterns

- **Label addresses**: Use `vm.label()` for better trace readability
  ```solidity
  vm.label(address(vault), "vault");
  vm.label(user1, "user1");
  ```

- **Test boundary conditions**: Test zero values, maximum values, and edge cases
  ```solidity
  testDepositZeroAmount()
  testDepositMaxAmount()
  testDepositBelowMinimum()
  testDepositAboveMaximum()
  ```

- **Use helper utilities**: Leverage `AddStrategyWithDeallocationOrder` and other utilities (see [Section 5.4](#54-test-utilities))

---

## 2. Unit Testing

### 2.1 Overview

The repository is divided into **core** and **periphery**, each with its own testing suite. All outward-facing functions (public and external) are covered with unit tests.

#### Test Directory Structure

- **Core unit tests**: `test/unit-test/`
  - `factory/` - Factory contract tests
  - `UpgradeableVault/` - Upgradeable vault abstract contract tests
  - `ConcreteStandardVaultImpl/` - Standard vault implementation tests
  - `ConcreteAsyncVaultImpl/` - Async vault implementation tests
  - `ConcreteBridgedAsyncVaultImpl/` - Bridged async vault implementation tests
  - `ConcretePredepositVaultImpl/` - Predeposit vault implementation tests

- **Periphery unit tests**: `test/periphery/unit-test/`
  - `FeeSplitterTest.t.sol` - Fee splitting functionality tests
  - `HooksUnitTest.t.sol` - Hooks system tests
  - `SimpleStrategyUnitTest.t.sol` - Simple strategy tests
  - `MultisigStrategyUnitTest.t.sol` - Multisig strategy tests
  - `ShareDistributorTest.t.sol` - Share distribution tests

---

### 2.2 Factory Unit Tests

**File**: `test/unit-test/factory/ConcreteFactoryUnitTest.t.sol`

**Run tests**:
```bash
forge test --match-path test/unit-test/factory/ConcreteFactoryUnitTest.t.sol
```

**Tests:**

- **Factory upgrades**: Factory owner upgrades factory contract to new implementation (`testUpgradeFactory`, `testUpgradeFactoryByNonOwner`)
- **Implementation approval**: Validates and approves new vault implementations, prevents duplicate approvals, validates factory ownership (`testApproveImplementation`)
- **Implementation blocking**: Blocks compromised/deprecated implementations from deployment and migration (`testDeployUsingBlockedImpl`, `testMigrateToBlockedImpl`)
- **Vault deployment**: Creates vaults with specific versions, validates version bounds, supports deterministic addresses via salt (`testDeployProxyUsingImpl1`, `testDeployVaultWithSalt`, `testDeployVaultWithSaultDifferentSenderCreatesDifferentAddress`)
- **Single vault migration**: Upgrades individual vaults to new versions, validates migration paths, enforces owner-only access (`testMigrateImpl1ToImpl2`, `testMigrateByNonVaultOwner`, `testMigrateToOldVersion`, `testMigrateNotMigratableVersionParis`)
- **Batch vault migration**: Upgrades multiple vaults atomically, validates consistent ownership, fails fast on errors (`testBatchMigrateSuccess`, `testBatchMigrateSingleVault`, `testBatchMigrateFailsWithDifferentOwners`, `testBatchMigrateWithMixedVersions`, `testBatchMigrateWithBlockedImplementation`, `testBatchMigrateWithNonMigratableVersions`, `testBatchMigrateWithInvalidVersion`)
- **External vault registration**: Registers externally-deployed vaults into factory management system, validates factory ownership via proxy admin (`testRegisterVault`, `testRegisterVaultAlreadyRegistered`, `testRegisterVaultInvalidFactory`, `testRegisterVaultNonOwner`, `testRegisterVaultZeroAddress`)
- **Explicit upgrade prevention**: Prevents direct vault upgrades bypassing factory (`testExplicitUpgradeToAndCall`)
- **Error handling**: Invalid versions, unregistered vaults, invalid data lengths (`testUpgradeNotAVault`, `testBatchUpgradeInvalidDataLength`, `testBatchUpgradeNotAVault`)

---

### 2.3 Upgradeable Vault Unit Tests

**File**: `test/unit-test/UpgradeableVault/UpgradeableVaultUnitTest.t.sol`

**Run tests**:
```bash
forge test --match-path test/unit-test/UpgradeableVault/UpgradeableVaultUnitTest.t.sol
```

**Tests:**

- **Initialization access control**: Ensures only factory can initialize vault proxy, rejects non-factory initialization attempts (`testInitializeRevertsIfNotFactory`)

---

### 2.4 Vault-Specific Unit Tests

#### 2.4.1 ConcreteStandardVaultImpl

**Directory**: `test/unit-test/ConcreteStandardVaultImpl/`

**Run all tests**:
```bash
forge test --match-path test/unit-test/ConcreteStandardVaultImpl/
```

##### InitializationUnitTest.t.sol

**Run tests**:
```bash
forge test --match-path test/unit-test/ConcreteStandardVaultImpl/InitializationUnitTest.t.sol
```

**Tests:**
- Valid initialization with proper parameters (`testInitialize`)
- Rejection of invalid allocate module (`testInitializeRevertsIfInvalidAllocateModule`)
- Rejection of invalid asset address (`testInitializeRevertsIfInvalidAsset`)
- Rejection of invalid initial vault manager (`testInitializeRevertsIfInvalidInitialVaultManager`)
- Rejection of invalid name (`testInitializeRevertsIfInvalidName`)
- Rejection of invalid symbol (`testInitializeRevertsIfInvalidSymbol`)

##### AccrueYieldUnitTest.t.sol

**Run tests**:
```bash
forge test --match-path test/unit-test/ConcreteStandardVaultImpl/AccrueYieldUnitTest.t.sol
```

**Tests:**
- Yield accrual with positive returns from strategies (`testAccrueYieldWithPositiveYield`)
- Loss handling and accounting updates (`testAccrueYieldWithLoss`)
- Preview accuracy vs actual accrual for yield and fees (`testPreviewVsAccruePerformanceFee`)

##### AddRemoveStrategyUnitTest.t.sol

**Run tests**:
```bash
forge test --match-path test/unit-test/ConcreteStandardVaultImpl/AddRemoveStrategyUnitTest.t.sol
```

**Tests:**
- Adding strategies with proper asset validation, preventing duplicates (`testAddStrategy`)
- Removing strategies from vault (`testRemoveStrategy`)

##### AllocateUnitTest.t.sol

**Run tests**:
```bash
forge test --match-path test/unit-test/ConcreteStandardVaultImpl/AllocateUnitTest.t.sol
```

**Tests:**
- Allocating funds to strategies (`testAllocate`)
- Deallocating funds from strategies (`testDeallocate`)

##### ManagementFunctionsUnitTest.t.sol

**Run tests**:
```bash
forge test --match-path test/unit-test/ConcreteStandardVaultImpl/ManagementFunctionsUnitTest.t.sol
```

**Tests:**
- **Management fee**: Setting/updating fees (`testUpdateManagementFee`, `testUpdateManagementFeeZero`, `testUpdateManagementFeeExceedsMaximum`), recipient management (`testUpdateManagementFeeRecipient`, `testUpdateManagementFeeRecipientZeroAddress`), requiring recipient before setting fee (`testUpdateManagementFeeNoRecipient`), access control (`testUpdateManagementFeeUnauthorized`, `testUpdateManagementFeeRecipientUnauthorized`)
- **Performance fee**: Setting/updating fees (`testUpdatePerformanceFee`, `testUpdatePerformanceFeeZero`, `testUpdatePerformanceFeeExceedsMaximum`), recipient management (`testUpdatePerformanceFeeRecipient`, `testUpdatePerformanceFeeRecipientZeroAddress`), requiring recipient before setting fee (`testUpdatePerformanceFeeNoRecipient`), access control (`testUpdatePerformanceFeeUnauthorized`, `testUpdatePerformanceFeeRecipientUnauthorized`)
- **Deposit limits**: Setting max/min deposit amounts, validation of bounds (`testSetDepositLimits`, `testSetDepositLimitsUnauthorized`, `testSetDepositLimitsInvalidLimits`)
- **Withdraw limits**: Setting max/min withdraw amounts, validation of bounds (`testSetWithdrawLimits`, `testSetWithdrawLimitsUnauthorized`, `testSetWithdrawLimitsInvalidLimits`)
- **Automatic accrual**: Yield accrual triggered by fee updates (`testUpdateFeesTriggersYieldAccrual`)

##### UserInteractionsUnitTest.t.sol

**Run tests**:
```bash
forge test --match-path test/unit-test/ConcreteStandardVaultImpl/UserInteractionsUnitTest.t.sol
```

**Tests:**
- **Deposit**: Receiver validation (`testDepositInvalidReceiver`), amount bounds checking (`testDepositInvalidUpperLimitAmount`, `testDepositInvalidLowerLimitAmount`), insufficient shares detection (`testDepositInsufficientShares`)
- **Mint**: Receiver validation (`testMintInvalidReceiver`), amount bounds checking (`testMintInvalidUpperLimitAmount`, `testMintInvalidLowerLimitAmount`)
- **Withdraw**: Receiver validation (`testWithdrawInvalidReceiver`), amount bounds checking (`testWithdrawInvalidUpperLimitAmount`, `testWithdrawInvalidLowerLimitAmount`)
- **Redeem**: Receiver validation (`testRedeemInvalidReceiver`), amount bounds checking (`testRedeemInvalidUpperLimitAmount`, `testRedeemInvalidLowerLimitAmount`), insufficient assets detection (`testRedeemInsufficientAssets`)

---

#### 2.4.2 ConcreteAsyncVaultImpl

**File**: `test/unit-test/ConcreteAsyncVaultImpl/QueueUnitTest.t.sol`

**Run tests**:
```bash
forge test --match-path test/unit-test/ConcreteAsyncVaultImpl/QueueUnitTest.t.sol
```

**Tests:**

- **Queue initialization**: Epoch tracking, unclaimed assets, queue active status (`test_Initialization`)
- **Withdrawal requests**: Creating pending requests, on-behalf-of requests, transferring shares to vault (`testWithdrawCreatesPendingRequest`, `testWithdrawCreatesPendingRequestOnBehalfOf`)
- **Request cancellation**: Cancelling open requests, preventing cancellation of closed epochs, on-behalf-of cancellation (`testCancelRequestPlain`, `testCancelRequestEpochAlreadyClosed`, `testCancelRequestNoRequestingShares`, `testCancelRequestOnBehalfOf`)
- **Epoch processing**: Closing epochs, processing withdrawals, calculating share prices, no requesting shares handling, insufficient balance checks (`testProcessEpoch`, `testProcessEpochFundsAllocated`, `testProcessEpochNoRequestingShares`, `testProcessEpochInsufficientBalance`, `testCloseEpochPreviousEpochNotProcessed`)
- **Withdrawal claims**: Claiming processed withdrawals, on-behalf-of claims, batch claiming for multiple users, empty/invalid epoch handling (`testClaimWithdrawal`, `testClaimWithdrawalOnBehalfOf`, `testclaimUsersBatch`, `testClaimWithdrawalEmptyEpochIDs`, `testClaimWithdrawalNoClaimableRequest`, `testClaimUsersBatchZeroAddress`, `testClaimUsersBatchNoClaimableRequest`)
- **Queue toggling**: Enabling/disabling async queue, fallback to standard withdrawals when disabled (`testToggleQueueActive`, `testClaimWithdrawalDisableQueue`)
- **Request management**: Moving requests to next epoch (`testMoveRequestToNextEpoch`, `testMoveRequestToNextEpochNoRequestingShares`)
- **Yield integration**: Processing epochs with yield generation, share price updates reflecting yield (`testEpochProcessingWithYield`)
- **Access control**: Withdrawal manager role enforcement (`testProcessEpochUnauthorized`, `testToggleQueueActiveUnauthorized`, `testMoveRequestToNextEpochUnauthorized`, `testClaimUsersBatchUnauthorized`)
- **Allowance handling**: Spending allowances for third-party withdrawal initiation (`testWithdrawSpendAllowance`, `testWithdrawSpendAllowanceQueueDisabled`)
- **Zero address validation**: Preventing operations with zero addresses (`testClaimWithdrawalZeroAddress`, `testCancelRequestZeroAddress`, `testMoveRequestToNextEpochZeroAddress`)

---

#### 2.4.3 ConcreteBridgedAsyncVaultImpl

**File**: `test/unit-test/ConcreteBridgedAsyncVaultImpl/UnbackedMintUnitTest.t.sol`

**Run tests**:
```bash
forge test --match-path test/unit-test/ConcreteBridgedAsyncVaultImpl/UnbackedMintUnitTest.t.sol
```

**Tests:**

- **Unbacked minting**: Initial mint of shares without backing assets (bootstrap operation) (`test_UnbackedMint_Success`, `testFuzz_UnbackedMint_VariousAmounts`)
- **One-time operation**: Prevents multiple unbacked mints, enforces single initial mint only (`test_UnbackedMint_RevertsWhenNotInitialMint`, `test_UnbackedMint_DifferentVaultManagers`)
- **Access control**: Vault manager role required for unbacked mint (`test_UnbackedMint_RevertsWhenNotVaultManager`)
- **Zero amount validation**: Prevents minting zero shares (`test_UnbackedMint_RevertsWhenZeroAmount`)
- **Post-mint behavior**: Normal deposits work correctly after unbacked mint (`test_Deposit_WorksAfterUnbackedMint`)
- **Integration**: Prevents unbacked mint after normal deposits (`test_UnbackedMint_RevertsAfterDeposit`)

---

#### 2.4.4 ConcretePredepositVaultImpl

**Directory**: `test/unit-test/ConcretePredepositVaultImpl/`

**Run all tests**:
```bash
forge test --match-path test/unit-test/ConcretePredepositVaultImpl/
```

##### Files:
- `BatchQuoteUnitTest.t.sol` - LayerZero cross-chain batch quote calculations
- `LayerZeroClaimUnitTest.t.sol` - Cross-chain withdrawal claims via LayerZero
- `SelfClaimsToggleUnitTest.t.sol` - Enabling/disabling self-service claims
- `UpgradeToPredeposit.t.sol` - Migration from standard vault to predeposit functionality
- `WithdrawalLockUnitTest.t.sol` - Locking/unlocking withdrawal functionality

**Tests cover:**
- Cross-chain messaging and claims coordination
- Withdrawal lock mechanisms and permissions
- Self-claims toggle functionality
- Upgrade path validation from standard to predeposit vault

---

### 2.5 Periphery Unit Tests

#### 2.5.1 FeeSplitter

**File**: `test/periphery/unit-test/FeeSplitterTest.t.sol`

**Run tests**:
```bash
forge test --match-path test/periphery/unit-test/FeeSplitterTest.t.sol
```

**Tests:**

- **Fee split configuration**: Setting fee fractions between main and secondary recipients (`test_setFeeSplit`, `test_setFeeSplit_withOneEmptyRecipient`)
- **Recipient management**: Assigning main and secondary recipients per vault (`test_setMainRecipient_WithoutPreviousFeeSplitBeingSet`, `test_setMainRecipient_WithPreviousFeeSplitBeingSet`, `test_setMainRecipient_VaultManagerCalls`, `test_setSecondaryRecipient`)
- **Fee fraction management**: Setting and updating fee fractions (`test_setFeeFraction`)
- **Fee distribution**: Splitting shares according to configured ratios (`test_distributeFees`, `test_distributeFees_afterFeeSplitIsSet`, `test_distributeFees_afterFeeFractionIsSet`, `test_distributeFees_afterMainRecipientIsSet`, `test_distributeFees_afterSecondaryRecipientIsSet`)
- **Validation**: Invalid fee splits, zero addresses, fee fraction bounds (`test_fail_setFeeSplit_InvalidFeeSplit`, `test_fail_setFeeSplit_feeFractionOutOfBounds`, `test_fail_setFeeFraction_OutOfBounds`, `test_fail_distributeFees_VaultInvalidOrWIthInvalidFeeSplit`, `test_fail_setSecondaryRecipient_WithoutPreviousFeeSplitBeingSet`)
- **Access control**: Owner and vault manager permissions (`test_fail_setFeeSplit_Unauthorized`, `test_fail_setMainRecipient_NeitherOwnerNorVaultManager`, `test_fail_setSecondaryRecipient_Unauthorized`)
- **Rescue operations**: Emergency fund recovery (`test_rescueFunds`, `test_fail_rescueFunds_Unauthorized`, `test_fail_rescueFunds_InvalidToken`)

---

#### 2.5.2 Hooks

**File**: `test/periphery/unit-test/HooksUnitTest.t.sol`

**Run tests**:
```bash
forge test --match-path test/periphery/unit-test/HooksUnitTest.t.sol
```

**Tests:**

- **Pre-deposit hooks**: Called before deposits, enforce custom validation like deposit limits (`test_preDeposit_withHooks`, `test_preDeposit_withHooks_fail`)
- **Post-mint hooks**: Called after mints, perform post-action logic (`test_postMint_withHooks`, `test_postMint_withHooks_fail`)
- **Pre-withdraw hooks**: Called before withdrawals, enforce withdrawal restrictions like ownership checks (`test_preWithdraw_withHooks`, `test_preWithdraw_withHooks_fail`)
- **Pre-redeem hooks**: Called before redemptions, enforce redemption restrictions (`test_preRedeem_withHooks`, `test_preRedeem_withHooks_fail`)

---

#### 2.5.3 SimpleStrategy

**File**: `test/periphery/unit-test/SimpleStrategyUnitTest.t.sol`

**Run tests**:
```bash
forge test --match-path test/periphery/unit-test/SimpleStrategyUnitTest.t.sol
```

**Tests:**

- **Initialization**: Strategy setup with admin and vault assignment (`testConstructor`)
- **Fund allocation**: Transferring assets from vault to strategy (`testAllocateFunds`)
- **Fund deallocation**: Returning assets from strategy to vault (`testDeallocateFunds`, `testInsufficientAllocatedAmountDeallocate`)
- **Withdrawal**: Direct withdrawals from strategy (`testOnWithdraw`)
- **Total value tracking**: Accurate accounting of strategy holdings (`testTotalAllocatedValue`)
- **Max allocation and withdrawal**: Strategy capacity limits (`testMaxAllocation`, `testMaxWithdraw`, `testSetMaxWithdrawEvent`, `testSetMaxWithdrawEventMultipleChanges`)
- **Strategy metadata**: Asset, vault, and type information (`testStrategyType`)
- **Access control**: Vault-only operations for fund management (`testUnauthorizedAccess`)
- **Emergency operations**: Emergency fund recovery (`testEmergencyRecover`, `testEmergencyRecoverUnauthorized`, `testEmergencyRecoverAssetToken`)
- **Pause functionality**: Pausing/unpausing strategy operations (`testPause`, `testUnpause`, `testPauseUnauthorized`, `testUnpauseUnauthorized`, `testPausePreventsOperations`)
- **Error handling**: Insufficient balance checks (`testInsufficientBalance`)

---

#### 2.5.4 MultisigStrategy

**File**: `test/periphery/unit-test/MultisigStrategyUnitTest.t.sol`

**Run tests**:
```bash
forge test --match-path test/periphery/unit-test/MultisigStrategyUnitTest.t.sol
```

**Tests:**

- **Initialization**: Setup with multisig address, accounting thresholds, cooldown periods (`testConstructor`, `testInitialization`, `testInitializeRevertIfInvalidMultiSigAddress`)
- **Multisig management**: Setting and updating multisig address (`testSetMultiSig`)
- **Operator management**: Setting strategy operator (`testSetOperator`)
- **Position accounting**: Recording off-chain positions, validating accounting changes against thresholds, nonce tracking (`testAccountingNonce`)
- **Accounting parameters**: Setting max accounting change threshold, validity period, cooldown period (`testSetMaxAccountingChangeThreshold`, `testSetMaxAccountingChangeThresholdInvalid`, `testSetAccountingValidityPeriod`, `testSetCooldownPeriod`, `testMinimumPeriodDifferenceValidation`)
- **Withdraw mode**: Deallocate and withdraw behavior when withdraw is enabled/disabled (`testDeallocateWhenWithdrawDisabled`, `testWithdrawWhenWithdrawDisabled`, `testDeallocateWhenWithdrawEnabled`, `testWithdrawWhenWithdrawEnabled`)
- **Pause functionality**: Pausing/unpausing strategy operations (`testPauseUnpause`)
- **Access control**: Admin, multisig, and operator roles (`testUnauthorizedAccess`)
- **Validation**: Invalid parameter handling (`testInvalidParameters`)

---

#### 2.5.5 ShareDistributor

**File**: `test/periphery/unit-test/ShareDistributorTest.t.sol`

**Run tests**:
```bash
forge test --match-path test/periphery/unit-test/ShareDistributorTest.t.sol
```

**Tests:**

- Share distribution functionality (41 test functions covering various distribution scenarios, recipient management, and validation)

---

## 3. Fuzz Testing

### 3.1 Overview

Fuzz testing (property-based testing) uses randomly generated inputs to test smart contract functions across a wide range of scenarios. Unlike unit tests that use specific, predetermined values, fuzz tests generate hundreds or thousands of random inputs to discover edge cases and unexpected behaviors.

**How Fuzz Tests Work:**

1. **Random Input Generation**: The test framework (Foundry) generates random values for function parameters
2. **Bounded Inputs**: Test writers use `bound()` to constrain random values to realistic ranges (e.g., `bound(amount, 1e18, 1000000e18)`)
3. **Property Verification**: Tests verify that invariants and expected properties hold true across all generated inputs
4. **Edge Case Discovery**: Random inputs often reveal edge cases that manual test writing might miss

**Why Bounds are Important:**

- **Realistic constraints**: Prevent testing unrealistic scenarios (e.g., deposits larger than total token supply)
- **Type safety**: Keep values within valid ranges for data types (e.g., `uint16` fees must be ≤ 65535)
- **Gas optimization**: Avoid extremely large values that would cause out-of-gas errors
- **Domain logic**: Enforce business rules (e.g., management fees capped at 10%)

**Currently, only core contracts have fuzz tests** (no periphery fuzz tests yet).

**Fuzz Test Location**: `test/fuzz/`

---

### 3.2 AllocateModule Fuzz Tests

**File**: `test/fuzz/AllocateModule/AllocateModuleFuzzTest.t.sol`

**Run tests**:
```bash
forge test --match-path test/fuzz/AllocateModule/AllocateModuleFuzzTest.t.sol
```

**Tests:**

- **Fund allocation/deallocation**: Tests allocate and deallocate operations with random amounts and directions (`testFuzzAllocateFunds`)
  - **Bounded inputs**:
    - `isDeposit`: Random boolean determining allocation vs deallocation
    - `amount`: 0 to `type(uint120).max` (realistic upper bound)
  - **Logic**: Ensures deallocation doesn't exceed already allocated amount
  - **Properties verified**: Allocation accounting remains consistent regardless of random inputs

---

### 3.3 ConcreteStandardVaultImpl Fuzz Tests

**Directory**: `test/fuzz/ConcreteStandardVaultImpl/`

**Run all tests**:
```bash
forge test --match-path test/fuzz/ConcreteStandardVaultImpl/
```

#### ManagementFeeFuzzTest.t.sol

**Run tests**:
```bash
forge test --match-path test/fuzz/ConcreteStandardVaultImpl/ManagementFeeFuzzTest.t.sol
```

**Tests:**

- **Management fee accrual with random parameters**: Tests fee calculations across various time periods, deposits, and fee rates (`testFuzzManagementFeeAccrual`)
  - **Bounded inputs**:
    - `timeElapsed`: 1 second to 2 years (realistic time ranges)
    - `initialDeposit`: 1 to 1,000,000 tokens
    - `managementFee`: 0.01% to 10% (1 to 1000 basis points, enforcing max allowed)
  - **Properties verified**:
    - Fee accrual matches expected calculation: `(totalAssets × fee × timeElapsed) / (365 days × 10,000)`
    - Share minting to fee recipient is accurate
    - Fees accrue correctly over multiple time periods
    - No fees charged on initial deposit

#### PerformanceFeeFuzzTest.t.sol

**Run tests**:
```bash
forge test --match-path test/fuzz/ConcreteStandardVaultImpl/PerformanceFeeFuzzTest.t.sol
```

**Tests:**

- **Performance fee accrual with random yields**: Tests fee calculations on positive yields with various parameters (`testFuzzPerformanceFeeAccrual`)
  - **Bounded inputs**:
    - `performanceFee`: 0.01% to 10% (1 to 1000 basis points)
    - `allocateAmount`: 0 to initial deposit amount
    - `positiveYield`: 0 to 50% of initial deposit
  - **Properties verified**:
    - Performance fee only charged on net positive yield
    - Fee calculation: `(netPositiveYield × performanceFee) / 10,000`
    - Correct share minting to fee recipient (within 1 wei tolerance for rounding)
    - No fee when there's no positive yield

#### ConcreteStandardVaultUserOpsTest.t.sol

**Run tests**:
```bash
forge test --match-path test/fuzz/ConcreteStandardVaultImpl/ConcreteStandardVaultUserOpsTest.t.sol
```

**Tests:**

- **Complex user operations with multiple variables**: Tests withdrawal scenarios combining yield/loss, fees, limits, and permissions (`testFuzzWithdrawStandardWithYieldFeesLimitsAndOnBehalfOf`)
  - **Bounded inputs**:
    - `assets`: 1 to total available supply
    - `yieldOrLoss`: Negative (loss) to positive (yield), bounded by strategy allocation
    - `withdrawAmount`: 1 to 2× total supply
    - `performanceFee`: 0 to max allowed (10%)
    - `managementFee`: 0 to max allowed (10%)
    - `globalMinWithdrawAmount` / `globalMaxWithdrawAmount`: Withdrawal limit ranges
    - `sender` / `receiver`: Random addresses for on-behalf-of operations
  - **Properties verified**:
    - Withdrawals work correctly with yield generation and losses
    - Fee calculations remain accurate during user operations
    - Withdrawal limits are properly enforced
    - On-behalf-of withdrawals handle allowances correctly
    - Share and asset accounting remains consistent across all scenarios

---

### 3.4 Invariant Testing

Invariant testing (stateful fuzzing) is an advanced form of property-based testing that validates system-wide properties across arbitrary sequences of actions. Unlike standard fuzz tests that test individual functions, invariant tests execute random sequences of many operations and verify that critical properties ("invariants") hold true after every operation.

**How Invariant Tests Work:**

1. **Handler Setup**: Define a handler contract with bounded operations (deposits, withdrawals, strategy allocations, etc.)
2. **Random Sequence Generation**: Foundry generates random sequences of handler operations
3. **Invariant Checking**: After each operation sequence, all invariant functions are executed to verify properties still hold
4. **Actor Management**: Multiple users with different roles perform operations to simulate realistic scenarios

**Why Invariant Testing is Powerful:**

- **State Exploration**: Tests complex interactions between multiple operations
- **Edge Case Discovery**: Finds sequences of operations that break invariants
- **Real-World Simulation**: Models actual usage patterns with multiple users and strategies
- **Comprehensive Coverage**: Tests entire system behavior, not just individual functions

**Currently, invariant tests are only defined for vaults** (ConcreteStandardVaultImpl).

**Invariant Test Location**: `test/invariant/`

#### Test Files

- **`InvariantTestBase.t.sol`**: Base setup with multi-user and multi-strategy configuration
- **`VaultInvariant.t.sol`**: Main invariant test contract with all invariant assertions
- **`handlers/ConcreteStandardVaultHandler.t.sol`**: Handler defining bounded vault operations
- **`helpers/ActorUtil.sol`**: Multi-user actor management utility
- **`helpers/InvariantUtils.sol`**: Mathematical utilities for invariant calculations

**Run invariant tests**:
```bash
FOUNDRY_PROFILE=invariant forge test -vv
```

**Run specific invariant**:
```bash
FOUNDRY_PROFILE=invariant forge test -vv --match-test invariant_vault_solvency
```

---

#### Actor Setup

The invariant tests use a multi-actor system to simulate realistic vault usage:

**System Actors** (privileged roles):
- **Vault Manager** (Index 0): Admin role, manages vault settings
- **Strategy Operator** (Index 1): Adds/removes strategies
- **Allocator** (Index 2): Allocates funds to strategies
- **Factory Owner** (Index 3): Factory-level admin
- **Fee Recipient** (Index 4): Receives management and performance fees

**Regular Users** (Index 5+):
- User1: Performs deposits, withdrawals, mints, redeems
- Initial balance: 1,000,000 tokens each

**Actor Selection**: Each handler operation receives a random seed to select which actor performs the action, ensuring realistic multi-user scenarios.

---

#### Handler Operations

The `ConcreteStandardVaultHandler` defines 12 bounded operations that are randomly executed:

**User Operations:**
- `deposit(actorSeed, assets)` - User deposits assets into vault
- `mint(actorSeed, shares)` - User mints shares from vault
- `withdraw(actorSeed, assets)` - User withdraws assets from vault
- `redeem(actorSeed, shares)` - User redeems shares for assets

**Strategy Management:**
- `allocateToStrategy(strategyIndex, amount)` - Allocator allocates vault funds to strategy
- `deallocateFromStrategy(strategyIndex, amount)` - Allocator deallocates funds from strategy
- `addNewStrategy()` - Strategy operator adds new strategy (max 10 strategies)
- `removeStrategy(strategyIndex)` - Strategy operator removes strategy

**Yield Operations:**
- `simulateYield(strategyIndex, yieldAmount)` - Simulates positive yield on strategy
- `simulateLoss(strategyIndex, lossAmount)` - Simulates loss on strategy
- `accrueYield(actorSeed)` - Triggers yield accrual to update accounting

**All operations use `bound()` to constrain inputs to realistic ranges** (e.g., deposits bounded to 0-100M tokens, losses bounded to allocated amounts).

---

#### Invariants Tested

**File**: `test/invariant/VaultInvariant.t.sol`

##### 1. Vault Solvency (`invariant_vault_solvency`)

**Property**: The vault must always remain solvent and able to honor all user redemptions.

```solidity
totalAssets >= previewRedeem(totalSupply)
```

**What it validates**: 
- Vault has enough assets to cover redemption of all outstanding shares
- Accounts for unrealized yields and losses from strategies
- Core safety property ensuring users can always withdraw

##### 2. Asset Conservation (`invariant_asset_conservation`)

**Property**: Total vault assets must equal idle assets plus all strategy allocations.

```solidity
cachedTotalAssets == asset.balanceOf(vault) + getTotalAllocated()
```

**What it validates**:
- Perfect accounting of all assets
- No assets are lost or double-counted
- Idle assets + allocated assets = total assets

##### 3. Strategy Allocation Bounds (`invariant_strategy_allocation_bounds`)

**Property**: Sum of all strategy allocations cannot exceed total vault assets.

```solidity
getTotalAllocated() <= cachedTotalAssets
```

**What it validates**:
- Allocation tracking is accurate
- No over-allocation of funds
- Allocation accounting remains consistent

##### 4. ERC4626 Max Function Accuracy (`invariant_erc4626_max_functions`)

**Property**: `maxRedeem()` must respect actual liquidity constraints and user balances.

```solidity
maxRedeem(user) == convertToShares(min(userAssets, availableLiquidity))

where:
  userAssets = convertToAssets(balanceOf(user))
  availableLiquidity = idleAssets + Σ(strategy.maxWithdraw())
```

**What it validates**:
- Max functions reflect real withdrawal constraints
- Considers both user balance and available liquidity
- Accounts for fees when present
- Ensures ERC4626 compliance with multi-strategy liquidity

---

**Additional Documentation**: For detailed mathematical specifications and proofs of each invariant, see `test/invariant/ConcreteStandardVaultImplInvariants.md`

---

## 4. End-to-End Testing

### 4.1 Overview

End-to-End (E2E) tests validate complete user scenarios and workflows by testing the interaction between multiple system components. Unlike unit tests that isolate individual functions and fuzz tests that test individual functions with random inputs, **E2E tests are scenario-based tests** that simulate realistic user journeys from start to finish.

**What Makes E2E Tests Different:**

- **Unit Tests**: Test individual functions in isolation with specific inputs
- **Fuzz Tests**: Test individual functions with random inputs to find edge cases
- **E2E Tests**: Test complete workflows involving multiple functions and components working together

**E2E Test Characteristics:**

1. **Multi-Step Workflows**: Tests include deposit → allocate → accrue yield → withdraw sequences
2. **Component Integration**: Validates that vault, strategies, fees, and factory work together correctly
3. **Realistic Scenarios**: Simulates actual user behavior (multiple users, strategies, yields/losses)
4. **State Transitions**: Validates system behavior across complex state changes

**E2E tests exist in both core and periphery:**
- **Core E2E**: `test/E2E/`
- **Periphery E2E**: `test/periphery/E2E/`

---

### 4.2 Core Strategy Management Tests

#### DeallocationOrderE2ETest.t.sol

**File**: `test/E2E/DeallocationOrderE2ETest.t.sol`

**Run tests**:
```bash
forge test --match-path test/E2E/DeallocationOrderE2ETest.t.sol
```

**Scenario**: Tests that withdrawals follow configured deallocation order when pulling funds from multiple strategies

**Tests:**
- **Deallocation order enforcement**: Withdrawals pull funds from strategies in specified order (`testWithdrawalsFollowDeallocationOrder`)
- **Order configuration**: Cannot add non-existent or zero addresses to order (`testCannotAddNonExistentStrategyToDeallocationOrder`, `testCannotAddZeroAddressToDeallocationOrder`)
- **Strategy removal constraints**: Cannot remove strategies that are in deallocation order unless removed from order first (`testCannotRemoveStrategyInDeallocationOrder`, `testCanRemoveStrategyAfterRemovingFromDeallocationOrder`)
- **Halted strategies**: Halted strategies can be removed even if in deallocation order, cannot add halted strategies to order (`testHaltedStrategyCanBeRemovedEvenInDeallocationOrder`, `testCannotAddHaltedStrategyToDeallocationOrder`)
- **Max withdraw calculations**: `maxWithdraw` respects deallocation order (`testMaxWithdrawFollowDeallocationOrder`)

---

#### HaltedStrategyE2ETest.t.sol

**File**: `test/E2E/HaltedStrategyE2ETest.t.sol`

**Run tests**:
```bash
forge test --match-path test/E2E/HaltedStrategyE2ETest.t.sol
```

**Scenario**: Tests strategy halting/resumption and how halted strategies are excluded from operations

**Tests:**
- **Status toggling**: Toggling strategies between Active and Halted states (`testToggleStrategyFromActiveToHalted`, `testToggleStrategyFromHaltedToActive`, `testMultipleStrategyStatusToggles`)
- **Allocation exclusion**: Halted strategies are skipped during allocation operations (`testAllocationIgnoresHaltedStrategies`)
- **Withdrawal exclusion**: Halted strategies are skipped during withdrawal operations (`testWithdrawalIgnoresHaltedStrategies`)
- **Yield accrual exclusion**: Halted strategies are skipped during yield accrual (`testAccrueYieldIgnoresHaltedStrategies`)
- **Removal rules**: Halted strategies can be removed with allocated funds, active strategies cannot (`testRemoveHaltedStrategyWithAllocatedFunds`, `testCannotRemoveActiveStrategyWithAllocatedFunds`, `testRemoveActiveStrategyWithZeroAllocation`)
- **Strategy migration**: Can migrate from halted strategy to new strategy (`testMigrateHaltedStrategyWithAllocatedFunds`)
- **Combined operations**: Halted strategies are properly excluded from allocation and withdrawal in same transaction (`testHaltedStrategySkipsAllocationAndWithdrawal`)
- **Access control**: Unauthorized users cannot toggle strategy status (`testToggleStrategyRevertsForUnauthorizedUser`)

---

### 4.3 Vault Tests

#### VaultMigrationE2ETest.t.sol

**File**: `test/E2E/VaultMigrationE2ETest.t.sol`

**Run tests**:
```bash
forge test --match-path test/E2E/VaultMigrationE2ETest.t.sol
```

**Scenario**: Tests complete vault migration workflow from one implementation to another

**Tests:**
- **Migration workflow**: Deploy vault with version 1, migrate to version 2, verify state and functionality (`testDeployProxyWithStandardImplAndMigrateToCAnotherImpl`)
  - Validates implementation upgrade
  - Verifies name/symbol changes during upgrade
  - Ensures migration path is properly configured

---

#### WithdrawFromAllocatedVaultE2ETest.t.sol

**File**: `test/E2E/WithdrawFromAllocatedVaultE2ETest.t.sol`

**Run tests**:
```bash
forge test --match-path test/E2E/WithdrawFromAllocatedVaultE2ETest.t.sol
```

**Scenario**: Tests withdrawal workflows when funds are allocated across multiple strategies with various conditions

**Tests:**
- **Idle funds withdrawals**: Withdrawals covered entirely by idle vault funds (`testWithdrawFromIdleFundsOnly`)
- **Strategy profit handling**: Withdrawals with profit in strategies (`testWithdrawWithProfitInStrategyAndWithdraw`)
- **Strategy deallocation**: Withdrawals requiring strategy deallocation (`testWithdrawRequiringStrategyDeallocation`)
- **Multi-strategy withdrawals**: Withdrawals pulling from multiple strategies (`testWithdrawFromMultipleStrategies`)
- **Yield scenarios**: Withdrawals with positive yields in strategies (`testWithdrawWithYieldInStrategies`)
- **Loss scenarios**: Withdrawals with losses in strategies (`testWithdrawWithLossInStrategies`)
- **Insufficient liquidity**: Withdrawal requests exceeding available liquidity (`testWithdrawWithInsufficientLiquidity`)
- **Max withdraw calculations**: `maxWithdraw()` accuracy with allocated strategies (`testMaxWithdrawCalculations`)
- **Yield accrual trigger**: Withdrawals trigger yield accrual before execution (`testWithdrawTriggersYieldAccrual`)
- **Redeem operations**: Redeem operations from allocated strategies (`testRedeemFromAllocatedStrategies`)
- **Multi-user scenarios**: Partial withdrawals from multiple users with strategies (`testPartialWithdrawFromMultipleUsersWithStrategies`)

---

### 4.4 Fee Tests

#### ManagementFeeAccrualE2ETest.t.sol

**File**: `test/E2E/ManagementFeeAccrualE2ETest.t.sol`

**Run tests**:
```bash
forge test --match-path test/E2E/ManagementFeeAccrualE2ETest.t.sol
```

**Scenario**: Tests management fee accrual across various time periods and vault operations

**Tests:**
- **Fee accrual**: Management fees accrue correctly over time based on total assets and time elapsed (`testAccrueManagementFee`)
- **Zero time elapsed**: No fees when no time has passed (`testAccrueManagementFeeWhenNoTimeElapsed`)
- **Fee on deposits**: Fees accrue when users deposit after time has passed (`testAccrueManagementFeeDuringDeposit`)
- **Zero fee rate**: No fees charged when fee rate is zero (`testAccrueManagementFeeWithZeroFee`)
- **Fee updates**: Updating fee rate triggers accrual of pending fees (`testManagementFeeUpdateWithoutSync`)
- **Large deposits**: Fee accrual with 5% management fee on large deposits (`testManagementFeeAccrual_5Percent_LargeDeposit`)
- **Time-based accrual**: Fees after one day, no time elapsed, multiple accruals (`testManagementFeeAccrual_NoTimeElapsed`, `testManagementFeeAccrual_OneDay`, `testManagementFeeAccrual_MultipleAccruals`)

---

#### PerformanceFeeE2ETest.t.sol

**File**: `test/E2E/PerformanceFeeE2ETest.t.sol`

**Run tests**:
```bash
forge test --match-path test/E2E/PerformanceFeeE2ETest.t.sol
```

**Scenario**: Tests performance fee charging on strategy yields across various scenarios

**Tests:**
- **Fee on yield**: Performance fees charged correctly on positive yield (`testPerformanceFeeAccrualOnYield`)
- **No fee without yield**: No performance fees when there's no yield (`testNoPerformanceFeeOnNoYield`)
- **Multiple accruals**: Performance fees on multiple yield accrual events (`testPerformanceFeeOnMultipleYieldAccruals`)
- **User withdrawals**: Users can withdraw after performance fees are charged (`testUserWithdrawalAfterPerformanceFee`)
- **Multi-user scenarios**: Performance fees calculated correctly with multiple users (`testPerformanceFeeWithMultipleUsers`)
- **Zero fee rate**: No fees when performance fee rate is zero (`testPerformanceFeeWithZeroFeeRate`)
- **Deposit triggers accrual**: Deposits trigger yield accrual and performance fee calculation (`testPerformanceFeeOnDepositTriggersYieldAccrual`)
- **Loss scenarios**: No performance fees charged when strategy has losses (`testPerformanceFeeWithStrategyLoss`)
- **Net positive yield**: Performance fees on net positive yield after previous loss (`testPerformanceFeeOnNetPositiveYieldAfterLoss`)

---

### 4.5 Cross-Chain Tests

#### LayerZeroClaimE2ETest.t.sol

**File**: `test/E2E/LayerZeroClaimE2ETest.t.sol`

**Run tests**:
```bash
forge test --match-path test/E2E/LayerZeroClaimE2ETest.t.sol
```

**Scenario**: Tests cross-chain share claiming via LayerZero messaging protocol

**Tests:**
- **Single claim flow**: User deposits on source chain, claims shares on destination chain (`test_E2E_singleClaim_fullFlow`)
- **Multiple users**: Multiple users claiming shares on destination chain (`test_E2E_multipleUsersClaim`)
- **Batch claiming**: Batch claim operations for multiple users (`test_E2E_batchClaim_fullFlow`)
- **Duplicate handling**: Batch claims with duplicate user addresses (`test_E2E_batchClaim_withDuplicates`)
- **Exchange rate consistency**: Exchange rate remains constant across chains (`test_E2E_exchangeRate_remainsConstant`)
- **Emergency withdrawals**: Emergency withdrawal functionality (`test_E2E_emergencyWithdraw`)
- **Self-claims disabled**: Reverts when self-claims are disabled (`test_E2E_revertsWhenSelfClaimsDisabled`)
- **Deposits not locked**: Reverts when deposits aren't locked yet (`test_E2E_revertsWhenDepositsNotLocked`)
- **No shares**: Reverts when user has no shares to claim (`test_E2E_revertsWithNoShares`)

---

### 4.6 Periphery Strategy Tests

#### SimpleStrategyE2ETest.t.sol

**File**: `test/periphery/E2E/SimpleStrategyE2ETest.t.sol`

**Run tests**:
```bash
forge test --match-path test/periphery/E2E/SimpleStrategyE2ETest.t.sol
```

**Scenario**: Tests SimpleStrategy integration with vault across complete allocation/deallocation workflows

**Tests:**
- **Initialization**: Strategy properly initialized with vault and admin (`testStrategyInitialization`)
- **Allocation through vault**: Vault allocates funds to strategy (`testAllocateFundsThroughVault`)
- **Deallocation through vault**: Vault deallocates funds from strategy (`testDeallocateFundsThroughVault`)
- **Withdrawals**: Strategy withdrawals triggered by vault withdrawals (`testWithdrawThroughVault`)
- **Multi-user operations**: Multiple users depositing and interacting with strategy (`testMultipleUsersWithStrategy`)
- **Max withdraw**: `maxWithdraw()` calculations (`testMaxWithdraw`)
- **Access control**: Unauthorized access prevention (`testUnauthorizedAccess`)
- **Insufficient funds**: Error handling for insufficient allocated amounts (`testInsufficientAllocatedAmount`)
- **Emergency recovery**: Emergency fund recovery functionality (`testEmergencyRecover`, `testEmergencyRecoverUnauthorized`, `testEmergencyRecoverAssetToken`)
- **Total allocated value**: Accurate tracking of allocated value (`testTotalAllocatedValue`)
- **Convert functions**: ERC4626 convert functions unaffected by strategy operations (`testConvertFunctionsUnaffectedByStrategyOperations`)

---

#### MultisigStrategyE2ETest.t.sol

**File**: `test/periphery/E2E/MultisigStrategyE2ETest.t.sol`

**Run tests**:
```bash
forge test --match-path test/periphery/E2E/MultisigStrategyE2ETest.t.sol
```

**Scenario**: Tests MultisigStrategy integration with vault, including off-chain accounting and multisig operations

**Tests:**
- **Initialization**: Strategy initialized with multisig, accounting thresholds, and cooldown periods (`testStrategyInitialization`)
- **Allocation through vault**: Vault allocates funds to strategy (`testAllocateFundsThroughVault`)
- **Deallocation through vault**: Vault deallocates funds from strategy (`testDeallocateFundsThroughVault`)
- **Withdrawals**: Strategy withdrawals via vault (`testWithdrawThroughVault`)
- **Insufficient vault balance**: Strategy withdrawals when vault balance is insufficient (`testWithdrawFromStrategyWhenVaultBalanceInsufficient`)
- **Multi-user operations**: Multiple users with multisig strategy (`testMultipleUsersWithStrategy`)
- **Max withdraw**: `maxWithdraw()` calculations with accounting (`testMaxWithdraw`)
- **Withdraw disabled mode**: Behavior when withdrawals are disabled (`testWithdrawDisabled`)
- **Operator role**: Operator role functionality for accounting updates (`testOperatorRole`)
- **Access control**: Unauthorized access prevention (`testUnauthorizedAccess`)
- **Insufficient funds**: Error handling (`testInsufficientAllocatedAmount`)
- **Emergency recovery**: Emergency fund recovery (`testEmergencyRecover`, `testEmergencyRecoverUnauthorized`, `testEmergencyRecoverAssetToken`)
- **Total allocated value**: Accurate value tracking (`testTotalAllocatedValue`)
- **Multisig balance tracking**: Tracking assets held by multisig (`testMultisigBalanceTracking`)
- **Valid accounting adjustments**: Accounting adjustments with yield (`testValidAccountingAdjustmentWithYield`)
- **Cooldown period**: Cooldown period enforcement between accounting updates (`testCooldownPeriodViolation`)
- **Large changes**: Large accounting change threshold enforcement (`testLargeAccountingChangeViolation`)
- **Validity period**: Accounting validity period expiration (`testAccountingValidityPeriodExpired`, `testAccountingValidityPeriodExpiredWithAllocationModule`)

---

## 5. Testing Utilities

### 5.1 Overview

The test suite includes a comprehensive set of reusable utilities that enable efficient and consistent test writing across all test types. These utilities are organized into three main categories:

1. **Mocks**: Simplified implementations of contracts for testing specific behaviors
2. **Base Test Contracts**: Standardized setup configurations that all tests inherit from
3. **Test Utilities**: Helper functions and contracts for common test operations

**Location**: `test/mock/`, `test/common/`

---

### 5.2 Mocks

**Location**: `test/mock/`

Mocks are simplified contract implementations that provide controlled, predictable behavior for testing. They allow tests to focus on specific functionality without depending on complex external contracts.

#### ERC20Mock.sol

**Purpose**: Simple ERC20 token for testing vault deposits, withdrawals, and transfers

**Key Features**:
- `mint(address, uint256)`: Mint tokens to any address
- `burn(address, uint256)`: Burn tokens from any address
- No access control for easy test setup

**Usage**: Used as the base asset in virtually all vault tests

---

#### ERC4626StrategyMock.sol

**Purpose**: Mock strategy implementing `IStrategyTemplate` interface for testing vault-strategy interactions

**Key Features**:
- `allocateFunds(bytes)`: Simulates allocating funds to underlying ERC4626 vault
- `deallocateFunds(bytes)`: Simulates deallocating funds from underlying vault
- `onWithdraw(uint256)`: Handles withdrawal requests from vault
- `simulateYield(uint256)`: Simulates positive yield generation
- `simulateLoss(uint256)`: Simulates strategy losses
- `emergencyRescue(address)`: Simulates emergency fund recovery

**Usage**: Primary mock for testing multi-strategy vault functionality, yield accrual, and allocation logic

---

#### StandardHookV1.sol

**Purpose**: Mock hook implementation for testing vault hook system

**Key Features**:
- `preDeposit()`: Validates deposits against deposit limit
- `preWithdraw()`: Validates sender is owner
- `preRedeem()`: Validates sender is owner
- `postMint()`: Validates mints against deposit limit
- Customizable deposit limit for testing constraints

**Usage**: Tests hook integration, custom validation logic, and access control patterns

---

#### ERC4626Mock.sol / ConcreteERC4626Mock.sol

**Purpose**: Mock ERC4626 vaults for testing strategy implementations

**Key Features**:
- Standard ERC4626 interface implementation
- Controllable for testing edge cases
- Used by `ERC4626StrategyMock`

---

#### ShareDistributorMock.sol

**Purpose**: Mock share distributor for testing cross-chain predeposit functionality

**Key Features**:
- Simulates share distribution on destination chain
- Used in LayerZero tests

---

#### MockPredepositVault.sol

**Purpose**: Mock predeposit vault for testing cross-chain claim flows

**Key Features**:
- Simplified predeposit vault behavior
- Used in cross-chain testing scenarios

---

### 5.3 Base Test Contracts

**Location**: `test/common/`

Base test contracts provide standardized setup and configuration that all tests inherit from. They follow an inheritance hierarchy where each level adds more specific setup.

#### ConcreteFactoryBaseSetup.t.sol

**Level**: Foundation (Level 0)

**Purpose**: Deploys and initializes the ConcreteFactory

**Provides**:
- `factory`: Deployed ConcreteFactory instance
- `factoryOwner`: Address with factory admin rights

**Inherited by**: All test contracts (directly or indirectly)

---

#### TestBaseSetup.t.sol

**Level**: Core Setup (Level 1)

**Purpose**: Extends `ConcreteFactoryBaseSetup` with ConcreteStandardVaultImpl approval

**Provides**:
- Everything from `ConcreteFactoryBaseSetup`
- `concreteStandardVaultImpl`: Deployed and approved standard vault implementation (version 1)

**Inherited by**: Most core vault tests

---

#### TestBaseAsyncSetup.t.sol

**Level**: Async Setup (Level 1)

**Purpose**: Extends `ConcreteFactoryBaseSetup` with ConcreteAsyncVaultImpl approval

**Provides**:
- Everything from `ConcreteFactoryBaseSetup`
- `concreteAsyncVaultImpl`: Deployed and approved async vault implementation (version 1)

**Inherited by**: Async vault tests

---

#### ConcreteStandardVaultImplBaseSetup.t.sol

**Level**: Standard Vault Setup (Level 2)

**Purpose**: Complete setup for testing ConcreteStandardVaultImpl with all roles and dependencies

**Provides**:
- Everything from `TestBaseSetup`
- `asset`: ERC20Mock token
- `allocateModule`: AllocateModule instance
- `concreteStandardVault`: Deployed standard vault instance
- `vaultOwner`: Vault owner address
- `vaultManager`: Vault manager with admin role
- `hookManager`: Hook manager role
- `strategyOperator`: Strategy manager role
- `allocator`: Allocator role
- All roles properly granted and configured

**Inherited by**: Most ConcreteStandardVaultImpl unit tests and E2E tests

---

#### ConcreteAsyncVaultImplBaseSetup.t.sol

**Level**: Async Vault Setup (Level 2)

**Purpose**: Complete setup for testing ConcreteAsyncVaultImpl with withdrawal queue functionality

**Provides**:
- Everything from `TestBaseAsyncSetup`
- `asset`: ERC20Mock token
- `allocateModule`: AllocateModule instance
- `concreteAsyncVault`: Deployed async vault instance
- All standard roles PLUS:
  - `withdrawalManager`: Manages epoch processing and claims
- All roles properly granted and configured

**Inherited by**: ConcreteAsyncVaultImpl tests

---

#### ConcretePredepositVaultImplBaseSetup.t.sol

**Level**: Predeposit Vault Setup (Level 2)

**Purpose**: Complete setup for testing cross-chain predeposit functionality with LayerZero

**Provides**:
- Everything from `TestBaseSetup`
- `predepositVault`: Deployed predeposit vault on source chain
- `predepositVaultOApp`: LayerZero OApp for cross-chain messaging
- `destinationVault`: Standard vault on destination chain
- `distributor`: ShareDistributor for destination chain
- LayerZero endpoints configured for both chains (`aEid`, `bEid`)
- Peer connections configured between chains
- All roles configured on both chains

**Inherited by**: Predeposit vault and LayerZero cross-chain tests

---

#### ConcreteBridgedAsyncVaultImplBaseSetup.t.sol

**Level**: Bridged Async Vault Setup (Level 2)

**Purpose**: Setup for testing bridged async vault with unbacked minting

**Provides**:
- Everything needed for bridged async vault testing
- Similar to `ConcreteAsyncVaultImplBaseSetup` but for bridged variant

**Inherited by**: ConcreteBridgedAsyncVaultImpl tests

---

### 5.4 Test Utilities

**Location**: `test/common/`

Test utilities provide reusable helper functions that simplify common testing operations.

#### AddStrategyWithDeallocationOrder.sol

**Purpose**: Helper contract to add strategies to vaults and automatically configure deallocation order

**Function**:
```solidity
function addStrategyWithDeallocationOrder(
    address strategy_,
    address concreteVaulAddress_,
    address allocator_,
    address strategyOperator_
) internal
```

**What it does**:
1. Adds strategy to vault using `strategyOperator_` role
2. Retrieves current deallocation order
3. Appends new strategy to end of deallocation order
4. Updates deallocation order using `allocator_` role

**Why it's useful**: 
- Strategies must be in deallocation order to be usable for withdrawals
- Manually managing order arrays in every test is error-prone
- Ensures consistent strategy setup across all tests

**Usage**: Mix into test contracts that need to add strategies:
```solidity
contract MyTest is ConcreteStandardVaultImplBaseSetup, AddStrategyWithDeallocationOrder {
    function testWithStrategy() public {
        ERC4626StrategyMock strategy = new ERC4626StrategyMock(address(asset));
        addStrategyWithDeallocationOrder(
            address(strategy),
            address(concreteStandardVault),
            allocator,
            strategyOperator
        );
        // Strategy is now ready to use
    }
}
```

---

### Base Test Contract Inheritance Hierarchy

```
ConcreteFactoryBaseSetup (Level 0)
    ├── TestBaseSetup (Level 1)
    │   ├── ConcreteStandardVaultImplBaseSetup (Level 2)
    │   └── ConcretePredepositVaultImplBaseSetup (Level 2)
    └── TestBaseAsyncSetup (Level 1)
        ├── ConcreteAsyncVaultImplBaseSetup (Level 2)
        └── ConcreteBridgedAsyncVaultImplBaseSetup (Level 2)
```

**Guidelines for Choosing Base Contract**:

- **Testing factory only**: Use `ConcreteFactoryBaseSetup`
- **Testing standard vault**: Use `ConcreteStandardVaultImplBaseSetup`
- **Testing async vault**: Use `ConcreteAsyncVaultImplBaseSetup`
- **Testing bridged async vault**: Use `ConcreteBridgedAsyncVaultImplBaseSetup`
- **Testing predeposit/cross-chain**: Use `ConcretePredepositVaultImplBaseSetup`
- **Need custom setup**: Extend appropriate level and add your configuration
