// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;
import { AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import { IAccessControlManager } from "./interfaces/IAccessControlManager.sol";

/**
 * @title Strata Access Control Contract
 * @dev This contract is a wrapper of OpenZeppelin AccessControl
 *		extending it in a way to standartize access control
 *		within Strata Smart Contract Ecosystem
 */
contract AccessControlManager is AccessControl, IAccessControlManager {
    /// @notice Emitted when an account is given a permission to a certain contract function
    /// @dev If contract address is 0x000..0 this means that the account is a default admin of this function and
    /// can call any contract function with this signature
    event PermissionGranted(address account, address contractAddress, bytes4 sel);

    /// @notice Emitted when an account is revoked a permission to a certain contract function
    event PermissionRevoked(address account, address contractAddress, bytes4 sel);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @notice Gives a function call permission to one single account
     * @dev this function can be called only from Role Admin or DEFAULT_ADMIN_ROLE
     * @param contractAddress address of contract for which call permissions will be granted
     * @dev if contractAddress is zero address, the account can access the specified function
     *      on **any** contract managed by this ACL
     * @param sel signature e.g. "functionName(uint256,bool)"
     * @param accountToPermit account that will be given access to the contract function
     * @custom:event Emits a {RoleGranted} and {PermissionGranted} events.
     */
    function grantCall(address contractAddress, bytes4 sel, address accountToPermit) public {
        bytes32 role = roleFor(contractAddress, sel);
        grantRole(role, accountToPermit);
        emit PermissionGranted(accountToPermit, contractAddress, sel);
    }

    /**
     * @notice Revokes an account's permission to a particular function call
     * @dev this function can be called only from Role Admin or DEFAULT_ADMIN_ROLE
     * 		May emit a {RoleRevoked} event.
     * @param contractAddress address of contract for which call permissions will be revoked
     * @param sel signature e.g. "functionName(uint256,bool)"
     * @custom:event Emits {RoleRevoked} and {PermissionRevoked} events.
     */
    function revokeCall(
        address contractAddress,
        bytes4 sel,
        address accountToRevoke
    ) public {
        bytes32 role = roleFor(contractAddress, sel);
        revokeRole(role, accountToRevoke);
        emit PermissionRevoked(accountToRevoke, contractAddress, sel);
    }

    /**
     * @notice Verifies if the given account can call a contract's guarded function
     * @dev Since restricted contracts using this function as a permission hook, we can get contracts address with msg.sender
     * @param account for which call permissions will be checked
     * @param sel restricted function signature
     * @return false if the user account cannot call the particular contract function
     *
     */
    function isAllowedToCall(address account, bytes4 sel) public view returns (bool) {
        address target = msg.sender;
        bytes32 role = roleFor(target, sel);

        if (hasRole(role, account)) {
            return true;
        }
        // Check global permission
        role = roleFor(address(0), sel);
        return hasRole(role, account);
    }

    /**
     * @notice Verifies if the given account can call a contract's guarded function
     * @dev This function is used as a view function to check permissions rather than contract hook for access restriction check.
     * @param account for which call permissions will be checked against
     * @param contractAddress address of the restricted contract
     * @param sel signature of the restricted function e.g. "functionName(uint256,bool)"
     * @return false if the user account cannot call the particular contract function
     */
    function hasPermission(
        address account,
        address contractAddress,
        bytes4 sel
    ) public view returns (bool) {
        bytes32 role = roleFor(contractAddress, sel);
        return hasRole(role, account);
    }

    /**
     * @notice Helper function to generate role for a given contract address and contract function
     * @dev Address in the high 20 bytes and selector in the low 4 bytes, 8 unused bytes in the middle
     * [ address:20B ] [empty: 0s:8B ][ selector:4B ]  => 32 bytes
     * Split:
     * sel = bytes4(uint32(uint256(role))); // low 4 bytes
     * contractAddress = address(uint160(uint256(role >> 96))); // high 20 bytes
     * @dev All arguments must be non-zero. The function will revert if either contractAddress or sel is zero.
    */
    function roleFor(address contractAddress, bytes4 sel) internal pure returns (bytes32 role) {
        require(contractAddress != address(0) && sel != bytes4(0), "StrictPermissionOnly");
        role = (bytes32(uint256(uint160(contractAddress))) << 96) | bytes32(uint256(uint32(sel)));
    }
}
