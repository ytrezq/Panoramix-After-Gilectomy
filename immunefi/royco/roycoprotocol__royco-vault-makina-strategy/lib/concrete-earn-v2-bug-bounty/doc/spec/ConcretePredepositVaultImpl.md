# Concrete Predeposit Vault Specification

## Overview

A **Predeposit Vault** on L1 enables users to deposit into a future L2 (or other L1) vault. Assets are bridged to L2 where a **ConcreteBridgedAsyncVault** and **ShareDistributor** are deployed. 

**Key Characteristics:**
- Withdrawals **disabled** on L1 from inception
- Users claim L2 shares (self-serve or batch)
- Shares burned on L1 as L2 shares released
- Exchange rate preserved across migration

**Flow:** L1 deposits → Deposits and withdrawal Lock → Bridge assets → L2 unbacked mint and donate assets to multisig strategy → Users claim L2 shares → withdrawals open

---

## Contracts & Roles

### L1 Contracts

**ConcretePredepositVaultImpl** - Standard ERC4626 vault with cross-chain claiming:
- Accepts deposits, mints shares
- Withdrawals permanently locked (limits = 0)
- Deposits locked when migration starts (limits = 0)
- Burns shares and sends LayerZero messages for claims
- Tracks locked shares per user

**PredepostVaultOApp** - LayerZero messaging:
- Sends authenticated messages to L2
- Quote messaging fees

### L2 Contracts

**ConcreteBridgedAsyncVault** - ERC4626 vault with unbacked minting:
- `unbackedMint()` - one-time mint without assets (totalSupply must be 0)
- Receives bridged assets via strategies
- Maintains L1 exchange rate
- Initially paused, enabled after migration

**ShareDistributor** - LayerZero receiver:
- Receives claim messages from L1
- Holds pre-minted shares
- Distributes to users automatically
- Emergency withdraw function

### Roles

- **VAULT_MANAGER**: Lock deposits, set OApp, enable claims, unbackedMint, emergency withdraw
- **STRATEGY_MANAGER**: Add/remove strategies
- **ALLOCATOR**: Allocate funds to strategies
- **VAULT_OWNER**: Set LayerZero peer configuration

---

## Migration Lifecycle

### 1. Open Phase (L1)
- Users deposit via `deposit(assets, receiver)` - standard ERC4626
- Vault mints shares, withdrawals disabled (limits = 0)
- Assets allocated to L1 strategies

### 2. Deposit Lock
- Vault manager: `setDepositLimits(0, 0)`
- Total supply frozen
- No new deposits accepted

### 3. Bridge & Seed L2

**Calculate parameters:**
```solidity
uint256 shares = l1Vault.totalSupply();
uint256 rate = l1Vault.convertToAssets(1e18); // e.g., 1.5e18
uint256 assets = l1Vault.totalAssets();
```

Bridge the assets to target chain, under multisig strategy custody.

**L2 Setup:**
```solidity
// 1. Deploy contracts 
ConcreteBridgedAsyncVault l2Vault = factory.create(...);
ShareDistributor distributor = new ShareDistributor(...);
configure the oapps and vaults
set deposit and withdrawal limits of 0 (pause the vault)



In an atomic transaction:
    // 2. Seed the distributor
    l2Vault.unbackedMint(shares);
    l2Vault.transfer(address(distributor), shares);
    
    // 3. Update strategy accounting to match totalAssets bridged
    strategy.pause();
    strategy.unpauseAndAdjustTotalAssets(int256(assets));
    
    // 4. Update vault cache
    l2Vault.accrueYield();
    
    // 5. Verify rate, make sure no fees were applied and erate = l1 erate
    require(l2Vault.convertToAssets(1e18) ≈ rate);
```

**Critical:** Assets sent directly to strategy, reported as yield. Set fees to 0 to avoid charging on migration.

### 4. Claim Window

**Self-serve:**

0. Enable self-claims when setup is correct and sare value matches between chains.

1.quote the LZ fees and send the claim
```solidity
l1Vault.oapp().quoteClaimOnTargetChain(address user, bytes calldata options="", bool payInLzToken=false)
l1Vault.claimOnTargetChain{value: fee}(options);
// Burns L1 shares, sends LZ message, L2 receives shares
```

**Batch (manager only):**
```solidity
l1Vault.batchClaimOnTargetChain{value: fee}(
    abi.encode([user1, user2, ...]), 
    options
);
```

### 5. Normal Operations
- After majority of shares are claimed
- unpause L2 withdrawals (optionally deposits)
- L2 vault fully operational
- Users can deposit, withdraw, redeem on L2

---

## Key Functions

### L1 Predeposit Vault

```solidity
// Standard ERC4626
function deposit(uint256 assets, address receiver) external returns (uint256);
function mint(uint256 shares, address receiver) external returns (uint256);

// Cross-chain claiming
function claimOnTargetChain(bytes calldata options) external payable;
function batchClaimOnTargetChain(bytes calldata addressesData, bytes calldata options) external payable;

// State queries
function getLockedShares(address user) external view returns (uint256);
function getSelfClaimsEnabled() external view returns (bool);
function getOApp() external view returns (address);
```

### L1 Oapp

```solidity
function quoteClaimOnTargetChain(address, bytes calldata, bool) external view returns (MessagingFee);
function quoteBatchClaimOnTargetChain(bytes calldata addressesData, bytes calldata options, bool payInLzToken) external view returns (MessagingFee memory fee)
function send(bytes calldata payload, bytes calldata options, address refundAddress)
```

### L2 Bridged Async Vault

```solidity
// Migration
function unbackedMint(uint256 shares) external; // One-time, totalSupply must be 0

// Standard ERC4626 + Async features
function deposit(uint256 assets, address receiver) external returns (uint256);
function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
function requestRedeem(uint256 shares, address receiver, address owner) external returns (uint256);
function claimWithdrawal(uint256[] calldata epochIDs) external;
function toggleQueueActive() external;
```

### L2 Share Distributor

```solidity
function getAvailableShares() external view returns (uint256);
function claimedShares(address user) external view returns (uint256);
function emergencyWithdraw(uint256 amount) external;
function setPeer(uint32 eid, bytes32 peer) external;
```

---

## Security & Invariants

### Access Control
- **VAULT_MANAGER**: Should be multisig. Controls migration, locks, claims.
- **Self Claims**: Can disable to force batch-only claiming.
- **Emergency**: Distributor emergency withdraw, vault pause, strategy halt.

### Cross-Chain
- LayerZero peer configuration must be correct
- Messages authenticated by LayerZero protocol
- Bridge assets in tranches for security

### Exchange Rate Preservation (Critical)
```solidity
// Must maintain rate across migration
l1Rate = l1Vault.convertToAssets(1e18);
l2Rate = l2Vault.convertToAssets(1e18);
require(abs(l1Rate - l2Rate) <= tolerance);
```

**Important:** Set fees to 0 before migration. Initial strategy value appears as "yield" - don't charge fees on it.

### Accounting Invariants
```solidity
// Locked shares = burned shares
sum(lockedShares[user]) == l1InitialSupply - l1CurrentSupply

// Distributor has correct amount
distributor.getAvailableShares() + sum(claimedShares) == totalMintedShares

// Total supply conserved
l1Vault.totalSupply() + sum(claimedOnL2) + distributor.available == l1InitialSupply
```

---

## Important Notes

### User Warnings

⚠️ **CRITICAL:** 
- Vault decimals must match accross chains!!!!
- Shares sent to **same address** on L2. Must control this address!
- Contract wallets may not exist on L2
- Withdrawals **permanently disabled** on L1
- Only exit: claim on L2 and withdraw there

### Fee Configuration
Set fees to 0 during migration to avoid charging on initial "yield":
```solidity
updatePerformanceFee(0);
updateManagementFee(0);
```

### Migration Checklist

**Pre-Migration:**
- [ ] Deploy L2 vault + distributor
- [ ] Configure LayerZero peers
- [ ] Set L2 fees to 0
- [ ] Test on testnet

**Migration:**
- [ ] Lock L1 deposits: `setDepositLimits(0, 0)`
- [ ] Lock L2 deposits: `setDepositLimits(0, 0)`
- [ ] Lock L2 withdrawal: `setWithdrawalLimits(0, 0)`
- [ ] Bridge assets (in tranches)
  - [ ] `unbackedMint()` on L2
  - [ ] Fund strategies, `accrueYield()`
  - [ ] **Verify exchange rates match**
  - [ ] Transfer shares to distributor

**Post-Migration:**
- [ ] Enable L1 claims
- [ ] Monitor progress
- [ ] eventually Enable L2 vault



### Example: Claim

```solidity
// Self-serve
MessagingFee memory fee = l1Vault.getOapp().quoteClaimOnTargetChain(...);
l1Vault.claimOnTargetChain{value: fee.nativeFee}(options);

// Batch (manager)
l1Vault.batchClaimOnTargetChain{value: fee}(abi.encode([user1, user2]), options);
```

---

## References

- [ERC-4626 Standard](https://eips.ethereum.org/EIPS/eip-4626)
- [LayerZero V2](https://docs.layerzero.network/)
- [Concrete V2 Architecture](../Architecture.md)

