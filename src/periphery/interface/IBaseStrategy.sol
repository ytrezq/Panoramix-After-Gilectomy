// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IStrategyTemplate} from "../../interface/IStrategyTemplate.sol";

/**
 * @title IBaseStrategy
 * @dev Interface for BaseStrategy extending IStrategyTemplate
 * @dev Contains events and errors specific to BaseStrategy
 */
interface IBaseStrategy is IStrategyTemplate {
    /**
     * @notice Emitted when funds are allocated from the vault to the strategy
     * @param amount The amount of funds allocated
     */
    event AllocateFunds(uint256 amount);

    /**
     * @notice Emitted when funds are deallocated from the strategy back to the vault
     * @param amount The amount of funds deallocated
     */
    event DeallocateFunds(uint256 amount);

    /**
     * @notice Emitted when funds are withdrawn from the strategy
     * @param amount The amount of funds withdrawn
     */
    event StrategyWithdraw(uint256 amount);

    /**
     * @notice Emitted when the maximum withdrawal amount is updated
     * @param oldMaxWithdraw The previous maximum withdrawal amount
     * @param newMaxWithdraw The new maximum withdrawal amount
     */
    event MaxWithdrawUpdated(uint256 oldMaxWithdraw, uint256 newMaxWithdraw);

    /**
     * @notice Thrown when a function is called by an unauthorized vault
     * @dev Only the vault bound to this strategy can call strategy functions
     */
    error UnauthorizedVault();

    /**
     * @notice Thrown when there are insufficient funds in the strategy for the requested operation
     * @dev This error indicates the strategy doesn't have enough balance to fulfill the request
     */
    error InsufficientBalance();

    /**
     * @notice Thrown when trying to deallocate more funds than are currently allocated
     * @dev This error prevents over-deallocation of funds from the strategy
     */
    error InsufficientAllocatedAmount();

    /**
     * @notice Thrown when trying to recover the strategy's primary asset token
     * @dev Emergency recovery cannot be used to recover the strategy's main asset
     */
    error InvalidAsset();

    /**
     * @notice Thrown when trying to withdraw more than the maximum allowed amount
     * @dev The withdrawal amount exceeds the strategy's maxWithdraw limit
     */
    error MaxWithdrawAmountExceeded();

    /**
     * @notice Thrown when trying to initialize with a zero admin address
     * @dev The admin address must be a valid non-zero address
     */
    error ZeroAdminAddress();

    /**
     * @notice Thrown when trying to initialize with a zero vault address
     * @dev The vault address must be a valid non-zero address
     */
    error ZeroVaultAddress();
}
