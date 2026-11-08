// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import {AccessControlEnumerableUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {WhitelistAccess} from "./WhitelistAccess.sol";

/**
 * @title Whitelist
 * @dev Whitelist contract with UUPS upgradeability pattern
 */
contract Whitelist is 
    Initializable, 
    AccessControlEnumerableUpgradeable, 
    UUPSUpgradeable,
    WhitelistAccess 
{
    // Constants - WHITELISTED_ROLE 
    /// @dev Role identifier for addresses that have been whitelisted to access restricted functions
    bytes32 public constant WHITELISTED_ROLE = keccak256("WHITELISTED_ROLE");
    
    // State variables
    bool private _active;
    
    // Custom errors
    error WhitelistAlreadyActive();
    error WhitelistAlreadyInactive();
    
    // Events
    /// @dev Emitted when the whitelist is activated by an admin
    /// @param admin The address of the admin who activated the whitelist
    event WhitelistActivated(address indexed admin);
    
    /// @dev Emitted when the whitelist is deactivated by an admin
    /// @param admin The address of the admin who deactivated the whitelist
    event WhitelistDeactivated(address indexed admin);
    
    /// @dev Emitted when the contract implementation is upgraded
    /// @param implementation The address of the new implementation contract
    event WhitelistUpgraded(address indexed implementation);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(address admin) public initializer {
        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        // Set DEFAULT_ADMIN_ROLE as the admin role for WHITELISTED_ROLE
        _setRoleAdmin(WHITELISTED_ROLE, DEFAULT_ADMIN_ROLE);
        
        // Only grant DEFAULT_ADMIN_ROLE 
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        
        // Set active state to true
        _active = true;
    }

    /**
     * @dev Restricts function to admin only
     */
    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "WhitelistAccess: caller does not have the DEFAULT_ADMIN_ROLE"
        );
        _;
    }

    /**
     * @dev Restricts function to whitelisted users only
     */
    modifier onlyWhitelisted() {
        require(
            hasRole(WHITELISTED_ROLE, msg.sender), 
            "WhitelistAccess: caller does not have the WHITELISTED_ROLE role"
        );
        _;
    }

    // External functions

    /**
     * @notice Check if the whitelist is active
     * @return Boolean indicating if the whitelist is active
     */
    function isActive() external view override returns (bool) {
        return _active;
    }
    
    /**
     * @notice Activate the whitelist, enforcing whitelist checks
     * @dev Can only be called by an admin
     */
    function activate() external onlyAdmin {
        if (_active) revert WhitelistAlreadyActive();
        _active = true;
        emit WhitelistActivated(msg.sender);
    }
    
    /**
     * @notice Deactivate the whitelist, allowing all accounts to pass checks
     * @dev Can only be called by an admin
     */
    function deactivate() external onlyAdmin {
        if (!_active) revert WhitelistAlreadyInactive();
        _active = false;
        emit WhitelistDeactivated(msg.sender);
    }

    // Public functions
    /**
     * @notice Check if an account is whitelisted
     * @param account The address to check
     * @return Boolean indicating if the address is whitelisted
     */
    function isWhitelisted(address account) public view override returns (bool) {
        return hasRole(WHITELISTED_ROLE, account);
    }

    /**
     * @notice Check if an account is an admin
     * @param account The address to check
     * @return Boolean indicating if the address is an admin
     */
    function isAdmin(address account) public view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract.
     * Called by {upgradeTo} and {upgradeToAndCall}.
     * @param newImplementation The address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        emit WhitelistUpgraded(newImplementation);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
