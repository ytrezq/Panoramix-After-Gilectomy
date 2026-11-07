// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PositionAccountingStorageLib} from "./PositionAccountingStorageLib.sol";
import {SafeCast} from "@openzeppelin-contracts/utils/math/SafeCast.sol";

/**
 * @title PositionAccountingLib
 * @dev Library for managing position accounting operations and validation
 * @dev Provides functionality for accounting change validation, cooldown periods, and thresholds
 */
library PositionAccountingLib {
    using SafeCast for int256;

    /// @notice Basis points constant (10000 = 100%)
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Custom errors
    error InvalidMaxAccountingChangeThreshold();

    /// @notice Minimum difference between cooldown period and accounting validity period (60 seconds)
    uint64 private constant MIN_PERIOD_DIFFERENCE = 60;

    /// @notice Emitted when an accounting change is too large
    /// @param accountingNonce The accounting nonce of the accounting change
    /// @param diff yield(+) or loss(-) amount
    /// @param oldAccounting The accounting before the accounting change
    /// @param maxAccountingChangeThreshold The maximum allowed accounting change threshold (BASIS_POINTS = 100%, 100 = 1%)
    event AccountingChangeTooLarge(
        uint256 accountingNonce, int256 diff, uint256 oldAccounting, uint64 maxAccountingChangeThreshold
    );

    /// @notice Emitted when the update cooldown period is not passed
    /// @param accountingNonce The accounting nonce of the accounting change
    /// @param currentTimestamp The current timestamp
    /// @param coolDownTimestamp The cool down timestamp
    event CooldownPeriodNotPassed(uint256 accountingNonce, uint256 currentTimestamp, uint256 coolDownTimestamp);

    /// @notice Emitted when the max accounting change threshold is set
    /// @param oldMaxAccountingChangeThreshold The old max accounting change threshold
    /// @param maxAccountingChangeThreshold The new max accounting change threshold
    event MaxAccountingChangeThresholdSet(uint64 oldMaxAccountingChangeThreshold, uint64 maxAccountingChangeThreshold);

    /// @notice Emitted when the update cooldown period is set
    /// @param oldCooldownPeriod The old update cooldown period
    /// @param cooldownPeriod The new update cooldown period
    event SetCooldownPeriod(uint64 oldCooldownPeriod, uint64 cooldownPeriod);

    /// @notice Emitted when the accounting validity period is set
    /// @param oldAccountingValidityPeriod The old accounting validity period
    /// @param accountingValidityPeriod The new accounting validity period
    event SetAccountingValidityPeriod(uint64 oldAccountingValidityPeriod, uint64 accountingValidityPeriod);

    /// @notice Custom errors
    error InvalidAccountingNonce(uint256 provided, uint256 expected);
    error InsufficientUnderlyingBalance();
    error AccountingValidityPeriodExpired();
    error InvalidAccountingValidityPeriod();
    error InvalidCooldownPeriod();

    /**
     * @notice Sets the max accounting change threshold
     * @param maxAccountingChangeThreshold_ The maximum accounting change threshold in basis points (BASIS_POINTS = 100%, 100 = 1%)
     */
    function setMaxAccountingChangeThreshold(uint64 maxAccountingChangeThreshold_) internal {
        require(maxAccountingChangeThreshold_ <= BASIS_POINTS, InvalidMaxAccountingChangeThreshold());
        PositionAccountingStorageLib.PositionAccountingStorage storage $ = PositionAccountingStorageLib.fetch();
        uint64 oldThreshold = $.maxAccountingChangeThreshold;
        emit MaxAccountingChangeThresholdSet(oldThreshold, maxAccountingChangeThreshold_);
        $.maxAccountingChangeThreshold = maxAccountingChangeThreshold_;
    }

    /**
     * @notice Sets the accounting change validation period
     * @param accountingValidityPeriod_ The new accounting change validation period in seconds
     */
    function setAccountingValidityPeriod(uint64 accountingValidityPeriod_) internal {
        PositionAccountingStorageLib.PositionAccountingStorage storage $ = PositionAccountingStorageLib.fetch();
        if (accountingValidityPeriod_ < $.cooldownPeriod + MIN_PERIOD_DIFFERENCE) {
            revert InvalidAccountingValidityPeriod();
        }
        uint64 oldPeriod = $.accountingValidityPeriod;
        emit SetAccountingValidityPeriod(oldPeriod, accountingValidityPeriod_);
        $.accountingValidityPeriod = accountingValidityPeriod_;
    }

    /**
     * @notice Sets the accounting update cooldown period
     * @param cooldownPeriod_ The new update cooldown period in seconds
     */
    function setCooldownPeriod(uint64 cooldownPeriod_) internal {
        PositionAccountingStorageLib.PositionAccountingStorage storage $ = PositionAccountingStorageLib.fetch();
        if (cooldownPeriod_ > $.accountingValidityPeriod - MIN_PERIOD_DIFFERENCE) revert InvalidCooldownPeriod();
        uint64 oldPeriod = $.cooldownPeriod;
        emit SetCooldownPeriod(oldPeriod, cooldownPeriod_);
        $.cooldownPeriod = cooldownPeriod_;
    }

    /**
     * @notice Returns the next accounting nonce
     * @return The next accounting nonce
     */
    function getNextAccountingNonce() internal view returns (uint256) {
        return PositionAccountingStorageLib.fetch().accountingNonce + 1;
    }

    /**
     * @notice Returns the last updated timestamp
     * @return The last updated timestamp
     */
    function getLastUpdatedTimestamp() internal view returns (uint64) {
        PositionAccountingStorageLib.PositionAccountingStorage storage $ = PositionAccountingStorageLib.fetch();
        return $.lastUpdatedTimestamp;
    }

    /**
     * @notice Returns the max accounting change threshold
     * @return The max accounting change threshold
     */
    function getMaxAccountingChangeThreshold() internal view returns (uint64) {
        PositionAccountingStorageLib.PositionAccountingStorage storage $ = PositionAccountingStorageLib.fetch();
        return $.maxAccountingChangeThreshold;
    }

    /**
     * @notice Returns the accounting validity period
     * @return The accounting validity period
     */
    function getAccountingValidityPeriod() internal view returns (uint64) {
        PositionAccountingStorageLib.PositionAccountingStorage storage $ = PositionAccountingStorageLib.fetch();
        return $.accountingValidityPeriod;
    }

    /**
     * @notice Returns the update cooldown period
     * @return The update cooldown period
     */
    function getCooldownPeriod() internal view returns (uint64) {
        PositionAccountingStorageLib.PositionAccountingStorage storage $ = PositionAccountingStorageLib.fetch();
        return $.cooldownPeriod;
    }

    /**
     * @notice Updates the timestamp and nonce in the position accounting storage
     * @return newNonce The new nonce value after incrementing
     */
    function updateTimestampAndNonce() internal returns (uint256 newNonce) {
        PositionAccountingStorageLib.PositionAccountingStorage storage accounting$ =
            PositionAccountingStorageLib.fetch();
        accounting$.lastUpdatedTimestamp = uint64(block.timestamp);
        accounting$.accountingNonce += 1;
        return accounting$.accountingNonce;
    }

    /**
     * @notice Checks if the accounting change is valid
     */
    function _checkAccountingValidity() internal view {
        PositionAccountingStorageLib.PositionAccountingStorage storage $ = PositionAccountingStorageLib.fetch();
        if (block.timestamp - $.lastUpdatedTimestamp > $.accountingValidityPeriod) {
            revert AccountingValidityPeriodExpired();
        }
    }

    /**
     * @notice Validates if an accounting change is acceptable
     * @param diff the diff to adjust the accounting by
     * @param accountingNonce_ The expected accounting nonce
     * @param currentAccounting The current accounting amount
     * @return isValid True if the change is valid (no pause needed), false if should pause
     */
    function isValidAccountingChange(int256 diff, uint256 accountingNonce_, uint256 currentAccounting)
        internal
        returns (bool isValid)
    {
        PositionAccountingStorageLib.PositionAccountingStorage storage accounting$ =
            PositionAccountingStorageLib.fetch();
        if (accountingNonce_ != accounting$.accountingNonce + 1) {
            revert InvalidAccountingNonce(accountingNonce_, accounting$.accountingNonce + 1);
        }
        return _validateAccountingChange(diff, accountingNonce_, currentAccounting);
    }

    /**
     * @notice Checks if the change is acceptable
     * @param diff the diff to adjust the accounting by
     * @param accountingNonce_ The next accounting nonce of the accounting change
     * @param currentAccounting The current accounting value
     */
    function _validateAccountingChange(int256 diff, uint256 accountingNonce_, uint256 currentAccounting)
        internal
        returns (bool)
    {
        PositionAccountingStorageLib.PositionAccountingStorage storage accounting$ =
            PositionAccountingStorageLib.fetch();

        uint256 coolDownTimestamp = accounting$.lastUpdatedTimestamp + accounting$.cooldownPeriod;
        bool isCooldownPeriodPassed = block.timestamp >= coolDownTimestamp;
        if (!isCooldownPeriodPassed) {
            emit CooldownPeriodNotPassed(accountingNonce_, block.timestamp, coolDownTimestamp);
        }

        uint256 divergence = diff < 0 ? uint256(-diff) : uint256(diff);
        uint256 divergencePercentage = (divergence * BASIS_POINTS) / (currentAccounting + 1);
        bool isAcceptableAccountingChange = divergencePercentage <= accounting$.maxAccountingChangeThreshold;
        if (!isAcceptableAccountingChange) {
            emit AccountingChangeTooLarge(
                accountingNonce_, diff, currentAccounting, accounting$.maxAccountingChangeThreshold
            );
        }
        return isCooldownPeriodPassed && isAcceptableAccountingChange;
    }
}
