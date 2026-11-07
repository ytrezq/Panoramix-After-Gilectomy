// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title IAllocateModule
 * @dev Interface for the AllocateModule contract that handles fund allocation and deallocation across multiple strategies.
 * @dev This module enables the vault to efficiently manage funds across different yield-generating strategies
 *      by batching multiple allocation/deallocation operations in a single transaction.
 *
 * @notice The AllocateModule serves as a coordinator for strategy operations, allowing the vault to:
 * - Allocate funds to multiple strategies in a single call
 * - Deallocate funds from multiple strategies in a single call
 * - Maintain accurate accounting of allocated amounts per strategy
 *
 * @notice This module is typically used during rebalancing operations where the vault needs to
 *         adjust allocations across multiple strategies based on current market conditions,
 *         strategy performance, or allocation targets.
 */
interface IAllocateModule {
    /**
     * @dev Emitted when funds are allocated or deallocated from a strategy.
     *
     * @param strategy The address of the strategy contract.
     * @param isDeposit True if this is an allocation (deposit) operation, false if it's a deallocation (withdrawal).
     * @param amount The amount of funds allocated or deallocated.
     * @param extraData Arbitrary calldata passed to the strategy's allocateFunds or deallocateFunds function.
     */
    event AllocatedFunds(address indexed strategy, bool indexed isDeposit, uint256 amount, bytes extraData);

    /**
     * @dev Structure containing parameters for a single allocation or deallocation operation.
     *
     * @param isDeposit True if this is an allocation (deposit) operation, false if it's a deallocation (withdrawal).
     * @param strategy The address of the strategy contract to interact with.
     * @param extraData Arbitrary calldata to pass to the strategy's allocateFunds or deallocateFunds function.
     *                  This allows for strategy-specific parameters like slippage tolerance, routing info, etc.
     */
    struct AllocateParams {
        bool isDeposit;
        address strategy;
        bytes extraData;
    }

    /**
     * @dev Executes multiple allocation and deallocation operations across different strategies in a single transaction.
     * @dev This function processes an array of allocation parameters, calling the appropriate strategy functions
     *      and updating the vault's internal accounting for each strategy.
     *
     * @param data ABI-encoded array of AllocateParams structures containing the operations to execute.
     *             Each AllocateParams specifies whether to allocate or deallocate funds, which strategy to use,
     *             and any additional data required by the strategy.
     *
     * @notice The function iterates through all provided parameters and:
     * - For deposits (isDeposit = true): Calls strategy.allocateFunds() and increases allocated amount
     * - For withdrawals (isDeposit = false): Calls strategy.deallocateFunds() and decreases allocated amount
     *
     * @notice All operations are executed atomically - if any single operation fails, the entire transaction reverts.
     *
     * @notice The function updates the vault's internal strategy accounting to track the total amount
     *         allocated to each strategy, which is used for yield calculation and strategy limits.
     */
    function allocateFunds(bytes calldata data) external;
}
