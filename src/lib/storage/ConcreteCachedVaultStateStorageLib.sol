// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/types/Time.sol)
pragma solidity ^0.8.24;

library ConcreteCachedVaultStateStorageLib {
    /// @custom:storage-location erc7201:openzeppelin.storage.ConcreteTokenizedVaultStorage
    struct ConcreteCachedVaultStateStorage {
        /// @dev Store last total assets of the vault at specific timestamp
        uint256 cachedTotalAssets;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("concrete.storage.ConcreteCachedVaultStateStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ConcreteCachedVaultStateStorageLocation =
        0x31b60059595cae2ebab32b53f301cf68fb9c4eef322a90dbc8487ddf3a197900;

    function fetch() internal pure returns (ConcreteCachedVaultStateStorage storage $) {
        assembly {
            $.slot := ConcreteCachedVaultStateStorageLocation
        }
    }
}
