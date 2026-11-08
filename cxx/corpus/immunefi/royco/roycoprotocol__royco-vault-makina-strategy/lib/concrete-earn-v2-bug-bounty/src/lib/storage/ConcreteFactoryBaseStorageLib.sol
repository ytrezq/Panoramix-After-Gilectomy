// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EnumerableSet} from "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";

library ConcreteFactoryBaseStorageLib {
    struct ConcreteFactoryBaseStorage {
        /// @dev Set of approved implementation addresses that can be used to deploy new vaults
        // This Factory depends on EnumerableSet ordering.
        // MUST NOT call `remove`, as the order is only reliable when elements are never removed.
        EnumerableSet.AddressSet implementations;
        /// @dev Mapping of implementation addresses to boolean values indicating if the implementation is blocked
        mapping(uint64 version => bool blocked) blocked;
        /// @dev Mapping indicating if a version is migratable to another version
        mapping(uint64 fromVersion => mapping(uint64 toVersion => bool)) migratable;
        /// @dev Mapping to track deployed vaults from this factory
        mapping(address => bool) vaults;
    }

    // keccak256(abi.encode(uint256(keccak256("concrete.storage.ConcreteFactoryBaseStorage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant CONCRETE_FACTORY_STORAGE_SLOT = 0x8e455bed11907189c537a36ae6131c14495d217d4f7af335ce892f553df45a00;

    function fetch() internal pure returns (ConcreteFactoryBaseStorage storage concreteFactoryBaseStorage) {
        bytes32 slot = CONCRETE_FACTORY_STORAGE_SLOT;
        assembly {
            concreteFactoryBaseStorage.slot := slot
        }
    }
}
