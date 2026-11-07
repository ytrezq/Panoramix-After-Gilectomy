// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IDSTrustService {
    function TRANSFER_AGENT() external view returns (uint8);

    function setRole(address account, uint8 role) external;
    function setServiceOwner(address owner) external;
}
