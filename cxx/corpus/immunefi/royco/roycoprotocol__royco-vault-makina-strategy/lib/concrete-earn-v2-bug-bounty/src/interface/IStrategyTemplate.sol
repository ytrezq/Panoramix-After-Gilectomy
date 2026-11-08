// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title IStrategyTemplate
 * @dev Interface that all strategy implementations must follow to be compatible with the vault system.
 * @dev Each strategy is bound to a single vault and manages that vault's funds in different protocols or investment opportunities.
 * @dev The Vault uses this interface to deploy, withdraw, and rebalance funds across multiple strategies.
 *
 * @notice This interface defines the core functionality required for strategy contracts:
 * - Asset management (allocation and deallocation of funds)
 * - Withdrawal capabilities for user redemptions
 * - Limit reporting for rebalancing operations
 * - Compatibility with the vault's underlying asset token
 *
 * @notice All strategies must implement proper access controls and ensure only authorized callers
 * (typically the vault) can execute fund management operations.
 *
 * @notice For strategies that accrue rewards from underlying protocols:
 * The vault has an arbitrary call execution function that can call any target with arbitrary data.
 * This is primarily used to claim rewards from external reward systems. Strategies that earn rewards
 * should provide dedicated functions that can be called by the vault through this mechanism to claim
 * rewards and forward them to the rewards distributor system.
 */

/**
 * @dev Enum representing different types of strategies
 */
enum StrategyType {
    ATOMIC, // 0: Strategy that executes operations atomically, provides on-chain accurate accounting of yield
    ASYNC, // 1: Strategy that requires asynchronous operations (multiple transactions), can provide stale (within defined latency) accounting of yield
    CROSSCHAIN // 2: Strategy that operates across different blockchain networks, can provide stale (within defined latency) accounting of yield
}

interface IStrategyTemplate {
    /**
     * @dev Allocates funds from the vault to the underlying protocol.
     * @dev This function will be called when the vault wants to deploy assets into the yield-generating protocol.
     *
     * @param data Arbitrary calldata that can be used to pass strategy-specific parameters for the allocation.
     *             This allows for flexible configuration of the allocation process (e.g., slippage tolerance,
     *             specific protocol parameters, routing information, etc.).
     *
     * - MUST emit the AllocateFunds event.
     * - MUST revert if all of assets cannot be deposited (due to allocation limit being reached, slippage, the protocol
     *   not being able to accept more funds, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault's underlying asset token.
     */
    function allocateFunds(bytes calldata data) external returns (uint256);

    /**
     * @dev Deallocates funds from the underlying protocol back to the vault.
     * @dev This function will be called when the vault wants to withdraw assets from the yield-generating protocol.
     *
     * @param data Arbitrary calldata that can be used to pass strategy-specific parameters for the deallocation.
     *             This allows for flexible configuration of the withdrawal process (e.g., slippage tolerance,
     *             specific protocol parameters, withdrawal routing, etc.).
     *
     * - MUST emit the DeallocateFunds event.
     * - MUST revert if all of assets cannot be withdrawn (due to withdrawal limit being reached, slippage, the protocol
     *   not having enough liquidity, etc).
     */
    function deallocateFunds(bytes calldata data) external returns (uint256);

    /**
     * @dev Sends assets of underlying tokens to sender.
     * @dev This function will be called when the vault unwinds its position while depositor withdraws.
     *
     * - MUST emit the Withdraw event.
     * - MUST revert if all of assets cannot be withdrawn (due to withdrawal limit being reached, slippage, the owner
     *   not having enough assets, etc).
     */
    function onWithdraw(uint256 assets) external returns (uint256);

    /**
     * @dev Rescue function to withdraw tokens that may have been accidentally sent to the strategy.
     * @dev This function allows authorized users to rescue tokens that are not part of the strategy's normal operations.
     *
     * @param token The address of the token to rescue.
     * @param amount The amount of tokens to rescue. Use 0 to rescue all available tokens.
     *
     * - MUST only allow rescue of tokens that are not the strategy's primary asset (asset()).
     * - MUST emit appropriate events for the rescue operation.
     * - MUST revert if the caller is not authorized to perform token rescue.
     * - MUST revert if attempting to rescue the strategy's primary asset token.
     */
    function rescueToken(address token, uint256 amount) external;

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function asset() external view returns (address);

    /**
     * @dev Returns the address of the vault that this strategy is bound to.
     *
     * - MUST return the vault address that was set during strategy initialization.
     * - MUST NOT revert.
     */
    function getVault() external view returns (address);

    /**
     * @dev Returns the type of strategy implementation.
     * @dev This function indicates the operational characteristics of the strategy.
     *
     * @return The strategy type as defined in the StrategyType enum.
     *
     * - MUST return one of the defined StrategyType values.
     * - MUST NOT revert.
     * - ATOMIC: Strategy executes operations atomically in the same transaction, yield MUST be always atomicly updated in strategy allocated amount.
     * - ASYNC: Strategy requires asynchronous operations across multiple transactions, yield Can be updated asynchronously within documented latency.
     * - CROSSCHAIN: Strategy operates across different blockchain networks, yield Can be updated asynchronously within documented latency.
     */
    function strategyType() external view returns (StrategyType);

    /**
     * @dev Returns the total value of assets that the bound vault has allocated in the strategy.
     * @dev This function is mainly used during yield accrual operations to account for strategy yield or losses.
     *
     * @return The total value of allocated assets denominated in the asset() token.
     *
     * - MUST return the total value of assets that the bound vault has allocated to this strategy.
     * - MUST account for any losses or depreciation in the underlying protocol.
     * - MUST NOT revert.
     * - MUST return 0 if the vault has no funds allocated to this strategy.
     */
    function totalAllocatedValue() external view returns (uint256);

    /**
     * @dev Returns the maximum amount of assets that can be allocated to the underlying protocol.
     * @dev This function is primarily used by the Allocator to determine allocation limits when rebalancing funds.
     *
     * - MUST return the maximum amount of underlying assets that can be allocated in a single call to allocateFunds.
     * - MUST NOT revert.
     * - MAY return 0 if the protocol cannot accept any more funds.
     * - MAY return type(uint256).max if there is no practical limit.
     */
    function maxAllocation() external view returns (uint256);

    /**
     * @dev Returns the maximum amount of assets that can be withdrawn from the strategy by the vault.
     * @dev This function is primarily used by the vault to determine withdrawal limits when covering user redemptions.
     *
     * - MUST return the maximum amount of underlying assets that can be withdrawn in a single call to onWithdraw.
     * - MUST NOT revert.
     * - MAY return 0 if no funds are available for withdrawal.
     * - SHOULD reflect current liquidity constraints and strategy-specific withdrawal limits.
     */
    function maxWithdraw() external view returns (uint256);
}
