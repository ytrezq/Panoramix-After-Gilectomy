// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.24;

contract IdentityNetworkMock {
    mapping(address => bool) public members;

    function isMember(address usr) external view returns (bool) {
        return members[usr];
    }
}
