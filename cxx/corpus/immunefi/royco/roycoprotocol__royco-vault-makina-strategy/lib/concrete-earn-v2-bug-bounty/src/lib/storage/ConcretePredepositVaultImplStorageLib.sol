// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ConcretePredepositVaultImplStorageLib {
    /// @dev keccak256(abi.encode(uint256(keccak256("concrete.storage.ConcretePredepositVaultImplStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ConcretePredepositVaultImplStorageLocation =
        0x79a41852d663cc56b526f07fa21bffd982d544af4842ed752b028e7ab747dc00;

    /// @custom:storage-location erc7201:concrete.storage.ConcretePredepositVaultImplStorage
    struct ConcretePredepositVaultImplStorage {
        /// @dev mapping of user address to their locked shares
        mapping(address => uint256) lockedShares;
        /// @dev whether self claims are enabled (true) or disabled (false)
        bool selfClaimsEnabled;
        /// @dev address of the OApp contract used for cross-chain messaging
        address oapp;
    }

    /**
     * @notice Fetches the storage struct for ConcretePredepositVaultImpl
     */
    function fetch() internal pure returns (ConcretePredepositVaultImplStorage storage $) {
        assembly {
            $.slot := ConcretePredepositVaultImplStorageLocation
        }
    }
}
