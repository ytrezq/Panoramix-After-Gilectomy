// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IDataStore {
    function getAddress(bytes32 key) external view returns (address);
    function getUint(bytes32 key) external view returns (uint256);
}