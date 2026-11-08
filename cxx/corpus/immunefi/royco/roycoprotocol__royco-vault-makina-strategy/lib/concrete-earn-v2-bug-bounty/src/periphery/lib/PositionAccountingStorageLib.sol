// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title PositionAccountingStorageLib
 * @dev Library for managing position accounting storage and validation
 * @dev Provides functionality for accounting change validation, cooldown periods, and thresholds
 */
library PositionAccountingStorageLib {
    /// @dev Storage location for keccak256(abi.encode(uint256(keccak256("concrete.storage.Positionaccounting.")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant POSITION_ACCOUNTING_STORAGE_LOCATION =
        0x5ce5a25f3602968dae3457825179f308a81a0ae9fafb34e4d83f623ffdb37f00;

    /// @notice The position accounting configuration structure
    struct PositionAccountingStorage {
        uint64 lastUpdatedTimestamp;
        uint64 cooldownPeriod; // in seconds
        uint64 maxAccountingChangeThreshold; // in basis points (10000 = 100%, 10 = 0.1%)
        uint64 accountingValidityPeriod; // in seconds
        uint256 accountingNonce;
    }

    /// @notice Fetches the PositionAccountingStorage from the specified location
    /// @return $ The PositionAccountingStorage struct
    function fetch() internal pure returns (PositionAccountingStorage storage $) {
        bytes32 position = POSITION_ACCOUNTING_STORAGE_LOCATION;
        assembly {
            $.slot := position
        }
    }

    /// @notice Initializes the PositionAccountingStorage with default values
    /// @param cooldownPeriod_ The update cooldown period in seconds
    /// @param maxAccountingChangeThreshold_ The maximum accounting change threshold in basis points
    /// @param accountingValidityPeriod_ The accounting validity period in seconds
    function initialize(uint64 cooldownPeriod_, uint64 maxAccountingChangeThreshold_, uint64 accountingValidityPeriod_)
        internal
    {
        PositionAccountingStorage storage $ = fetch();
        $.lastUpdatedTimestamp = uint64(block.timestamp);
        $.cooldownPeriod = cooldownPeriod_;
        $.maxAccountingChangeThreshold = maxAccountingChangeThreshold_;
        $.accountingValidityPeriod = accountingValidityPeriod_;
        $.accountingNonce = 0;
    }
}
