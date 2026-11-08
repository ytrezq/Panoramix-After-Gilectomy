// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ConcreteAsyncVaultImplStorageLib {
    /// @dev keccak256(abi.encode(uint256(keccak256("concrete.storage.ConcreteAsyncVaultImplStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ConcreteAsyncVaultImplStorageLocation =
        0x0ada5b606f7944319310c49c0f9f30d6272793a991bd2b9c3db8049867746700;

    /// @custom:storage-location erc7201:concrete.storage.ConcreteAsyncVaultImplStorage
    struct ConcreteAsyncVaultImplStorage {
        // Current epoch ID for async withdrawals
        uint256 latestEpochID;
        // Assets available for past withdrawals (denominated in underlying asset)
        uint256 pastEpochsUnclaimedAssets;
        // Mapping from epoch ID to total shares requested in that epoch
        mapping(uint256 => uint256) totalRequestedSharesPerEpoch;
        // Mapping from user address to epoch ID to shares requested
        mapping(address user => mapping(uint256 epochID => uint256 shares)) userEpochRequests;
        // Mapping from epoch ID to share price when that epoch was processed
        mapping(uint256 => uint256) epochPricePerSharePlusOne;
        // Whether the queue is active
        bool isQueueActive;
    }

    /**
     * @dev Returns the storage struct for ConcreteAsyncVaultImpl
     */
    function fetch() internal pure returns (ConcreteAsyncVaultImplStorage storage $) {
        assembly {
            $.slot := ConcreteAsyncVaultImplStorageLocation
        }
    }
}
