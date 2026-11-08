// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title MultisigStrategyStorageLib
 * @dev Library for managing MultisigStrategy-specific storage
 * @dev Provides storage for multisig address, deposited amount, withdraw state, and operator
 */
library MultisigStrategyStorageLib {
    /// @dev Storage location for MultisigStrategyStorage keccak256(abi.encode(uint256(keccak256("concrete.storage.MultisigStrategyStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MULTISIG_STRATEGY_STORAGE_LOCATION =
        0xcb7da0d8897752a6df968d7ec6cb8f24f19b693fff4548ee51892258c2c21a00;

    /// @notice The MultisigStrategy storage structure
    struct MultisigStrategyStorage {
        address multiSig; // The address of the multi-signature wallet
        uint256 vaultDepositedAmount; // The amount of assets deposited into this strategy
    }

    /// @notice Fetches the MultisigStrategyStorage from the specified location
    /// @return $ The MultisigStrategyStorage struct
    function fetch() internal pure returns (MultisigStrategyStorage storage $) {
        bytes32 position = MULTISIG_STRATEGY_STORAGE_LOCATION;
        assembly {
            $.slot := position
        }
    }

    /// @notice Initializes the MultisigStrategyStorage
    /// @param multiSig_ The address of the multi-signature wallet
    function initialize(address multiSig_) internal {
        MultisigStrategyStorage storage $ = fetch();
        $.multiSig = multiSig_;
    }
}
