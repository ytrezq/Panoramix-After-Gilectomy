// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUpgradeableVault} from "./IUpgradeableVault.sol";
import {Hooks} from "./IHook.sol";
import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";
import {IAccessControlEnumerable} from "@openzeppelin-contracts/access/extensions/IAccessControlEnumerable.sol";

/**
 * @title IConcreteStandardVaultImpl
 * @dev Interface for the standard vault implementation that manages multiple investment strategies.
 * @dev This interface extends the base tokenized vault functionality with strategy management capabilities.
 * @dev Strategies are external contracts that implement the IStrategyTemplate interface and handle
 * fund allocation to different yield-generating protocols or investment opportunities.
 */
interface IConcreteStandardVaultImpl is IUpgradeableVault, IERC4626, IAccessControlEnumerable {
    /**
     * @dev Thrown when attempting to withdraw to the zero address.
     */
    error InvalidReceiver();

    /**
     * @dev Thrown when attempting to add a strategy that uses a different asset than the vault.
     */
    error InvalidStrategyAsset();

    /**
     * @dev Thrown when attempting to add a strategy that has already been added to the vault.
     */
    error StrategyAlreadyAdded();

    /**
     * @dev Thrown when attempting to operate on a strategy that doesn't exist in the vault.
     */
    error StrategyDoesNotExist();

    /**
     * @dev Thrown when attempting to interact with a strategy that is halted.
     */
    error StrategyIsHalted();

    /**
     * @dev Thrown when attempting to halt a strategy that is already halted.
     */
    error StrategyAlreadyHalted();

    /**
     * @dev Thrown when attempting to toggle the status of an inactive strategy.
     */
    error CannotToggleInactiveStrategy();

    /**
     * @dev Thrown when attempting to set a management fee without setting a recipient first.
     */
    error FeeRecipientNotSet();

    /**
     * @dev Thrown when attempting to set a management fee that exceeds the maximum allowed.
     */
    error ManagementFeeExceedsMaximum();

    /**
     * @dev Thrown when attempting to set a performance fee that exceeds the maximum allowed.
     */
    error PerformanceFeeExceedsMaximum();

    /**
     * @dev Thrown when attempting to set an invalid fee recipient address (address(0)).
     */
    error InvalidFeeRecipient();

    /**
     * @dev Thrown when the allocate module is invalid.
     */
    error InvalidAllocateModule();

    /**
     * @dev Thrown when the asset is invalid.
     */
    error InvalidAsset();

    /**
     * @dev Thrown when the initial vault manager is invalid.
     */
    error InvalidInitialVaultManager();

    /**
     * @dev Thrown when the name is invalid.
     */
    error InvalidName();

    /**
     * @dev Thrown when the symbol is invalid.
     */
    error InvalidSymbol();

    /**
     * @dev Thrown when the deposit limits are invalid.
     */
    error InvalidDepositLimits();

    /**
     * @dev Thrown when the withdraw limits are invalid.
     */
    error InvalidWithdrawLimits();

    /**
     * @dev Thrown when the asset amount is out of bounds.
     */
    error AssetAmountOutOfBounds(address sender, uint256 assets, uint256 minDepositAmount, uint256 maxDepositAmount);

    /**
     * @dev Thrown when attempting to remove a strategy that has allocation or is in the deallocation order.
     */
    error StrategyHasAllocation();

    /**
     * @dev Thrown when the vault has insufficient balance to process the epoch.
     */
    error InsufficientBalance();

    /**
     * @dev Thrown when calculated shares are zero.
     */
    error InsufficientShares();

    /**
     * @dev Thrown when calculated assets are zero.
     */
    error InsufficientAssets();

    /**
     * @dev Emitted when a new strategy is successfully added to the vault.
     * @param strategy The address of the strategy contract that was added.
     */
    event StrategyAdded(address strategy);

    /**
     * @dev Emitted when a strategy is successfully removed from the vault.
     * @param strategy The address of the strategy contract that was removed.
     */
    event StrategyRemoved(address strategy);

    /**
     * @dev Emitted when a strategy is set to Halted status.
     * @param strategy The address of the strategy contract that was halted.
     */
    event StrategyHalted(address strategy);

    /**
     * @dev Emitted when a strategy's status is toggled between Active and Halted.
     * @param strategy The address of the strategy contract whose status was toggled.
     */
    event StrategyStatusToggled(address indexed strategy);

    /**
     * @dev Emitted when the yield accrual operation is completed across all strategies.
     *
     * @param totalPositiveYield The total amount of positive yield generated across all strategies.
     * @param totalNegativeYield The total amount of losses incurred across all strategies.
     */
    event YieldAccrued(uint256 totalPositiveYield, uint256 totalNegativeYield);

    /**
     * @dev Emitted when management fee is accrued.
     * @param recipient The address that received the management fee shares.
     * @param shares The number of shares minted as management fee.
     * @param feeAmount The asset value of the management fee.
     */
    event ManagementFeeAccrued(address indexed recipient, uint256 shares, uint256 feeAmount);

    /**
     * @dev Emitted when performance fee is accrued.
     * @param recipient The address that received the performance fee shares.
     * @param shares The number of shares minted as performance fee.
     * @param feeAmount The asset value of the performance fee.
     */
    event PerformanceFeeAccrued(address indexed recipient, uint256 shares, uint256 feeAmount);

    /**
     * @dev Emitted when management fee is updated.
     * @param managementFee The new management fee rate in basis points.
     */
    event ManagementFeeUpdated(uint16 managementFee);

    /**
     * @dev Emitted when management fee recipient is updated.
     * @param managementFeeRecipient The new management fee recipient address.
     */
    event ManagementFeeRecipientUpdated(address managementFeeRecipient);

    /**
     * @dev Emitted when performance fee is updated.
     * @param performanceFee The new performance fee rate in basis points.
     */
    event PerformanceFeeUpdated(uint16 performanceFee);

    /**
     * @dev Emitted when performance fee recipient is updated.
     * @param performanceFeeRecipient The new performance fee recipient address.
     */
    event PerformanceFeeRecipientUpdated(address performanceFeeRecipient);

    /**
     * @dev Emitted when deposit limits are updated.
     * @param maxDepositAmount The new maximum deposit amount.
     * @param minDepositAmount The new minimum deposit amount.
     */
    event DepositLimitsUpdated(uint256 maxDepositAmount, uint256 minDepositAmount);

    /**
     * @dev Emitted when withdraw limits are updated.
     * @param maxWithdrawAmount The new maximum withdraw amount.
     * @param minWithdrawAmount The new minimum withdraw amount.
     */
    event WithdrawLimitsUpdated(uint256 maxWithdrawAmount, uint256 minWithdrawAmount);

    /**
     * @dev Emitted when the deallocation order is updated.
     */
    event DeallocationOrderUpdated();

    /**
     * @dev Emitted when an individual strategy's yield is accrued.
     *
     * @param strategy The address of the strategy contract whose yield was accrued.
     * @param currentTotalAllocatedValue The current total allocated value reported by the strategy.
     * @param yield The amount of positive yield generated by this strategy since last accrual.
     * @param loss The amount of loss incurred by this strategy since last accrual.
     */
    event StrategyYieldAccrued(
        address indexed strategy, uint256 currentTotalAllocatedValue, uint256 yield, uint256 loss
    );

    /**
     * @dev Enumeration of possible strategy statuses within the vault.
     * @dev Inactive: Strategy is inactive and cannot receive new allocations.
     * @dev Active: Strategy is active and can receive allocations and process withdrawals normally.
     * @dev Halted: Strategy is halted, typically due to detected issues or failures.
     * In this state, the strategy can be removed even if it has allocated funds
     */
    enum StrategyStatus {
        Inactive,
        Active,
        Halted
    }

    /**
     * @dev Structure containing metadata and state information for each strategy.
     * @dev status: Current operational status of the strategy.
     * @dev allocated: Total amount of vault assets currently allocated to this strategy, denominated in the vault's underlying asset token.
     */
    struct StrategyData {
        StrategyStatus status;
        uint120 allocated;
    }

    /**
     * @dev Adds a new strategy to the vault.
     * @dev The strategy must implement the IStrategyTemplate interface and use the same underlying asset as the vault.
     * @dev Only callable by accounts with the STRATEGY_MANAGER role.
     *
     * @param strategy The address of the strategy contract to add.
     *
     * Requirements:
     * - The strategy's asset() must match the vault's asset()
     * - The strategy must not already be added to the vault
     * - Caller must have STRATEGY_MANAGER role
     *
     * Emits:
     * - StrategyAdded event
     *
     * Reverts:
     * - InvalidStrategyAsset if strategy uses different asset
     * - StrategyAlreadyAdded if strategy is already in the vault
     */
    function addStrategy(address strategy) external;

    /**
     * @dev Removes a strategy from the vault.
     * @dev The strategy can only be removed if it has no allocated funds, unless it's in Halted status.
     * @dev Only callable by accounts with the STRATEGY_MANAGER role.
     *
     * @param strategy The address of the strategy contract to remove.
     *
     * Requirements:
     * - Strategy must exist in the vault
     * - Strategy must have zero allocated funds OR be in Halted status
     * - Caller must have STRATEGY_MANAGER role
     *
     * Emits:
     * - StrategyRemoved event
     *
     * Reverts:
     * - StrategyDoesNotExist if strategy is not in the vault
     * - Custom revert if strategy has allocated funds and is not in Halted status
     */
    function removeStrategy(address strategy) external;

    /**
     * @dev Toggles a strategy's status between Active and Halted.
     * @dev This is a safety mechanism to isolate problematic strategies or reactivate previously halted ones.
     * @dev Active strategies can receive allocations and participate in yield accrual and withdrawal operations.
     * @dev Halted strategies are skipped during yield accrual and withdrawal operations.
     * @dev Only callable by accounts with the STRATEGY_MANAGER role.
     *
     * @param strategy The address of the strategy contract to toggle.
     *
     * Requirements:
     * - Strategy must exist in the vault
     * - Strategy must be either Active or Halted (cannot toggle Inactive strategies)
     * - Caller must have STRATEGY_MANAGER role
     *
     * Emits:
     * - StrategyStatusToggled event
     *
     * Reverts:
     * - StrategyDoesNotExist if strategy is not in the vault
     */
    function toggleStrategyStatus(address strategy) external;

    /**
     * @notice Executes fund allocation and deallocation operations across multiple strategies.
     * @dev This function performs a yield accrual operation first to update vault accounting,
     *      then executes the allocation operations specified in the data parameter.
     * @dev All operations are performed via delegatecall to the respective modules to maintain
     *      proper storage context and access control.
     * @param data ABI-encoded array of AllocateParams structures containing the allocation
     *             operations to execute. Each param specifies whether to allocate or deallocate
     *             funds, which strategy to use, and any additional data required by the strategy.
     * @dev Only callable by accounts with the ALLOCATOR role.
     * @dev The function automatically triggers yield accrual before allocation to ensure
     *         accurate vault accounting prior to fund movements.
     */
    function allocate(bytes calldata data) external;

    /**
     * @notice Accrues yield and accounts for losses across all active strategies in the vault.
     * @dev This function updates the vault's internal accounting by querying the current
     *      value of all strategy allocations and calculating net yield or losses.
     * @dev This function can be called by anyone to update the vault's accounting.
     * @dev The yield accrual operation does not trigger actual fund movements, it only
     *         updates the vault's internal state to reflect current strategy values.
     */
    function accrueYield() external;

    /**
     * @notice Updates the management fee for the vault.
     * @param managementFee The new management fee in basis points.
     * @dev Only callable by accounts with VAULT_MANAGER role.
     * @dev Fee must be <= MAX_MANAGEMENT_FEE.
     * @dev If fee > 0, recipient must be set.
     */
    function updateManagementFee(uint16 managementFee) external;

    /**
     * @notice Updates the management fee recipient for the vault.
     * @param recipient The new management fee recipient address.
     * @dev Only callable by accounts with VAULT_MANAGER role.
     * @dev Recipient cannot be address(0).
     */
    function updateManagementFeeRecipient(address recipient) external;

    /**
     * @notice Updates the performance fee for the vault.
     * @param performanceFee The new performance fee in basis points.
     * @dev Only callable by accounts with VAULT_MANAGER role.
     * @dev Fee must be <= MAX_PERFORMANCE_FEE.
     * @dev If fee > 0, recipient must be set.
     */
    function updatePerformanceFee(uint16 performanceFee) external;

    /**
     * @notice Updates the performance fee recipient for the vault.
     * @param recipient The new performance fee recipient address.
     * @dev Only callable by accounts with VAULT_MANAGER.
     * @dev Recipient cannot be address(0).
     */
    function updatePerformanceFeeRecipient(address recipient) external;

    /**
     * @notice Returns the current fee configuration for the vault.
     * @return currentManagementFee The current management fee in basis points.
     * @return currentManagementFeeRecipient The current management fee recipient address.
     * @return currentLastManagementFeeAccrual The timestamp of the last management fee accrual.
     * @return currentPerformanceFee The current performance fee in basis points.
     * @return currentPerformanceFeeRecipient The current performance fee recipient address.
     */
    function getFeeConfig()
        external
        view
        returns (
            uint16 currentManagementFee,
            address currentManagementFeeRecipient,
            uint32 currentLastManagementFeeAccrual,
            uint16 currentPerformanceFee,
            address currentPerformanceFeeRecipient
        );

    /**
     * @notice Sets the hooks for the vault.
     * @dev This function sets the hooks for the vault.
     * @dev Only callable by accounts with the HOOK_MANAGER role.
     * @param hooks The hooks to set.
     */
    function setHooks(Hooks memory hooks) external;

    /**
     * @notice Previews the total assets that would be available after accruing yield from all strategies.
     * @dev This function simulates the yield accrual operation without actually executing it,
     *      providing a view of what the vault's total assets would be after accounting
     *      for yield and losses across all active strategies.
     * @dev The calculation includes the current lastTotalAssets plus any positive
     *      yield minus any losses that would be realized during yield accrual.
     * @dev This is a view function that does not modify state or trigger any actual
     *      fund movements or strategy interactions.
     *
     * @return The total amount of assets that would be available in the vault after yield accrual,
     *         denominated in the vault's underlying asset token.
     * @return The total amount of shares that would be available in the vault after yield accrual,
     *         calculated as current totalSupply + management fee shares.
     */
    function previewAccrueYield() external view returns (uint256, uint256);

    /**
     * @dev Retrieves the current data and status information for a specific strategy.
     * @dev This function provides read-only access to strategy metadata including allocation amounts and status.
     *
     * @param strategy The address of the strategy contract to query.
     * @return The StrategyData struct containing the strategy's current status and allocated amount.
     *
     * Note:
     * - Returns default values (Inactive status, 0 allocated) for non-existent strategies
     * - Does not revert for invalid strategy addresses
     */
    function getStrategyData(address strategy) external view returns (StrategyData memory);

    /**
     * @dev Returns an array of all strategy addresses currently managed by the vault.
     * @dev This function provides a way to enumerate all active strategies for external integrations and monitoring.
     *
     * @return An array containing the addresses of all strategies added to the vault.
     *
     * Note:
     * - The returned array includes strategies in all statuses (Active, Inactive, Emergency)
     * - The order of strategies in the array is not guaranteed
     * - Returns an empty array if no strategies have been added
     */
    function getStrategies() external view returns (address[] memory);

    /**
     * @dev Returns the address of the allocate module.
     *
     * @return The address of the allocate module.
     */
    function allocateModule() external view returns (address);

    /**
     * @dev Returns the management fee configuration.
     * @return managementFeeRecipient The address that receives management fees.
     * @return managementFeeRate The management fee rate in basis points (where 10,000 = 100%).
     * @return lastAccrualTime The timestamp of the last management fee accrual.
     */
    function managementFee()
        external
        view
        returns (address managementFeeRecipient, uint16 managementFeeRate, uint32 lastAccrualTime);

    /**
     * @dev Sets the deposit limits.
     * @param maxDepositAmount The maximum deposit amount.
     * @param minDepositAmount The minimum deposit amount.
     * @dev Only callable by accounts with VAULT_MANAGER role.
     */
    function setDepositLimits(uint256 maxDepositAmount, uint256 minDepositAmount) external;

    /**
     * @dev Sets the withdraw limits.
     * @param maxWithdrawAmount The maximum withdraw amount.
     * @param minWithdrawAmount The minimum withdraw amount.
     * @dev Only callable by accounts with VAULT_MANAGER role.
     */
    function setWithdrawLimits(uint256 maxWithdrawAmount, uint256 minWithdrawAmount) external;

    /**
     * @dev Returns the deposit limits.
     * @return maxDepositAmount The maximum deposit amount.
     * @return minDepositAmount The minimum deposit amount.
     */
    function getDepositLimits() external view returns (uint256 maxDepositAmount, uint256 minDepositAmount);

    /**
     * @dev Returns the withdraw limits.
     * @return maxWithdrawAmount The maximum withdraw amount.
     * @return minWithdrawAmount The minimum withdraw amount.
     */
    function getWithdrawLimits() external view returns (uint256 maxWithdrawAmount, uint256 minWithdrawAmount);

    /**
     * @dev Returns the performance fee configuration.
     * @return performanceFeeRecipient The address that receives performance fees.
     * @return performanceFeeRate The performance fee rate in basis points (where 10,000 = 100%).
     */
    function performanceFee() external view returns (address performanceFeeRecipient, uint16 performanceFeeRate);

    /**
     * @dev Returns the total amount of assets allocated to all strategies.
     *
     * @return The total amount of assets allocated to all strategies.
     */
    function getTotalAllocated() external view returns (uint256);

    /**
     * @dev Returns the cached value of total assets after the last call.
     *
     * @return The cached value of total assets after the last call.
     */
    function cachedTotalAssets() external view returns (uint256);

    /**
     * @dev Returns the deallocation order from strategies.
     *
     * @return order An array of strategy addresses in the order they should be deallocated.
     */
    function getDeallocationOrder() external view returns (address[] memory order);

    /**
     * @dev Sets the deallocation order for strategies.
     * @dev Only callable by accounts with the ALLOCATOR role.
     * @param order An array of strategy addresses in the order they should be deallocated.
     */
    function setDeallocationOrder(address[] calldata order) external;
}
