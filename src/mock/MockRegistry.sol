// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IProxyAuthorization} from "../IProxyAuthorization.sol";

/**
 * @title MockRegistry
 * @dev Simulates a registry implementation for testing
 */
contract MockRegistry is UUPSUpgradeable, OwnableUpgradeable, IProxyAuthorization {
    mapping(address => bool) public registeredAddresses;
    uint256 public constant version = 1;

    // ### Events
    event AddressRegistered(address indexed account);
    event AddressUnregistered(address indexed account);

    function canUpgradeFrom(address previousImplementation) external view virtual returns (bool) {
        return true;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner); // Initialize Ownable
        __UUPSUpgradeable_init();
    }

    function register(address account) external onlyOwner {
        require(!registeredAddresses[account], "Address already registered");
        registeredAddresses[account] = true;
        emit AddressRegistered(account);
    }

    function unregister(address account) external onlyOwner {
        require(registeredAddresses[account], "Address not registered");
        registeredAddresses[account] = false;
        emit AddressUnregistered(account);
    }

    function isRegistered(address account) external view returns (bool) {
        return registeredAddresses[account];
    }

    function getRegistryVersion() public pure virtual returns (uint256) {
        return version;
    }
}
