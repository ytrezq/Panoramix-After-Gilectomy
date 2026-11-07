// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

/**
 * @title ITwoWayFeeSplitter
 * @author Blueprint-Finance
 * @notice Interface for the fee splitter with two recipients.
 */
interface ITwoWayFeeSplitter {
    /**
     * @dev The fee split for a given vault.
     * @param feeFractionOfSecondaryRecipient The fee fraction for the given vault.
     * @param mainRecipient The main recipient of the fees for the given vault.
     * @param secondaryRecipient The secondary recipient of the fees for the given vault.
     * @dev The secondary recipient gets a fraction of the fee defined by the fee fraction.
     * @dev For instance, if the fee fraction is 250 (i.e. 2.5%), the secondary recipient gets 2.5% of the fee and the main recipient gets 97.5% of the fee.
     */
    struct TwoWayFeeSplit {
        uint32 feeFractionOfSecondaryRecipient;
        address mainRecipient;
        address secondaryRecipient;
        bool set;
    }

    /**
     * @dev The storage of the fee splitter.
     * @param feeType The type of fee for the given vault (e.g. management fee = 1, performance fee = 2, etc.)
     * @param feeSplit The fee split for the given vault.
     */
    struct TwoWayFeeSplitterStorage {
        uint8 feeType;
        mapping(address vault => TwoWayFeeSplit) feeSplit;
        mapping(address vault => uint256 amount) distributedFees;
    }

    /**
     * ERRORS
     */

    /**
     * @dev Error thrown when the fee split would result in a revert during a collectFees call.
     * @param feeFractionOfSecondaryRecipient The fee fraction of the secondary recipient to check if it is invalid.
     * @param mainRecipient The main recipient to check if it is invalid.
     * @param secondaryRecipient The secondary recipient to check if it is invalid.
     */
    error InvalidFeeSplit(uint32 feeFractionOfSecondaryRecipient, address mainRecipient, address secondaryRecipient);

    /**
     * @dev Error thrown when the vault is invalid. No fee split has ever been set for this address.
     * @param vault The invalid vault.
     */
    error VaultInvalidOrWIthInvalidFeeSplit(address vault);

    /**
     * @dev Error thrown when the fee fraction is out of bounds.
     */
    error FeeFractionOutOfBounds();

    /**
     * @dev Error thrown when the token is invalid. Its either a vault with a fee split set or the zero address.
     * @param token The invalid token.
     */
    error InvalidToken(address token);

    /**
     * @dev Error thrown when the caller is neither the owner nor a vault manager.
     */
    error NeitherOwnerNorVaultManager();

    /**
     * EVENTS
     */

    /**
     * @dev Emitted when fees are collected for a given vault.
     * @param vault The vault that the fees are collected for.
     * @param fee1Amount The amount of fees collected for the main recipient.
     * @param fee2Amount The amount of fees collected for the secondary recipient.
     * @param recipient1 The main recipient of the fees.
     * @param recipient2 The secondary recipient of the fees.
     */
    event FeesDistributed(
        address indexed vault, uint256 fee1Amount, uint256 fee2Amount, address recipient1, address recipient2
    );

    /**
     * @dev Emitted when the fee fraction is set for a given vault.
     * @param vault The vault that the fee fraction is set for.
     * @param newFeeFraction The new fee fraction.
     */
    event FeeFractionSet(address indexed vault, uint32 newFeeFraction);

    /**
     * @dev Emitted when the main recipient is set for a given vault.
     * @param vault The vault that the main recipient is set for.
     * @param newMainRecipient The new main recipient.
     */
    event MainRecipientSet(address indexed vault, address newMainRecipient);

    /**
     * @dev Emitted when the secondary recipient is set for a given vault.
     * @param vault The vault that the secondary recipient is set for.
     * @param newSecondaryRecipient The new secondary recipient.
     */
    event SecondaryRecipientSet(address indexed vault, address newSecondaryRecipient);

    /**
     * @dev Emitted when tokens are rescued from the fee splitter.
     * @param token The token that is rescued.
     * @param amount The amount of tokens that are rescued.
     */
    event TokensRescued(address indexed token, uint256 amount);

    /**
     * @dev Emitted when a new fee split is registered.
     * @param vault The vault that the new fee split is registered for.
     * @param feeFractionOfSecondaryRecipient The fee fraction of the secondary recipient.
     * @param mainRecipient The main recipient of the fees.
     * @param secondaryRecipient The secondary recipient of the fees.
     */
    event RegisterNewFeeSplit(
        address indexed vault, uint32 feeFractionOfSecondaryRecipient, address mainRecipient, address secondaryRecipient
    );
}
