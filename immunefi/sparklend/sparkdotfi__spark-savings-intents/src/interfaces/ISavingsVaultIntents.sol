// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

/**
 *  @title ISavingsVaultIntents
 *  @dev   Interface for managing intent-based withdrawal requests from spark savings vaults v2.
 *         Users submit withdrawal requests that a relayer fulfills offchain.
 */
interface ISavingsVaultIntents {

    /**********************************************************************************************/
    /*** Types                                                                                  ***/
    /**********************************************************************************************/

    /**
     *  @dev   Configuration for a specific vault.
     *  @param whitelisted     Whether the vault is allowed to be used with this contract.
     *  @param minIntentAssets Minimum asset value (in underlying) required per withdrawal request.
     *  @param maxIntentAssets Maximum asset value (in underlying) allowed per withdrawal request.
     */
    struct VaultConfig {
        bool    whitelisted;
        uint256 minIntentAssets;
        uint256 maxIntentAssets;
    }

    /**
     *  @dev   Data for a pending withdrawal request.
     *  @param requestId Auto-incrementing identifier scoped to the vault.
     *  @param shares    Number of vault shares the user wants to withdraw.
     *  @param recipient Address that will receive the redeemed assets.
     *  @param deadline  Timestamp after which the request can no longer be fulfilled.
     */
    struct WithdrawRequest {
        uint256 requestId;
        uint256 shares;
        address recipient;
        uint256 deadline;
    }

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    /// @dev Thrown when trying to fulfill a request after its deadline has passed.
    error DeadlineExceeded(address account, address vault, uint256 requestId, uint256 deadline);

    /// @dev Thrown when the caller does not hold enough vault shares to cover the request.
    error InsufficientShares(uint256 sharesRequested, uint256 sharesPresent);

    /// @dev Thrown when the contract does not have enough share allowance from the caller.
    error InsufficientAllowance(uint256 requiredAllowance, uint256 currentAllowance);

    /// @dev Thrown when the request's asset value exceeds the vault's configured maximum.
    error IntentAssetsAboveMax(uint256 maxAssets, uint256 assets);

    /// @dev Thrown when the request's asset value is below the vault's configured minimum.
    error IntentAssetsBelowMin(uint256 minAssets, uint256 assets);

    /// @dev Thrown when the admin address is the zero address.
    error InvalidAdminAddress();

    /// @dev Thrown when the deadline exceeds block.timestamp + maxDeadlineDuration.
    error InvalidDeadline(uint256 maxDeadline, uint256 deadline);

    /// @dev Thrown when the max deadline offset is set to zero.
    error InvalidMaxDeadlineDuration();

    /// @dev Thrown when the recipient address is the zero address.
    error InvalidRecipientAddress();

    /// @dev Thrown when the relayer address is the zero address.
    error InvalidRelayerAddress();

    /// @dev Thrown when the vault address is the zero address.
    error InvalidVaultAddress();

    /// @dev Thrown when min intent assets is not less than max intent assets.
    error InvalidIntentAmountBounds(uint256 minIntentAssets, uint256 maxIntentAssets);

    /// @dev Thrown when no pending request exists for the given account and vault.
    error RequestNotFound(address account, address vault);

    /// @dev Thrown when the vault is not whitelisted.
    error VaultNotWhitelisted();

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     *  @dev   Emitted when the admin updates the maximum allowed deadline offset.
     *  @param maxDeadlineDuration New maximum deadline offset in seconds.
     */
    event MaxDeadlineDurationUpdated(uint256 indexed maxDeadlineDuration);

    /**
     *  @dev   Emitted when a user cancels their pending withdrawal request.
     *  @param account   Address of the user who created the request.
     *  @param vault     Address of the vault the request was against.
     *  @param requestId Identifier of the cancelled request.
     */
    event RequestCancelled(
        address indexed account,
        address indexed vault,
        uint256 indexed requestId
    );

    /**
     *  @dev   Emitted when a user creates a new withdrawal request.
     *  @param account   Address of the user creating the request.
     *  @param vault     Address of the vault to withdraw from.
     *  @param requestId Identifier assigned to this request.
     *  @param shares    Number of vault shares to withdraw.
     *  @param recipient Address that will receive the redeemed assets.
     *  @param deadline  Timestamp after which the request expires.
     */
    event RequestCreated(
        address indexed account,
        address indexed vault,
        uint256 indexed requestId,
        uint256         shares,
        address         recipient,
        uint256         deadline
    );

    /**
     *  @dev   Emitted when the relayer fulfills a pending withdrawal request.
     *  @param account   Address of the user whose request was fulfilled.
     *  @param vault     Address of the vault the request was against.
     *  @param requestId Identifier of the fulfilled request.
     */
    event RequestFulfilled(
        address indexed account,
        address indexed vault,
        uint256 indexed requestId
    );

    /**
     *  @dev   Emitted when the admin updates a vault's configuration.
     *  @param vault           Address of the vault being configured.
     *  @param whitelisted     Whether the vault is now whitelisted.
     *  @param minIntentAssets New minimum asset value per request.
     *  @param maxIntentAssets New maximum asset value per request.
     */
    event VaultConfigUpdated(
        address indexed vault,
        bool    indexed whitelisted,
        uint256         minIntentAssets,
        uint256         maxIntentAssets
    );

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    /**
     *  @dev   Sets the max allowed deadline offset from block.timestamp at request time.
     *         This function can only be called by accounts with DEFAULT_ADMIN_ROLE.
     *  @param maxDeadlineDuration_ New maximum deadline offset in seconds.
     */
    function setMaxDeadlineDuration(uint256 maxDeadlineDuration_) external;

    /**
     *  @dev   Updates the configuration for a given vault.
     *         This function can only called by accounts with DEFAULT_ADMIN_ROLE.
     *  @param vault            Address of the vault to configure.
     *  @param whitelisted_     Whether the vault should be whitelisted.
     *  @param minIntentAssets_ Minimum asset value required per request.
     *  @param maxIntentAssets_ Maximum asset value allowed per request.
     */
    function updateVaultConfig(
        address vault,
        bool    whitelisted_,
        uint256 minIntentAssets_,
        uint256 maxIntentAssets_
    ) external;

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    /**
     *  @dev    Cancels the caller's pending withdrawal request for a given vault.
     *  @param  vault     Address of the vault to cancel the request for.
     *  @return requestId Identifier of the cancelled request.
     */
    function cancel(address vault) external returns (uint256 requestId);

    /**
     *  @dev   Fulfills a pending withdrawal request by redeeming shares from the vault.
     *         This function can only called by accounts with RELAYER role.
     *  @param account   Address of the user whose request is being fulfilled.
     *  @param vault     Address of the vault to redeem from.
     *  @param requestId Expected request identifier, used to prevent stale fulfillments.
     */
    function fulfill(address account, address vault, uint256 requestId) external;

    /**
     *  @dev    Creates a new withdrawal request for a given vault.
     *          The caller must have approved this contract to transfer their vault shares.
     *  @param  vault     Address of the vault to withdraw from.
     *  @param  shares    Number of vault shares to withdraw.
     *  @param  recipient Address that will receive the redeemed assets.
     *  @param  deadline  Timestamp after which the request expires. Must be strictly greater than 
     *                    the current block timestamp and must not exceed block.timestamp + maxDeadlineDuration.
     *  @return requestId Identifier assigned to the new request.
     */
    function request(
        address vault,
        uint256 shares,
        address recipient,
        uint256 deadline
    ) external returns (uint256 requestId);

    /**********************************************************************************************/
    /*** View functions                                                                         ***/
    /**********************************************************************************************/

    /**
     *  @dev    Returns the max time after a request is made that the deadline can be set to.
     *  @return maxDeadlineDuration Maximum deadline offset from block.timestamp at request time, in seconds.
     */
    function maxDeadlineDuration() external view returns (uint256 maxDeadlineDuration);

    /**
     *  @dev    Returns the ACL role identifier used for the relayer.
     *  @return relayer The bytes32 role hash for the relayer.
     */
    function RELAYER() external view returns (bytes32 relayer);

    /**
     *  @dev    Returns the configuration for a given vault.
     *  @param  vault           Address of the vault to query.
     *  @return whitelisted     Whether the vault is whitelisted.
     *  @return minIntentAssets Minimum asset value required per request.
     *  @return maxIntentAssets Maximum asset value allowed per request.
     */
    function vaultConfig(address vault)
        external
        view
        returns (
            bool    whitelisted,
            uint256 minIntentAssets,
            uint256 maxIntentAssets
        );

    /**
     *  @dev    Returns the total number of withdrawal requests created for a given vault.
     *  @param  vault        Address of the vault to query.
     *  @return requestCount Total number of requests created. The last created request ID equals
     *                       requestCount. The next request ID will be requestCount + 1.
     */
    function vaultRequestCount(address vault) external view returns (uint256 requestCount);

    /**
     *  @dev    Returns the pending withdrawal request for a given account and vault.
     *  @param  account   Address of the user to query.
     *  @param  vault     Address of the vault to query.
     *  @return requestId Identifier of the request.
     *  @return shares    Number of vault shares in the request.
     *  @return recipient Address that will receive the redeemed assets.
     *  @return deadline  Timestamp after which the request expires.
     */
    function withdrawRequests(address account, address vault)
        external
        view
        returns (
            uint256 requestId,
            uint256 shares,
            address recipient,
            uint256 deadline
        );

}
