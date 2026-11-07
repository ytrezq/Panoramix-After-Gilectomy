# Concrete Earn V2 Architecture
## Overview 

Concrete V2 is a protocol for aggregating yield and allows curators to deploy vaults permissionlessly. As such it comprises three main components: Vaults of various flavour, a factory for vault deployments and peripherial infrastructure that complement the core features such as bespoke strategies, hooks, fee splitters and other auxiliary contracts.

## Table of Contents

🏭 **[1. Factory](#1-factory)**
- 1.1. Vault Deployment
- 1.2. Implementation and Vault Registry  
- 1.3. Upgrade Vaults

🏦 **[2. Concrete V2 Vaults](#2-concrete-v2-vaults)**
- 2.1. Main User Operations
- 2.2. Vault Accounting
- 2.3. Yield Accrual
- 2.4. Fees
- 2.5. Access Control And Vault Operations
- 2.6. Concrete Vault Implementations
  - 2.6.1. Asynchronous Vault Overview
  - 2.6.2. Access Control and Events
  - 2.6.3. Async Vault Initialization

🔧 **[3. Peripheral Contracts](#3-peripheral-contracts)**
- 3.1. Strategies
  - 3.1.1. Base Strategy Interface
  - 3.1.2. Allocator Fund Movement
  - 3.1.3. Multisig Strategies
- 3.2. Hooks
- 3.3. Fee Splitter


## 1. Factory

The factory is an upgradeable contract that has the following three major functionalities:  
1) deploy vaults
2) register implementations and vaults
3) upgrade vaults

**Factory Architecture:**
- **Upgradeability**: Uses the UUPS (Universal Upgradeable Proxy Standard) proxy pattern for upgradeability
- **Upgrade Control**: Only the factory owner can upgrade the factory implementation
- **Storage Layout**: Implements EIP-7201 storage layout pattern for upgradeable contracts
- **Location**: Factory contracts are located in `src/factory/` directory

### 1.1. Vault Deployment

The deployment of vaults works as follows. The deployer can choose from one of several implementations. Implementations are vault contracts of a certain flavor and with certain unique features, that have been registered in the factory and are indexed in a sequential manner. The deployment of a vault is done via the function 
```js
function create(uint64 version, address ownerAddr, bytes calldata data, bytes32 salt) public returns (address)
```
It is a permissionless function with four arguments. The `version` is the implementation index, the `ownerAddr` is the admin of the vault (see [Section 2.5](#25-access-control-and-vault-operations)), the `data` carries some initialization data and the `salt` allows to create predictable deterministic vault addresses. Upon deployment an ERC-1976 proxy is created that points to the logic of the registered implementations. Upon successful deployment the following event will be emitted:
```js
event Deployed(address indexed vault, uint64 indexed version, address indexed owner); 
``` 
If there is no such version or the version has been blocked, then the call will revert. A useful function for curators to predict their vault addresses is:
```js 
function predictVaultAddress(uint64 version, address ownerAddr, bytes calldata data, bytes32 salt)
```

### 1.2. Implementation and Vault Registry

New implementations can be approved or blocked via the following two functions
```js
function approveImplementation(address implementation) external onlyOwner;
function blockImplementation(uint64 version) external onlyOwner;
```
They will respectively emit the following events:
```js
event ApprovedImplementation(address indexed implementation);
event Blocked(uint64 indexed version);
```
Only approved implementations can be deployed. A new approval automatically receives the latest version plus one, which can be queried via 
```js 
function lastVersion() public view returns (uint64)
```
One may also query the implementation registry via:
```js 
function getImplementationByVersion(uint64 version) public view checkVersion(version) returns (address)
``` 

Regarding the vault registry, it is simply a mapping `mapping(address => bool) vaults;`. There are two ways how vaults can be registered. 
1) Deploy a vault through the factory (see above)
2) Register a vault deployed not through the factory

The default scenario is that a vault gets deployed through the factory. The alternative path is to register it via the following function 
```js
function registerVault(address vault) external onlyOwner
```

One may query the factory about registered vaults via:
```js
function isRegisteredVault(address vault) public view returns (bool)
```

### 1.3. Upgrade Vaults

Deployed vaults may be upgraded. Upgrading means that the implementation of the proxy is changed and re-initialized. However not any implementation can be chosen for the upgrade. The implementation must be approved, non-blocked and migrateable. Migratability is a feature that can be set for any pair of implementations with the constraint that the target has a higher version number.
```js 
function setMigratable(uint64 fromVersion, uint64 toVersion) external onlyOwner
```
One may query the migratability:
```js 
function isMigratable(uint64 fromVersion, uint64 toVersion)
```

In order to upgrade a particular vault to a new version `version` the vault admin has to call 
```js
function upgrade(address vault, uint64 newVersion, bytes calldata data) external
```
on the factory. The calldata `data` is passed into the vault's upgrade function `abi.encodeCall(IUpgradeableVault.upgrade, (version, data))` (for reference see [Vault Interface 2.3](#23-yield-accrual)). A successful upgrade requires the abovementioned guards on the approval, blockage and migratability of source and target implementation to be passed. It then emits the following event:
```js
event Migrated(address indexed vault, uint64 newVersion);
```


## 2. Concrete V2 Vaults

The Concrete V2 Vaults are ERC4626-vaults. They adhere to the standard in all but one place, which regards the reporting of totalAssets. This will be covered in [Section 2.5](#25-access-control-and-vault-operations). These vaults are single-asset vaults in the sense that they take one asset type under management. They allow users to deposit and withdraw and the accounting on the vault level works through an ERC20 token whose balance tracks the holders share of the vault.

**Vault Architecture:**
- **Storage Layout**: Implements EIP-7201 storage layout pattern for upgradeable contracts
- **Storage Management**: Storage and utilities are handled through dedicated libraries
- **Library Structure**: Core functionality is organized in libraries located in `src/lib/` directory
- **Upgradeability**: Vaults are upgradeable through the factory's upgrade mechanism via `UpgradeableVault` base contract (`src/common/UpgradeableVault.sol`)
- **Location**: Vault implementations are located in `src/implementation/` directory 

The vaults can hold several strategies, which are adapters to other protocols or abstract away functions and features to earn yield. Hence the name __Multi-Strategy-Vault__. Accounting of totalAssets happens through a cached variable, rather than a query of `balanceOf`. All vaults are capable of charging various fee types. By default the vaults come with two fee types, which are the management and performance fees.

### 2.1. Main User Operations

For the user operations all vaults expose four main entrypoints:
```js
function deposit(uint256 assets, address receiver) external returns (uint256 shares);
function mint(uint256 shares, address receiver) external returns (uint256 assets);
function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
```
Deposit and Mint allow users to deposit funds into the vault. Those funds need to be of that asset type. They differ in the input and output arguments. Deposit allows the user to pass in the amount that they wish to deposit and returns the amount of minted accounting tokens, also called shares. Mint allows users to pass the amount of shares they wish to mint and returns the amount of assets deposited. Both functions require the holder to approve the vault to spend its tokens. Withdraw and Redeem allow users to withdraw from the vault. They differ again with respect to the input arguments. The former takes the amount of assets and returns the amount of redeemed shares. The latter takes in the amount of shares to be redeemed and returns the asset withdrawn. For each of these functions a different receiver can be designated. Withdrawal and redemption can also happen on behalf of the owner if the approvals are correct.

In Concrete V1 each of these entrypoints had an additional entrypoint for the default case where the receiver equals the `msg.sender`. But in Concrete V2 those additional functions have been omitted.

Each of the user operations has a preview[userOP] and a max[userOP] function. These can be used to preview the shares minted during deposit, the amount deposited during a mint, the redemption amount during a withdraw and the withdrawal amount during a redemption. 

```js 
function previewDeposit(uint256 assets) external view returns (uint256 shares);
function previewMint(uint256 shares) external view returns (uint256 assets);
function previewWithdraw(uint256 assets) external view returns (uint256 shares);
function previewRedeem(uint256 shares) external view returns (uint256 assets);
```

### 2.2. Vault Accounting 

As mentioned above the vault accounting happens through a designated ERC20-token, the vault share. In fact the vault itself is an ERC20 token. There are two values around which most of the accounting is constructed: 1) `totalAssets` and 2) `totalSupply`. The first one is the amount of assets under management and the second one is the amount of shares issued in total. The share worth in asset terms is usually something like the ratio of the two (see below). 

One important feature of the Concrete-V2 vaults is that `totalAssets` is in fact a state variable at the vault. This has two benefits and one draw-back. First of all it safe-guards against donation-attacks, such as the inflation attack. If assets were tracked trough `balanceOf` reporting, they could be manipulated without interacting with the vault, simply by donating to the vault. Second, the gas-costs of multi-strategy vaults typically scale with the amount of strategies. If the total asset reporting were to query each strategy each time it is called, the gas costs would scale unfavourably. Hence a caching can help with that. It does however also mean that the cached variable always needs to be kept up to date. 

Every ERC4626 vault has two functions that allow the conversion of assets and shares and vice versa:
```js
function convertToAssets(uint256 shares) external view returns (uint256 assets);
function convertToShares(uint256 assets) external view returns (uint256 shares);
```
In the case of the Concrete-V2 vaults these conversions are defined as follows:
```latex
assets = Floor [shares * (totalAssets + 1) / (totalSupply + 1)]
shares = Floor [assets * (totalSupply + 1) / (totalAssets + 1)]
```
**NOTE**: It is note-worthy that the totalAsset cached value is updated prior to the calculation. In general each user or operator intervention requires the updating of totalAssets.

### 2.3. Yield Accrual

In order to keep an up-to-date quote of the total Assets, the yield generated by the strategies and the fees (see below) has to be accurately accounted for. To this end there are three internal functions called `_accrueYield()`, `_previewAccrueYieldAndFees()` and `_previewYieldNoFees()`. Before any user or administrative operations the cached value of total Assets is updated by calling the accrue yield internal function. This happens through the modifier `modifier withYieldAccrual()` or by directly calling the external `function accrueYield() external`.

One consequence of this accounting method is the existence of two functions that report totalAssets, namely one that returns the current up-to-date value including yield or loss, which is the `totalAsset()` function that also exists in the ERC4626-standard. The other is the `function cachedTotalAssets() public view returns (uint256)`, which returns merely the state-variable.

Accrual of yield emits several events. First of all each strategy separately emits 
```js
event StrategyYieldAccrued(address indexed strategy, uint256 currentTotalAllocatedValue, uint256 yield, uint256 loss);
```
and then the totality assets lost and gained is tracked in this event
```js 
event YieldAccrued(uint256 totalPositiveYield, uint256 totalNegativeYield);
```
Moreover if fees are accrueing, then fee accrual events will also be emitted.

**IMPORTANT**: The Concrete-V2 vaults are ERC4626-compliant in every point except one, which regards the quote of totalAssets. In case of a broken strategy, where accurate accounting cannot be guaranteed, the value of totalAssets must not reflect a wrong value. Instead totalAssets will revert, which is not compliant to the standard.

### 2.4 Fees

Concrete-V2 comes with the ability to charge fees. By default Concrete charges two types of fees: `management fee` and `performance fee`. 

The management fee is charged per annum. Each time the management fee accrues it is checked how much time has elapsed since the previous accrual and based on a state-variable called `uint16 managementFee` which is given in basis points (100% = 10000) the fee is charged accordingly. The fee is charged by minting shares and thus is socialized across all holders. It also leads to a tiny depreciation of the share value.

The performance fee is charged on each positive yield accrual with respect to that yield. This differs from Concrete-V1, where previously the fee has been charged with respect to the share value. In V2 any time the accrual is called and the net effect of the gains and losses across all strategies is positive, a percentage of `uint16 performanceFee` (in basispoints) from that net-yield is deducted. The fee is then minted in shares. However these shares typically do not depreciate the share value, since they are backed by newly accounted assets from the incoming yield. 

There is no external function that calls the accrual of fees by themselves. It happens in conjunction with the yield accrual, which is at least for the performance fee a pre-requisite for the accrual. The events that are triggered upon successful fee accrual for the management and performance fees are 
```js
event ManagementFeeAccrued(address indexed recipient, uint256 shares, uint256 feeAmount);
event PerformanceFeeAccrued(address indexed recipient, uint256 shares, uint256 feeAmount);
```

There is one fee recipient per fee type. This allows the vault operators to disentangle the fee types. The fee recipient can either be an EOA, an account abstraction or some auxiliary contract that handles the fee processing or splitting. Concrete provides an out-of-the box basic fee-splitter that can divide the fees for up to two parties. It can be found in __src/periphery/auxiliary/TwoWayFeeSplitter.sol__ . If it is set as a fee recipient, the fees will accumulate there and can be distributed on regular intervals. The Two-Way Fee Splitter can also function as a fee splitter for many vaults. It discerns the fees by the token address, which is identical to the vault address for Concrete-v2 ERC4626 vaults.

In summary the fees are handled as follows:

1. Concrete-V2 charges two types of fees by default: management fee and performance fee.
2. All fees are minted as shares to a recipient.
3. Management fees are calculated per annum on every user and operator interaction.
4. Performance Fees are taken directly from the generated yield (major change from previous v1).
5. No hurdle rate and no high water mark even. 
6. Fee calculation is global, not at user level. 

### 2.5. Access Control And Vault Operations

The Concrete-V2 vaults have three different modes of access control and permissions: factory ownership, vault ownership and a role-based access. Every vault has an owner, who may upgrade the vault to another version. This role may be called `upgrade admin`. It uses the Openzeppelin `Ownable` model (or the upgradeable version of it). The current imcumbant can be queried via the `owner()` public function. For the common vault operations there are four roles set aside: 1) Vault Manager 2) Strategy Manager 3) Hook Manager 4) Allocator. The Vault Manager is used for updating state variable. The Strategy Manager can add, remove or halt strategies (see below in [Section 3.1](#31-strategies)). The hook Manager can set and update the hook (See [Section 3.2](#32-hooks)). The Allocator can allocate funds to strategies or deallocate them. They can also set a de-allocation order (see [Section 3.1.2](#312-allocator-fund-movement)).

The role-based access control uses the OpenZeppelin `AccessControlUpgradeable` contracts, where each Role has an admin role. Account with that role can grant and revoke the underlying role from role-holders. By default every role that is defined or not defined has the `DEFAULT_ADMIN_ROLE` as admin role. In Concrete-V2 we do not assign this role. Instead each role, in particular the abovementioned standard roles have their own admin roles: 1) Vault Manager Admin 2) Strategy Admin 3) Hook Manager Admin 4) Allocator Admin. They are initially set to the vault admin, whose address is passed into the contructor args. That means that the vault admin may assign all the above roles. Role definitions are located in `src/lib/Roles.sol`. 

more complex implementations can have additional roles. One of the more common implementation that is used in Concrete-V2 is the AsyncVault Implementation (see [Section 2.6](#26-concrete-vault-implmentations)). It also comes with a WITHDRAWAL MANAGER role and its admin role. 

Here we discuss the main state variables and their access guards:

#### 2.5.1 Vault functions guarded by factory owner

| Function | Event |
|----------|-------|
| `vault.updateManagementFeeRecipient(address recipient)` | `ManagementFeeRecipientUpdated(address managementFeeRecipient)` |
| `vault.updatePerformanceFeeRecipient(address recipient)` | `PerformanceFeeRecipientUpdated(address performanceFeeRecipient)` |

#### 2.5.2 Functions guarded by vault owner

| Function | Event |
|----------|-------|
| `factory.upgrade(address vault, uint64 newVersion, bytes calldata data)` | `Migrated(address indexed vault, uint64 newVersion)` |

#### 2.5.3 Functions guarded by vault manager

| Function | Event |
|----------|-------|
| `vault.setDepositLimits(uint256 minDepositAmount, uint256 maxDepositAmount)` | `DepositLimitsUpdated(uint256 maxDepositAmount, uint256 minDepositAmount)` |
| `vault.setWithdrawLimits(uint256 minWithdrawAmount, uint256 maxWithdrawAmount)` | `WithdrawLimitsUpdated(uint256 maxWithdrawAmount, uint256 minWithdrawAmount)` |
| `vault.updateManagementFee(uint16 managementFee)` | `ManagementFeeUpdated(uint16 managementFee)` |
| `vault.updatePerformanceFee(uint16 performanceFee)` | `PerformanceFeeUpdated(uint16 performanceFee)` |

#### 2.5.4 Functions guarded by strategy manager

| Function | Event |
|----------|-------|
| `vault.addStrategy(address strategy)` | `StrategyAdded(address strategy)` |
| `vault.removeStrategy(address strategy)` | `StrategyRemoved(address strategy)` |
| `vault.toggleStrategyStatus(address strategy)` | `StrategyStatusToggled(address indexed strategy)` |

#### 2.5.5 Functions guarded by hook manager

| Function | Event |
|----------|-------|
| `vault.setHooks(Hooks memory hooks)` | `HooksSet(Hooks hooks)` |

#### 2.5.6 Functions guarded by allocator

| Function | Event |
|----------|-------|
| `vault.allocate(bytes calldata data)` | `YieldAccrued(uint256 totalPositiveYield, uint256 totalNegativeYield)` |
| `vault.setDeallocationOrder(address[] calldata order)` | `DeallocationOrderUpdated()` | 

 
### 2.6. Concrete Vault Implmentations 

Concrete V2 has several implementations (located in `src/implementation/`). Initially there will be two: 
1) an implementation for synchronous, i.e. atomic, handling of deposits and withdrawals. => Standard Implementation (`ConcreteStandardVaultImpl.sol`)
2) an implementation for asynchronous handling of withdrawals, but atomic handling of deposits. => Async Implementation (`ConcreteAsyncVaultImpl.sol`)

#### 2.6.1. Asynchronous Vault Overview

The asynchronous implementation inherits the standard implementation and only overrides the withdrawal feature. It introduces a queue-based withdrawal system that allows for better liquidity management and batch processing of withdrawal requests. This system operates in epochs and provides several key features:

> **📖 Detailed Specification**: For comprehensive technical details, state machine diagrams, and mathematical specifications of the async vault, see [ConcreteAsyncVaultImpl Specification](./spec/ConcreteAsyncVaultImpl.md).

**Queue Toggle Functionality:**
The async vault can toggle the queue on and off, allowing it to operate in two modes:
- **Queue Active**: Withdrawals are queued in epochs and processed asynchronously
- **Queue Inactive**: The vault operates like a standard implementation with atomic withdrawals

This toggle is controlled by the **Vault Manager** role via the `toggleQueueActive()` function.

**Epoch-Based Processing:**
The queue system operates in discrete epochs, where:
- Each epoch has a unique ID that increments sequentially
- New withdrawal requests are automatically queued in the current epoch
- Closing an epoch opens a new one. New incoming requests are then associated to the new epoch.
- Closed epochs can be processed. Which locks a specific share price and makes the funds available for withdrawal.
- An epoch cannot be closed when the previous one hasn't been processed yet. 
- Requests can be claimed individually or in batch for epochs that have been processed.

The life cycle of an epoch is as follows:
Inactive => Active => Processing => Processed.

An epoch is inactive if it is bigger than the current epoch id. 

An epoch is active when its epoch id coincides with the current epoch id. 

An epoch is processing when it has been closed but not processed. Its epoch id is one less than the current one. 

An epoch is processed when it has been closed and processed. Its epoch id is at least one less than the current one.

**Request Lifecycle:**

1) **Request Creation**: Users submit withdrawal requests through the standard `withdraw()` or `redeem()` functions. These requests are automatically queued in the current epoch.

2) **Request Cancellation**: Users can cancel their pending withdrawal requests, but only for epochs that haven't been processed yet. Cancellation is performed by the **Allocator** role via `cancelRequest(address user, uint256 epochID)`.

3) **Epoch Processing**: Epochs are processed by the **Allocator** role via `processEpoch()`. During processing:
   - The current share price is calculated and locked for that epoch
   - Required assets are reserved for the epoch's total withdrawal requests
   - The epoch is marked as processed and ready for claims

4) **Request Rollover**: If needed, individual user requests can be moved to the next epoch by the **Allocator** role via `moveRequestToNextEpoch(address user)`.

**Querying Capabilities:**
The async vault provides extensive querying functions for monitoring the queue system:
- `latestEpochID()`: Get the current epoch ID
- `getUserEpochRequest(address user, uint256 epochID)`: Get a user's request for a specific epoch
- `getUserEpochRequestInAssets(address user, uint256 epochID)`: Get claimable assets for a user's request
- `totalRequestedSharesPerEpoch(uint256 epochID)`: Get total shares requested in an epoch
- `getEpochPricePerShare(uint256 epoch)`: Get the locked share price for a processed epoch
- `pastEpochsUnlcaimedAssets()`: Get total assets reserved for past epoch claims
- `isQueueActive()`: Check if the queue is currently active

**Batched Withdrawals:**
Withdrawals are processed in batches for efficiency:
- **Individual Claims**: Users can claim their processed withdrawals via `claimWithdrawal(uint256[] calldata epochIDs)`
- **Batch Claims**: The **Allocator** role can process claims for multiple users in batch via `claimUsersBatch(address[] calldata users, uint256 epochID)`

This batched approach allows for gas-efficient processing of multiple withdrawal claims while maintaining the security and accounting integrity of the vault. 

#### 2.6.2 Access Control and Events

The async vault implementation adds several additional functions that require specific roles. There is also a specific role called the `WITHDRAWAL_MANAGER` which can trigger various functions. Below are the guarded functions organized by role:

**Functions guarded by VAULT_MANAGER:**

| Function | Event |
|----------|-------|
| `asyncVault.toggleQueueActive()` | `QueueActiveToggled(bool isQueueActive)` |

**Functions guarded by WITHDRAWAL MANAGER:**

| Function | Event |
|----------|-------|
| `asyncVault.cancelRequest(address user, uint256 epochID)` | `RequestCancelled(address indexed owner, uint256 shares, uint256 epoch)` |
| `asyncVault.processEpoch()` | `EpochProcessed(uint256 epoch, uint256 shares, uint256 assets, uint256 sharePrice)` |
| `asyncVault.claimWithdrawal(address user, uint256[] calldata epochIDs)` | `RequestClaimed(address indexed owner, uint256 assets)` |
| `asyncVault.claimUsersBatch(address[] calldata users, uint256 epochID)` | `RequestClaimed(address indexed owner, uint256 assets)` |
| `asyncVault.moveRequestToNextEpoch(address user)` | `RequestMovedToNextEpoch(address indexed user, uint256 shares, uint256 currentEpoch, uint256 nextEpochID)` |

**Public Functions (No Access Control Required):**

The following async vault functions are publicly accessible and do not require specific roles:

| Function | Event |
|----------|-------|
| `asyncVault.withdraw(uint256 assets, address receiver, address owner)` | `QueuedWithdrawal(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares, uint256 epochID)` |
| `asyncVault.redeem(uint256 shares, address receiver, address owner)` | `QueuedWithdrawal(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares, uint256 epochID)` |

**Initialization Event:**

| Function | Event |
|----------|-------|
| Vault initialization | `WithdrawalQueueInitialized(uint256 epochID)` |

#### 2.6.3 Async Vault Initialization

The async vault uses the same initialization arguments as the standard vault implementation since it inherits from `ConcreteStandardVaultImpl`. The initialization data must be ABI-encoded and passed to the factory's `create()` function:

**Required Initialization Arguments:**
```js
abi.encode(
    address allocateModuleAddr,    // Address of the allocation module
    address asset,                 // Address of the underlying asset token
    address initialVaultManager,   // Initial vault manager address
    string memory name,           // ERC20 token name for vault shares
    string memory symbol          // ERC20 token symbol for vault shares
)
```

**Initialization Process:**
1. The async vault inherits the standard vault initialization
2. After standard initialization, it calls `__ConcreteAsyncVaultImpl_init()`
3. This sets up the withdrawal queue with:
   - Initial epoch ID set to 1
   - Queue active state set to true
   - Emits `WithdrawalQueueInitialized(1)` event

**Factory Deployment:**
```js
factory.create(
    uint64 version,           // Async vault implementation version
    address ownerAddr,        // Vault owner address
    bytes calldata data,      // ABI-encoded initialization arguments
    bytes32 salt             // Optional salt for deterministic addresses
)
```

## 3. Peripheral Contracts

The Concrete V2 protocol includes several peripheral contracts (located in `src/periphery/`) that extend the core vault functionality. These contracts provide additional features such as strategy management, hooks for custom logic, and fee distribution mechanisms.

### 3.1. Strategies

Strategies are external contracts that implement the `IStrategyTemplate` interface and handle fund allocation to different yield-generating protocols or investment opportunities. Each strategy is bound to a single vault and manages that vault's funds in specific protocols.

**Strategy Architecture:**
- **Storage Layout**: Implements EIP-7201 storage layout pattern for upgradeable contracts
- **Proxy Pattern**: Uses transparent proxy pattern for upgradeability
- **Base Implementation**: All strategies inherit from `BaseStrategy` (`src/periphery/strategies/BaseStrategy.sol`) which provides common functionality
- **Location**: Strategy implementations are located in `src/periphery/strategies/` directory

#### 3.1.1. Base Strategy Interface

All strategies must implement the `IStrategyTemplate` interface, which defines the core functionality required for strategy contracts:

**Required Functions** (defined in `src/interface/IStrategyTemplate.sol`):
```js
function allocateFunds(bytes calldata data) external returns (uint256)
function deallocateFunds(bytes calldata data) external returns (uint256)
function withdraw(uint256 amount) external returns (uint256)
function totalAssets() external view returns (uint256)
function asset() external view returns (address)
function strategyType() external view returns (StrategyType)
```

**Strategy Types:**
- `ATOMIC`: Strategy that executes operations atomically, provides on-chain accurate accounting of yield
- `ASYNC`: Strategy that requires asynchronous operations (multiple transactions), can provide stale accounting of yield
- `CROSSCHAIN`: Strategy that operates across different blockchain networks, can provide stale accounting of yield

**Key Requirements:**
- Must emit `AllocateFunds` event when funds are allocated
- Must emit `DeallocateFunds` event when funds are deallocated
- Must revert if operations cannot be completed (slippage, limits, etc.)
- Must implement proper access controls to ensure only authorized vaults can call functions
- Must use the same underlying asset as the vault

#### 3.1.2. Allocator Fund Movement

The Allocator role manages fund allocation and deallocation through the `AllocateModule` (`src/module/AllocateModule.sol`). The process works as follows:

**Allocation Process:**
1. The Allocator calls `vault.allocate(bytes calldata data)` with ABI-encoded `AllocateParams[]`
2. The vault delegates to the `AllocateModule.allocateFunds()` function
3. For each allocation parameter:
   - If `isDeposit` is true: calls `strategy.allocateFunds(extraData)`
   - If `isDeposit` is false: calls `strategy.deallocateFunds(extraData)`
4. Updates the vault's internal accounting of allocated amounts
5. Emits `AllocatedFunds` event for each operation

**AllocateParams Structure** (defined in `src/interface/IAllocateModule.sol`):
```js
struct AllocateParams {
    address strategy;        // Strategy contract address
    bool isDeposit;         // true for allocation, false for deallocation
    bytes extraData;        // Strategy-specific parameters
}
```

**Access Control:**
- Only accounts with the `ALLOCATOR` role can call allocation functions
- Only active strategies can receive new allocations
- The vault automatically handles token approvals and accounting updates

#### 3.1.3. Multisig Strategies

The `MultisigStrategy` (`src/periphery/strategies/MultisigStrategy.sol`) is a specialized strategy implementation that forwards assets to a designated multi-signature wallet. This strategy is useful for:

**Key Features:**
- **Asset Forwarding**: Simply forwards deposits to a multi-sig wallet
- **Asset Retrieval**: Retrieves assets from the multi-sig on withdrawal
- **No Yield Generation**: Does not generate any rewards, purely for custody
- **Position Accounting**: Implements position accounting with configurable thresholds

**Initialization Parameters:**
```js
function initialize(
    address admin,                           // Strategy admin
    address vault_,                         // Authorized vault
    address multiSig_,                      // Multi-sig wallet address
    uint64 maxAccountingChangeThreshold_,   // Max accounting change (basis points)
    uint64 accountingValidityPeriod_,       // Accounting validity period (seconds)
    uint64 cooldownPeriod_                  // Update cooldown period (seconds)
)
```

**Access Control:**
- `STRATEGY_ADMIN`: Can set the multi-sig address and update accounting parameters
- `OPERATOR_ROLE`: Can execute allocation and deallocation operations
- Only the authorized vault can call strategy functions

**Events:**
- `MultiSigSet`: Emitted when the multi-sig address is updated
- `AssetsForwarded`: Emitted when assets are sent to the multi-sig
- `AssetsRetrieved`: Emitted when assets are retrieved from the multi-sig
- `AdjustTotalAssets`: Emitted when total assets are adjusted

### 3.2. Hooks

Hooks provide a mechanism for custom logic to be executed at specific points during vault operations. The hook system uses a struct containing an address and flags to determine which hooks are active. Hook interface and library are located in `src/interface/IHook.sol` and `src/lib/Hooks.sol`.

**Hooks Structure:**
```js
struct Hooks {
    address target;  // Address of the hook contract
    uint96 flags;    // Bit flags indicating which hooks are active
}
```

**Available Hook Types:**
- `PRE_DEPOSIT` (1): Called before deposit operations
- `POST_DEPOSIT` (2): Called after deposit operations
- `PRE_MINT` (3): Called before mint operations
- `POST_MINT` (4): Called after mint operations
- `PRE_WITHDRAW` (5): Called before withdraw operations
- `POST_WITHDRAW` (6): Called after withdraw operations
- `PRE_REDEEM` (7): Called before redeem operations
- `POST_REDEEM` (8): Called after redeem operations
- `PRE_ADD_STRATEGY` (9): Called before adding strategies
- `PRE_REMOVE_STRATEGY` (10): Called before removing strategies

**Hook Interface:**
Hook contracts must implement the `IHook` interface (`src/interface/IHook.sol`) with functions for each hook type:
```js
function preDeposit(address sender, uint256 assets, address receiver, uint256 totalAssets) external;
function postDeposit(address sender, uint256 assets, uint256 shares, address receiver, uint256 totalAssets) external;
// ... other hook functions
```

**Access Control:**
- Only accounts with the `HOOK_MANAGER` role can set hooks via `vault.setHooks(Hooks memory hooks)`

### 3.3. Fee Splitter

The `TwoWayFeeSplitter` (`src/periphery/auxiliary/TwoWayFeeSplitter.sol`) is the primary fee distribution mechanism in Concrete V2. It allows fees to be split between two recipients with configurable ratios.

**Key Features:**
- **Two Recipients**: Main recipient (curator) and secondary recipient (service provider)
- **Configurable Split**: Fee fraction determines the distribution ratio
- **Automatic Distribution**: Fees are automatically distributed when `distributeFees()` is called
- **Multi-Vault Support**: Can handle fees from multiple vaults simultaneously

**Recipients:**
- **Main Recipient**: Typically the vault curator who manages the vault
- **Secondary Recipient**: Typically Concrete (the service provider)

**Fee Distribution Logic:**
```js
// If feeFractionOfSecondaryRecipient = 0: All fees go to main recipient
// If feeFractionOfSecondaryRecipient = 10000 (100%): All fees go to secondary recipient
// Otherwise: Fees are split proportionally
```

**Access Control:**
- **Fee Splitter Owner**: Can set secondary recipient and fee fractions
- **Vault Manager**: Can set main recipient for their vault
- **Anyone**: Can call `distributeFees()` to trigger distribution

**Key Functions:**
```js
function distributeFees(address vault) external                    // Distribute accumulated fees
function setMainRecipient(address vault, address newMainRecipient) external
function setSecondaryRecipient(address vault, address secondaryRecipient) external
function setFeeFraction(address vault, uint32 newFeeFractionOfSecondaryRecipient) external
```

**Events:**
- `FeesDistributed`: Emitted when fees are distributed to recipients
- `MainRecipientSet`: Emitted when main recipient is updated
- `SecondaryRecipientSet`: Emitted when secondary recipient is updated
- `FeeFractionSet`: Emitted when fee fraction is updated