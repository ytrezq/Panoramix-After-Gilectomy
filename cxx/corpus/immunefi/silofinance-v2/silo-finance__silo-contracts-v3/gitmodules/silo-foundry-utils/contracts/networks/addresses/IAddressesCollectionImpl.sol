// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

interface IAddressesCollectionImpl {
    function setAddress(uint256 _chainId, string memory _key, address _value) external returns (address);
    function getAddress(uint256 _chainId, string memory _key) external view returns (address);
}
