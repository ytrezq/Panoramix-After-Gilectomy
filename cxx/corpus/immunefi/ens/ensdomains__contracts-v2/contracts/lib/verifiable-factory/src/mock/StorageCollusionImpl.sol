// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract StorageConflictImplementation is UUPSUpgradeable, OwnableUpgradeable {
    // deliberate storage layout conflict
    address public conflictAddress; // previously was 'registeredAddresses' mapping in MockRegistry
    uint256 public conflictValue; // previously was 'version' constant

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        conflictAddress = owner;
        conflictValue = 999;
    }

    function dangerousMethod() external {
        // manipulate critical storage slots
        assembly {
            sstore(0, 0xdeadbeef)
        }
    }

    function canUpgradeFrom(address previousImplementation) external view returns (bool) {
        return true;
    }
}
