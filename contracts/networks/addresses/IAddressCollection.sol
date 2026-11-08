// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

interface IAddressCollection {
    function getAddress(uint256 _chainId, string memory _key) external returns (address);
}
