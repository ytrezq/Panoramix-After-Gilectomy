// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {IAddressesCollectionImpl} from "./IAddressesCollectionImpl.sol";

contract AddressesCollectionImplWrapper {
    IAddressesCollectionImpl public collection;

    function setCollection(address _collection) external {
        collection = IAddressesCollectionImpl(_collection);
    }

    /// @notice Allocates an address for the current chain id
    /// @param _key The key to allocating/resolving an address
    /// @param _value An address that should be allocated
    function setAddress(uint256 _chainId, string memory _key, address _value) public {
        collection.setAddress(_chainId, _key, _value);
    }

    function getAddress(uint256 _chainId, string memory _key) external view returns (address) {
        return collection.getAddress(_chainId, _key);
    }
}
