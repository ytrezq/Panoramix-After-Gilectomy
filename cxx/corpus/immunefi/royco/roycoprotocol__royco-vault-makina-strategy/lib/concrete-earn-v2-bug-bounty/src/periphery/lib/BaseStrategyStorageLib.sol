// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

library BaseStrategyStorageLib {
    /// @dev keccak256(abi.encode(uint256(keccak256("concrete.storage.BaseStrategyStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BaseStrategyStorageLocation =
        0xe84a5801edbad7de8e77ad0d2d730a53019bf3035b3c2f0ee45940fd7a547900;

    /// @custom:storage-location erc7201:concrete.storage.BaseStrategyStorage
    struct BaseStrategyStorage {
        /// @dev The underlying asset token
        address asset;
        /// @dev The single authorized vault address
        address vault;
        /// @dev The maximum amount that can be withdrawn from the strategy
        uint256 maxWithdraw;
    }

    /**
     * @dev Get the storage struct
     */
    function fetch() internal pure returns (BaseStrategyStorage storage $) {
        assembly {
            $.slot := BaseStrategyStorageLocation
        }
    }
}
