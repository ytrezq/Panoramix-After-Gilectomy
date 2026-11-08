// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library ACL_OZ_5_2_0_Lib {
    using EnumerableSet for EnumerableSet.AddressSet;
    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.AccessControl")) - 1)) & ~bytes32(uint256(0xff))

    bytes32 private constant AccessControlStorageLocation =
        0x02dd7bc7dec4dceedda775e58dd541e08a116c6c53815c0bd028192f7b626800;

    function __getAccessControlStorage()
        private
        pure
        returns (AccessControlUpgradeable.AccessControlStorage storage $)
    {
        assembly {
            $.slot := AccessControlStorageLocation
        }
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.AccessControlEnumerable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AccessControlEnumerableStorageLocation =
        0xc1f6fe24621ce81ec5827caf0253cadb74709b061630e6b55e82371705932000;

    function __getAccessControlEnumerableStorage()
        private
        pure
        returns (AccessControlEnumerableUpgradeable.AccessControlEnumerableStorage storage $)
    {
        assembly {
            $.slot := AccessControlEnumerableStorageLocation
        }
    }

    /**
     * @dev Overload {AccessControl-_grantRole} to track enumerable memberships
     */
    function _grantRole(bytes32 role, address account, address sender) internal returns (bool) {
        AccessControlEnumerableUpgradeable.AccessControlEnumerableStorage storage $ace =
            __getAccessControlEnumerableStorage();
        bool granted = __grantRole(role, account, sender);
        if (granted) {
            $ace._roleMembers[role].add(account);
        }
        return granted;
    }

    function __grantRole(bytes32 role, address account, address sender) private returns (bool) {
        AccessControlUpgradeable.AccessControlStorage storage $ac = __getAccessControlStorage();
        if (!__hasRole(role, account)) {
            $ac._roles[role].hasRole[account] = true;
            emit IAccessControl.RoleGranted(role, account, sender);
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function __hasRole(bytes32 role, address account) private view returns (bool) {
        AccessControlUpgradeable.AccessControlStorage storage $ac = __getAccessControlStorage();
        return $ac._roles[role].hasRole[account];
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function __getRoleAdmin(bytes32 role) private view returns (bytes32) {
        AccessControlUpgradeable.AccessControlStorage storage $ac = __getAccessControlStorage();
        return $ac._roles[role].adminRole;
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        AccessControlUpgradeable.AccessControlStorage storage $ac = __getAccessControlStorage();
        bytes32 previousAdminRole = __getRoleAdmin(role);
        $ac._roles[role].adminRole = adminRole;
        emit IAccessControl.RoleAdminChanged(role, previousAdminRole, adminRole);
    }
}
