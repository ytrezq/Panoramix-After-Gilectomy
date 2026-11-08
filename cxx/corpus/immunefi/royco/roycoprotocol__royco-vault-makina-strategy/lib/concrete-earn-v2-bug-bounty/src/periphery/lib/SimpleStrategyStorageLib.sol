// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

library SimpleStrategyStorageLib {
    /// @dev keccak256(abi.encode(uint256(keccak256("concrete.storage.SimpleStrategyStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SimpleStrategyStorageLocation =
        0x1072a7caa0c9466a5663f14b684022d58172ece341afae9fa84ed6b270157700;

    /// @custom:storage-location erc7201:concrete.storage.SimpleStrategyStorage
    struct SimpleStrategyStorage {
        /// @dev The allocated amount for the single vault
        uint256 allocated;
    }

    /**
     * @dev Get the storage struct
     */
    function fetch() internal pure returns (SimpleStrategyStorage storage $) {
        assembly {
            $.slot := SimpleStrategyStorageLocation
        }
    }
}
