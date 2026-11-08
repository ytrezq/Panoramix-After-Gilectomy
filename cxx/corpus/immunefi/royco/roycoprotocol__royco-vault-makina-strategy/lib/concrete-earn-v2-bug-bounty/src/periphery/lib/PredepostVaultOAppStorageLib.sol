// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library PredepostVaultOAppStorageLib {
    /// @dev keccak256(abi.encode(uint256(keccak256("concrete.storage.PredepostVaultOAppStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PredepostVaultOAppStorageLocation =
        0x6a67ff7c8e833a22db547ce7a4196d06847dcb45e7570c468989fd0e8693fc00;

    /// @custom:storage-location erc7201:concrete.storage.PredepostVaultOAppStorage
    struct PredepostVaultOAppStorage {
        /// @dev The vault that is authorized to use this OApp
        address vault;
        /// @dev The destination endpoint ID
        uint32 dstEid;
    }

    /**
     * @notice Fetches the storage struct for PredepostVaultOApp
     */
    function fetch() internal pure returns (PredepostVaultOAppStorage storage $) {
        assembly {
            $.slot := PredepostVaultOAppStorageLocation
        }
    }
}
