// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IRoleStore {
    function hasRole(address account, bytes32 roleKey) external view returns (bool);
}