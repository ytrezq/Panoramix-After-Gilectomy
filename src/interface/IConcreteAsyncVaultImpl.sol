// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IConcreteStandardVaultImpl} from "./IConcreteStandardVaultImpl.sol";

/**
 * @title IConcreteAsyncVaultImpl
 * @dev Interface for the async vault implementation that provides epoch-based withdrawal management.
 * @dev This interface extends the standard vault functionality with asynchronous withdrawal capabilities,
 * allowing for better liquidity management and batch processing of withdrawal requests.
 * @dev Users submit withdrawal requests that are queued in epochs, processed by allocators when liquidity
 * is available, and then claimed by users after processing is complete.
 */
interface IConcreteAsyncVaultImpl is IConcreteStandardVaultImpl {
    enum EpochState {
        // Epoch is not active
        Inactive,
        // An epoch is active if it is receiving requests and is not closed
        Active,
        // An epoch is processing if it is closed (cannot receive requests anymore) and has not been processed
        Processing,
        // An epoch is processed if it has been processed and has a price locked
        Processed
    }

    /**
     * @dev Thrown when attempting to operate on a zero address.
     */
    error ZeroAddress();

    /**
     * @dev Thrown when attempting to withdraw zero shares.
     */
    error ZeroShares();

    /**
     * @dev Thrown when attempting to operate on an epoch with no requesting shares.
     */
    error NoRequestingShares();

    /**
     * @dev Thrown when attempting to claim a request that is not claimable.
     */
    error NoClaimableRequest();

    /**
     * @dev Thrown when there are no redeemable assets available.
     */
    error NoRedeemableAssets();

    /**
     * @dev Thrown when attempting to roll to next epoch while current epoch is not processed.
     */
    error EpochNotProcessed(uint256 epochID);

    /**
     * @dev Thrown when attempting to cancel a request for an epoch that has already been processed.
     */
    error EpochAlreadyProcessed(uint256 epochID);

    /**
     * @dev Thrown when attempting to claim with empty epoch IDs.
     */
    error EmptyEpochIDs();

    /**
     * @dev Thrown when attempting to claim with empty users.
     */
    error EmptyUsers();

    /**
     * @dev Emitted when the withdrawal queue is initialized.
     * @param epochID The initial epoch ID.
     */
    event WithdrawalQueueInitialized(uint256 epochID);

    /**
     * @dev Thrown when attempting to close an epoch that and previous epoch was not processed.
     */
    error PreviousEpochNotProcessed(uint256 epochID);

    /**
     * @dev Thrown when attempting to process an epoch that was already processed.
     */
    error PreviousEpochAlreadyProcessed(uint256 epochID);

    /**
     * @dev Thrown when attempting to process an epoch that is already closed.
     * @param epochID The epoch that was already closed.
     */
    error EpochAlreadyClosed(uint256 epochID);

    /**
     * @dev Thrown when attempting to process an epoch that is still open.
     * @param epochID The epoch that was still open.
     */
    error EpochStillOpen(uint256 epochID);

    /**
     * @dev Emitted when a user submits a withdrawal request that is queued for epoch processing.
     * @param owner The address of the user making the request.
     * @param assets The amount of assets requested for withdrawal.
     * @param shares The amount of shares transferred to the vault for the request.
     * @param epochID The epoch in which the request was queued.
     */
    event QueuedWithdrawal(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares,
        uint256 epochID
    );

    /**
     * @dev Emitted when a user cancels their pending withdrawal request.
     * @param owner The address of the user cancelling the request.
     * @param shares The amount of shares returned to the user.
     * @param epochID The epoch from which the request was cancelled.
     */
    event RequestCancelled(address indexed owner, uint256 shares, uint256 epochID);

    /**
     * @dev Emitted when a user claims their processed withdrawal request.
     * @param owner The address of the user claiming the withdrawal.
     * @param assets The amount of assets transferred to the user.
     * @param epochIDs The epoch IDs from which the request was claimed.
     */
    event RequestClaimed(address indexed owner, uint256 assets, uint256[] epochIDs);

    /**
     * @dev Emitted when an epoch's withdrawal requests are processed.
     * @param epochID The epoch ID that was processed.
     * @param shares The total shares processed in the epoch.
     * @param assets The total assets reserved for the epoch.
     * @param sharePrice The share price locked for the epoch.
     */
    event EpochProcessed(uint256 epochID, uint256 shares, uint256 assets, uint256 sharePrice);

    /**
     * @dev Emitted when a user's request is moved to the next epoch.
     * @param user The address of the user whose request was moved.
     * @param shares The amount of shares moved.
     * @param currentEpochID The epoch from which the request was moved.
     * @param nextEpochID The epoch to which the request was moved.
     */
    event RequestMovedToNextEpoch(address indexed user, uint256 shares, uint256 currentEpochID, uint256 nextEpochID);

    /**
     * @dev Emitted when an epoch is closed.
     * @param epochID The epoch that was closed.
     */
    event EpochClosed(uint256 epochID);

    /**
     * @dev Emitted when the queue is toggled.
     * @param isQueueActive The active status of the queue.
     */
    event QueueActiveToggled(bool isQueueActive);

    /**
     * @dev This struct definition is maintained for interface compatibility.
     */
    struct RedeemRequest {
        uint256 requestEpoch;
        uint256 requestShares;
    }

    /**
     * @notice Cancel pending redeem request for a specific epoch (only unprocessed epochs)
     * @dev Users can only cancel requests from epochs that haven't been processed yet (no price locked)
     * @dev Returns shares back to the user and updates epoch accounting
     * @param user The user address to cancel the request for
     * @param epochID The epoch ID from which to cancel the request
     */
    function cancelRequest(address user, uint256 epochID) external;

    /**
     * @notice Cancel pending redeem request for a specific epoch (only unprocessed epochs)
     * @dev Users can only cancel requests from epochs that haven't been processed yet (no price locked)
     * @dev Returns shares back to the user and updates epoch accounting
     * @param epochID The epoch ID from which to cancel the request
     */
    function cancelRequest(uint256 epochID) external;

    /**
     * @notice Claim processed redeem requests from specified epochs
     * @dev Processes each epoch internally, aggregates assets and shares, then burns and transfers once
     * @dev More gas efficient than claiming epochs individually
     * @dev Skips epochs with no claimable amounts (zero shares or unprocessed epochs)
     * @param epochIDs Array of epoch IDs to claim from
     */
    function claimWithdrawal(uint256[] calldata epochIDs) external;

    /**
     * @notice Claim processed redeem requests from specified epochs
     * @dev Processes each epoch internally, aggregates assets and shares, then burns and transfers once
     * @dev More gas efficient than claiming epochs individually
     * @dev Skips epochs with no claimable amounts (zero shares or unprocessed epochs)
     * @param user The user address to claim from
     * @param epochIDs Array of epoch IDs to claim from
     */
    function claimWithdrawal(address user, uint256[] calldata epochIDs) external;

    /**
     * @notice Close the current epoch
     * @dev Only callable by WITHDRAWAL_MANAGER role
     * @dev Closes the current epoch and increments the epoch ID
     * @dev Can only be called if the previous epoch is processed (!)
     */
    function closeEpoch() external;

    /**
     * @notice Process all pending redeem requests for a specific epoch
     * @dev Harvests all strategies to get current accurate pricing before processing
     * @dev Calculates share price and reserves required assets for the epoch
     * @dev Can process any epoch with pending requests, enabling historical processing
     * @dev Only callable by ALLOCATOR role
     */
    function processEpoch() external;

    /**
     * @notice Move a user's request to the next epoch
     * @param user The user address to move the request for
     */
    function moveRequestToNextEpoch(address user) external;

    /**
     * @notice Get claimable redeem request from a specific epoch
     * @dev Returns the amount of assets claimable by the caller from the specified epoch
     * @dev Returns 0 if epoch is not processed, no request exists, or epoch is current/future
     * @param epochID The epoch ID to check
     * @return assets The amount of assets claimable from the epoch
     */
    function getUserEpochRequestInAssets(address user, uint256 epochID) external view returns (uint256 assets);

    /**
     * @notice Get user's redeem request for a specific epoch
     * @dev Returns the amount of shares requested by the specified user in the epoch
     * @param user The user address to check
     * @param epochID The epoch ID to check
     * @return shares The amount of shares requested by the user in the epoch
     */
    function getUserEpochRequest(address user, uint256 epochID) external view returns (uint256 shares);

    /**
     * @notice Get the state of an epoch
     * @dev Returns the state of an epoch
     * @param epochID The epoch ID to check
     * @return The state of the epoch
     */
    function getEpochState(uint256 epochID) external view returns (EpochState);

    /**
     * @notice Get current epoch ID
     * @dev New withdrawal requests are queued in this epoch
     * @return The current epoch ID
     */
    function latestEpochID() external view returns (uint256);

    /**
     * @notice Get total redeemable assets from past epochs
     * @dev This amount is subtracted from totalAssets() to exclude reserved funds from active vault operations
     * @return The total assets reserved for past epoch claims
     */
    function pastEpochsUnclaimedAssets() external view returns (uint256);

    /**
     * @notice Get total requested shares in a specific epoch
     * @dev Returns the total shares from all users that requested withdrawal in the epoch
     * @dev Returns 0 after epoch is processed (shares moved to requestingSharesInPast)
     * @param epochID The epoch ID to check
     * @return The total shares requested in the epoch
     */
    function totalRequestedSharesPerEpoch(uint256 epochID) external view returns (uint256);

    /**
     * @notice Get total requested shares in the active and processing epochs
     * @dev Returns the total shares from all users that requested withdrawal in the active and processing epochs
     * @return activeShares The total shares requested in the active epoch
     * @return processingShares The total shares requested in the processing epoch
     * @return processedShares The total shares requested in the last processed epoch
     */
    function totalRequestedSharesForCurrentEpochs()
        external
        view
        returns (uint256 activeShares, uint256 processingShares, uint256 processedShares);

    /**
     * @notice Get share price for a specific epoch
     * @dev Returns the share price that was locked when the epoch was processed
     * @dev Returns 0 if the epoch has not been processed yet
     * @param epochID The epoch ID to check
     * @return The share price locked when the epoch was processed (in assets per 1e18 shares)
     */
    function getEpochPricePerShare(uint256 epochID) external view returns (uint256);

    /**
     * @notice Get whether the queue is active
     * @dev Returns true if the queue is active, false otherwise
     * @return The active status of the queue
     */
    function isQueueActive() external view returns (bool);

    /**
     * @notice Toggle the active status of the queue
     * @dev Only callable by the ALLOCATOR role
     */
    function toggleQueueActive() external;
}
