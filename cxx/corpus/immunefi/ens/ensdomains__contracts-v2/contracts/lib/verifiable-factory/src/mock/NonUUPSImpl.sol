// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Does NOT inherit from UUPSUpgradeable
contract NonUUPSImpl {
    uint256 public value;

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}
