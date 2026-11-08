// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IKATVault } from "./interfaces/IKATVault.sol";

/**
 * @title KATOFTAdapterStorageLayout
 * @notice Storage layout for the upgradeable OFT adapter contracts
 * @dev Respects the namespaced storage layout standard defined in EIP 7201
 */
abstract contract KATOFTAdapterStorageLayout {
    /**
     * @custom:storage-location erc7201:kat.oft.adapter
     * @dev Storage layout of the OFTAdapaterUpgradeable contracts
     * @param vault The KATVault contract that holds and transfers KAT tokens
     */
    struct OftAdapterStorage {
        IKATVault vault;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256(bytes("kat.oft.adapter"))) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant OFT_ADAPTER_STORAGE_LOCATION =
        0x34572c60b90a0db5bd1af576c5408232923eb6d59cf3a8bd5cfb886656576700;

    /// @dev Returns a storage pointer to the `OftAdapterStorage` struct in storage.
    function _getStorage() internal pure returns (OftAdapterStorage storage $) {
        assembly {
            $.slot := OFT_ADAPTER_STORAGE_LOCATION
        }
    }
}
