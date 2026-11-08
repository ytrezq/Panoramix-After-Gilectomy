// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IConcreteStandardVaultImpl} from "./IConcreteStandardVaultImpl.sol";

interface IConcretePredepositVaultImpl is IConcreteStandardVaultImpl {
    /**
     * @notice Emitted when a user claims their shares on the target chain
     * @param user The user who initiated the claim
     * @param shares The amount of shares locked
     */
    event SharesClaimedOnTargetChain(address indexed user, uint256 shares);

    /**
     * @notice Emitted when self claims are enabled or disabled
     * @param enabled Whether self claims are enabled
     */
    event SelfClaimsEnabledUpdated(bool enabled);

    /**
     * @notice Error thrown when user has no shares to claim
     */
    error NoSharesToClaim();

    /**
     * @notice Error thrown when deposits are not locked
     */
    error DepositsNotLocked();

    /**
     * @notice Error thrown when addresses array length is invalid (must be > 0 and <= 150)
     * @param length The actual length of the addresses array
     */
    error BadAddressArrayLength(uint256 length);

    /**
     * @notice Error thrown when user address is invalid
     */
    error InvalidUserAddress();

    /**
     * @notice Error thrown when no shares available in batch
     */
    error NoSharesInBatch();

    /**
     * @notice Error thrown when self claims are disabled
     */
    error SelfClaimsDisabled();

    /**
     * @notice Error thrown when OApp is not set
     */
    error OAppNotSet();

    /**
     * @notice Error thrown when withdrawals are not locked
     */
    error WithdrawalsNotLocked();

    /**
     * @notice Claim all shares owned by msg.sender on L1 on target chain
     * @dev Sends a single LZ message to remote chain with an account and the amount of eligable shares.
     * @dev burns shares on L1
     * @dev Accrues yield to sync strategy state, but strategies should report no yield after claims open
     * @dev protected by selfClaimsEnabled
     * @param options LayerZero messaging options
     */
    function claimOnTargetChain(bytes calldata options) external payable;

    /**
     * @notice Batch claim shares on target chain for multiple addresses
     * @dev Only callable by VAULT_MANAGER. Processes multiple addresses and sends a single LZ message
     * @dev Skips addresses with zero shares (including users who already claimed)
     * @dev Accrues yield to sync strategy state, but strategies should have no yield after claims open
     * @param addressesData Encoded array of addresses to claim for
     * @param options LayerZero messaging options
     */
    function batchClaimOnTargetChain(bytes calldata addressesData, bytes calldata options) external payable;

    /**
     * @notice Returns the locked shares for a user
     * @param user The user address
     * @return The amount of locked shares
     */
    function getLockedShares(address user) external view returns (uint256);

    /**
     * @notice Sets whether self claims are enabled
     * @param enabled Whether to enable or disable self claims
     * @dev Only callable by addresses with VAULT_MANAGER role
     */
    function setSelfClaimsEnabled(bool enabled) external;

    /**
     * @notice Returns whether self claims are enabled
     * @return True if self claims are enabled, false otherwise
     */
    function getSelfClaimsEnabled() external view returns (bool);

    /**
     * @notice Sets the OApp contract address for cross-chain messaging
     * @param oappAddress The address of the OApp contract
     * @dev Only callable by addresses with VAULT_MANAGER role
     */
    function setOApp(address oappAddress) external;

    /**
     * @notice Returns the OApp contract address
     * @return The address of the OApp contract
     */
    function getOApp() external view returns (address);
}
