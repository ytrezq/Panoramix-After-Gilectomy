// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Simple interface to communicate with the KATVault contract
interface IKATVault {
    function transferKat(address to, uint256 amount) external;
}
