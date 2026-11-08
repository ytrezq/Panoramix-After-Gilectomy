// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {IAccessControl} from "@openzeppelin-contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ConcreteV2RolesLib} from "../../../src/lib/Roles.sol";
import {ConcreteV2ConstantsLib} from "../../../src/lib/Constants.sol";
import {ITwoWayFeeSplitter} from "../interface/IFeeSplitter.sol";

/**
 * @title TwoWayFeeSplitter
 * @author Blueprint Finance
 * @notice This in auxiliary contract that can be used to abstract away the logic of fee splitting.
 * @dev Each fee type should have its own fee splitter contract, hence it is architected as a clonable contract.
 * @dev For each vault and fee type, fees are accruing and the collection can be triggered permissionlessly.
 * @dev During a collection automatically the fees are send out to the main recipient and a secondary recipient with the corresponding ratio.
 */
contract TwoWayFeeSplitter is OwnableUpgradeable, ITwoWayFeeSplitter, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev keccak256(abi.encode(uint256(keccak256("concrete.utils.fee-splitter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ConcreteTwoWayFeeSplitterLocation =
        0xe59e1996f78369fdb0652cbe6c7621b6c36d906f53d5d65910abbe196af08500;

    /**
     * CONSTRUCTOR
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Modifier that collects the fees for a given vault if the previous fee split is valid.
     * @param vault The vault to collect fees for.
     */
    modifier distributeFeesWithPrevSplitArgs(address vault) {
        TwoWayFeeSplit memory oldFeeSplit = s().feeSplit[vault];
        _;
        if (oldFeeSplit.set) _distributeFeesAndUpdate(vault, oldFeeSplit);
    }

    /**
     * INITIALIZER
     */

    /**
     * @dev Initializes the contract.
     * @param owner The owner of the contract.
     * @param feeType The type of the fee. E.g. Management Fee, Performance Fee, Deposit Fee, etc.
     */
    function initialize(address owner, uint8 feeType) external initializer {
        __Ownable_init_unchained(owner);
        __ReentrancyGuard_init_unchained();
        s().feeType = feeType;
    }

    /**
     * MAIN FUNCTIONS
     */

    /**
     * @dev Collects the fees for a given vault.
     * @param vault The vault to collect fees for.
     * @dev A fee fraction determines the amount of fees that are sent to the respective recipients.
     * @dev If the fee fraction is zero, all fees are sent to the main recipient.
     * @dev If the fee fraction is 100% (i.e. BASIS_POINTS_DENOMINATOR), all fees are sent to the secondary recipient.
     * @dev The main fee recipient can be thought of as the vault fee recipient, whilst the secondary recipient can be thought of the service provider.
     */
    function distributeFees(address vault) external nonReentrant {
        TwoWayFeeSplit memory feeSplit = s().feeSplit[vault];
        if (!feeSplit.set) revert VaultInvalidOrWIthInvalidFeeSplit(vault);
        _distributeFeesAndUpdate(vault, feeSplit);
    }

    /**
     * SETTERS
     */

    /**
     * @dev Sets the fee split for a given vault.
     * @param vault The vault to set the fee split for.
     * @param feeFractionOfSecondaryRecipient The fee fraction to set. This is the fraction of the fees going to the secondary recipient.
     * @param mainRecipient The main recipient to set. This is the vault fee recipient.
     * @param secondaryRecipient The secondary recipient to set. This is the service provider.
     * @dev The Fee Splitter Owner can set all parameters at once.
     */
    function setFeeSplit(
        address vault,
        uint32 feeFractionOfSecondaryRecipient,
        address mainRecipient,
        address secondaryRecipient
    ) external onlyOwner {
        // load the entire fee split for this vault into memory
        TwoWayFeeSplit memory split = s().feeSplit[vault];

        // revert if the fee split is malformed
        _revertIfMalformedFeeSplit(feeFractionOfSecondaryRecipient, mainRecipient, secondaryRecipient);

        if (split.set) {
            // if the fee split is already set, distribute the fees with old splitting parameters
            _distributeFeesAndUpdate(vault, split);
        } else {
            // if the fee split has not been set yet, emit the event
            emit RegisterNewFeeSplit(vault, feeFractionOfSecondaryRecipient, mainRecipient, secondaryRecipient);
        }

        // set the fee split
        s().feeSplit[vault] = TwoWayFeeSplit({
            feeFractionOfSecondaryRecipient: feeFractionOfSecondaryRecipient,
            mainRecipient: mainRecipient,
            secondaryRecipient: secondaryRecipient,
            set: true
        });

        // emit events for all parameters that have changed
        if (feeFractionOfSecondaryRecipient != split.feeFractionOfSecondaryRecipient) {
            emit FeeFractionSet(vault, feeFractionOfSecondaryRecipient);
        }
        if (mainRecipient != split.mainRecipient) {
            emit MainRecipientSet(vault, mainRecipient);
        }
        if (secondaryRecipient != split.secondaryRecipient) {
            emit SecondaryRecipientSet(vault, secondaryRecipient);
        }
    }

    /**
     * @dev Sets the fee fraction for a given vault. This is the fraction of the fees going to the secondary recipient.
     * @param vault The vault to set the fee fraction for.
     * @param newFeeFractionOfSecondaryRecipient The new fee fraction to set.
     * @dev The Fee Splitter Owner can set the fee fraction at any time.
     */
    function setFeeFraction(address vault, uint32 newFeeFractionOfSecondaryRecipient)
        external
        onlyOwner
        distributeFeesWithPrevSplitArgs(vault)
    {
        TwoWayFeeSplit storage split = s().feeSplit[vault];
        _revertIfMalformedFeeSplit(newFeeFractionOfSecondaryRecipient, split.mainRecipient, split.secondaryRecipient);
        split.feeFractionOfSecondaryRecipient = newFeeFractionOfSecondaryRecipient;
        emit FeeFractionSet(vault, newFeeFractionOfSecondaryRecipient);
    }

    /**
     * @dev Sets the main recipient for a given vault.
     * @param vault The vault to set the main recipient for.
     * @param newMainRecipient The new main recipient to set.
     * @dev The Fee Splitter Owner can set the main recipient at any time.
     */
    function setMainRecipient(address vault, address newMainRecipient) external distributeFeesWithPrevSplitArgs(vault) {
        // fee splitter owner or vault manager can set the main recipient
        if (_msgSender() != owner() && !IAccessControl(vault).hasRole(ConcreteV2RolesLib.VAULT_MANAGER, _msgSender())) {
            revert NeitherOwnerNorVaultManager();
        }
        TwoWayFeeSplit storage split = s().feeSplit[vault];
        _revertIfMalformedFeeSplit(split.feeFractionOfSecondaryRecipient, newMainRecipient, split.secondaryRecipient);
        split.mainRecipient = newMainRecipient;
        emit MainRecipientSet(vault, newMainRecipient);
    }

    /**
     * @dev Sets the secondary recipient for a given vault.
     * @param vault The vault to set the secondary recipient for.
     * @param secondaryRecipient The new secondary recipient to set.
     * @dev The Fee Splitter Owner can set the secondary recipient at any time.
     */
    function setSecondaryRecipient(address vault, address secondaryRecipient)
        external
        onlyOwner
        distributeFeesWithPrevSplitArgs(vault)
    {
        TwoWayFeeSplit storage split = s().feeSplit[vault];
        _revertIfMalformedFeeSplit(split.feeFractionOfSecondaryRecipient, split.mainRecipient, secondaryRecipient);
        split.secondaryRecipient = secondaryRecipient;
        emit SecondaryRecipientSet(vault, secondaryRecipient);
    }

    /**
     * @dev Rescues tokens from the fee splitter.
     * @param token The token to rescue.
     * @dev The Fee Splitter Owner can rescue tokens at any time.
     * @dev The token must not be a registered vault or the zero address.
     */
    function rescueTokens(address token) external onlyOwner {
        // catch zero address and tokens that are accrued fees in terms of vault-shares
        if (token == address(0) || feeSplitForVaultIsActive(token)) revert InvalidToken(token);
        // transfer the tokens to the owner
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(_msgSender(), balance);
        emit TokensRescued(token, balance);
    }

    /**
     * GETTERS
     */

    /**
     * @dev Returns the amount of fees accrued for a given vault.
     * @param vault The vault to get the fees accrued for.
     * @return The amount of fees accrued for the given vault.
     */
    function feesAccrued(address vault) external view returns (uint256) {
        return IERC20(vault).balanceOf(address(this));
    }

    /**
     * @dev Returns the amount of fees distributed for a given vault.
     * @param vault The vault to get the fees distributed for.
     * @return The amount of fees distributed for the given vault.
     */
    function feesDistributed(address vault) external view returns (uint256) {
        return s().distributedFees[vault];
    }

    /**
     * @dev Returns the fee type for a given vault.
     * @return The fee type for the given vault.
     * @dev The fee type is the type of fee for the given vault. E.g. Management Fee = 1, Performance Fee = 2, Deposit Fee = 3, etc.
     */
    function getFeeType() external view returns (uint8) {
        return s().feeType;
    }

    /**
     * @dev Returns the fee fraction for the secondary recipient for a given vault.
     * @param vault The vault to get the fee fraction for the secondary recipient for.
     * @return The fee fraction for the secondary recipient for the given vault.
     * @dev The fee fraction is the fraction of the fees going to the secondary recipient.
     */
    function getFeeFractionForSecondaryRecipient(address vault) external view returns (uint32) {
        return s().feeSplit[vault].feeFractionOfSecondaryRecipient;
    }

    /**
     * @dev Returns the main recipient for a given vault.
     * @param vault The vault to get the main recipient for.
     * @return The main recipient for the given vault.
     */
    function getMainRecipient(address vault) external view returns (address) {
        return s().feeSplit[vault].mainRecipient;
    }

    /**
     * @dev Returns the secondary recipient for a given vault.
     * @param vault The vault to get the secondary recipient for.
     * @return The secondary recipient for the given vault.
     */
    function getSecondaryRecipient(address vault) external view returns (address) {
        return s().feeSplit[vault].secondaryRecipient;
    }

    /**
     * @dev Returns whether a token is a vault token.
     * @param vault The token to check if it is a vault token.
     * @return Whether a token is a vault token.
     * @dev In this iteration the fee split is active if and only if the fee split is valid if and only if the status is not 0.
     */
    function feeSplitForVaultIsActive(address vault) public view returns (bool) {
        return s().feeSplit[vault].set;
    }

    /**
     * @dev Returns whether a fee split is registered for a given vault.
     * @param vault The vault to check if a fee split is registered for.
     * @return Whether a fee split is registered for the given vault.
     */
    function hasValidFeeSplit(address vault) external view returns (bool) {
        TwoWayFeeSplit memory feeSplit = s().feeSplit[vault];
        return !_isInvalidFeeSplit(
            feeSplit.feeFractionOfSecondaryRecipient, feeSplit.mainRecipient, feeSplit.secondaryRecipient
        );
    }

    /**
     * INTERNAL FUNCTIONS
     */
    function s() internal pure returns (TwoWayFeeSplitterStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := ConcreteTwoWayFeeSplitterLocation
        }
    }

    /**
     * @dev Distributes the fees for a given vault.
     * @param vault The vault to distribute fees for.
     * @param feeSplit The fee split to use.
     */
    function _distributeFeesAndUpdate(address vault, TwoWayFeeSplit memory feeSplit) internal {
        uint256 feeAmount = IERC20(vault).balanceOf(address(this));
        if (feeAmount != 0) {
            (uint256 fee1Amount, uint256 fee2Amount) = _distributeAmountOfFees(feeAmount, vault, feeSplit);
            emit FeesDistributed(vault, fee1Amount, fee2Amount, feeSplit.mainRecipient, feeSplit.secondaryRecipient);
            unchecked {
                s().distributedFees[vault] += feeAmount;
            }
        }
    }

    /**
     * @dev Distributes the fees for a given vault.
     * @param feeAmount The amount of fees to distribute.
     * @param vault The vault to distribute fees for.
     * @param feeSplit The fee split to use.
     * @return fee1Amount The amount of fees to send to the main recipient.
     * @return fee2Amount The amount of fees to send to the secondary recipient.
     */
    function _distributeAmountOfFees(uint256 feeAmount, address vault, TwoWayFeeSplit memory feeSplit)
        internal
        returns (uint256 fee1Amount, uint256 fee2Amount)
    {
        // calculate the amount of fees to send to the main recipient
        fee1Amount = Math.mulDiv(
            feeAmount,
            ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR - feeSplit.feeFractionOfSecondaryRecipient,
            ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR,
            Math.Rounding.Ceil
        );
        if (fee1Amount != 0) {
            // send the fees to the main recipient
            IERC20(vault).safeTransfer(feeSplit.mainRecipient, fee1Amount);
        }
        if (feeAmount > fee1Amount) {
            unchecked {
                fee2Amount = feeAmount - fee1Amount;
            }
            // send the fees to the secondary recipient
            IERC20(vault).safeTransfer(feeSplit.secondaryRecipient, fee2Amount);
        }
    }

    /**
     * @dev Returns whether a fee split is invalid. If the collection of fees would revert, the fee split is invalid.
     * @param feeFractionOfSecondaryRecipient The fee fraction of the secondary recipient to check if it is invalid.
     * @param mainRecipient The main recipient to check if it is invalid.
     * @param secondaryRecipient The secondary recipient to check if it is invalid.
     * @return Whether a fee split is invalid.
     */
    function _isInvalidFeeSplit(
        uint32 feeFractionOfSecondaryRecipient,
        address mainRecipient,
        address secondaryRecipient
    ) internal view returns (bool) {
        // is invalid if recipient 1 is not set but fraction is not maximal (i.e. BASIS_POINTS_DENOMINATOR)
        bool isInvalidOption1 = mainRecipient == address(this)
            || (mainRecipient == address(0)
                && feeFractionOfSecondaryRecipient != ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR);
        // is invalid if recipient 2 is not set but fraction is not 0
        bool isInvalidOption2 = secondaryRecipient == address(this)
            || (secondaryRecipient == address(0) && feeFractionOfSecondaryRecipient != 0);
        // is invalid if recipient 1 and 2 are the same
        bool isInvalidOption3 = mainRecipient == secondaryRecipient;

        // is valid if neither of the above is true
        return isInvalidOption1 || isInvalidOption2 || isInvalidOption3;
    }

    /**
     * @dev Reverts if a fee split is malformed.
     * @param newFeeFractionOfSecondaryRecipient The new fee fraction to check if it is malformed.
     * @param newMainRecipient The new main recipient to check if it is malformed.
     * @param newSecondaryRecipient The new secondary recipient to check if it is malformed.
     */
    function _revertIfMalformedFeeSplit(
        uint32 newFeeFractionOfSecondaryRecipient,
        address newMainRecipient,
        address newSecondaryRecipient
    ) internal view {
        if (uint256(newFeeFractionOfSecondaryRecipient) > ConcreteV2ConstantsLib.BASIS_POINTS_DENOMINATOR) {
            revert FeeFractionOutOfBounds();
        }
        if (_isInvalidFeeSplit(newFeeFractionOfSecondaryRecipient, newMainRecipient, newSecondaryRecipient)) {
            revert InvalidFeeSplit(newFeeFractionOfSecondaryRecipient, newMainRecipient, newSecondaryRecipient);
        }
    }
}
