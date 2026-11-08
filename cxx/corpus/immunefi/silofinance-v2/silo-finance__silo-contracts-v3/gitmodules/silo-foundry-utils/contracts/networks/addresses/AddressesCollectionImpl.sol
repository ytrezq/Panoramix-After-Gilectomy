// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

contract AddressesCollectionImpl {
    // network => key => value
    mapping(uint256 => mapping(string => address)) public getAddress;

    /// @notice Allocates an address for the current chain id
    /// @param _key The key to allocating/resolving an address
    /// @param _value An address that should be allocated
    function setAddress(uint256 _chainId, string memory _key, address _value) public {
        getAddress[_chainId][_key] = _value;
    }
}
