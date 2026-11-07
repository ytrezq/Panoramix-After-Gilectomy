// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {IACL} from "../interfaces/IACL.sol";
import {IImmutableOwnableTrait} from "../interfaces/base/IImmutableOwnableTrait.sol";
import {ACL} from "../market/ACL.sol";

contract ACLUnitTest is Test {
    ACL acl;
    address owner;
    address user1;
    address user2;
    bytes32 constant ROLE_1 = keccak256("ROLE_1");
    bytes32 constant ROLE_2 = keccak256("ROLE_2");

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        acl = new ACL(owner);
    }

    /// @notice U:[ACL-1]: Constructor works correctly
    function test_U_ACL_01_constructor_works_correctly() public view {
        assertEq(acl.owner(), owner);
        assertEq(acl.getRoles().length, 0);

        assertEq(acl.getConfigurator(), owner);
        assertTrue(acl.isConfigurator(owner));
        assertFalse(acl.isConfigurator(address(this)));
    }

    /// @notice U:[ACL-2]: `grantRole` works correctly
    function test_U_ACL_02_grantRole_works_correctly() public {
        // Only owner can grant roles
        vm.expectRevert(
            abi.encodeWithSelector(IImmutableOwnableTrait.CallerIsNotOwnerException.selector, address(this))
        );
        acl.grantRole(ROLE_1, user1);

        // Test role granting
        vm.startPrank(owner);

        // First grant creates role and grants it
        vm.expectEmit(true, true, true, true);
        emit IACL.CreateRole(ROLE_1);
        vm.expectEmit(true, true, true, true);
        emit IACL.GrantRole(ROLE_1, user1);
        acl.grantRole(ROLE_1, user1);

        assertTrue(acl.hasRole(ROLE_1, user1));
        assertFalse(acl.hasRole(ROLE_1, user2));

        // Second grant of same role only emits GrantRole
        vm.expectEmit(true, true, true, true);
        emit IACL.GrantRole(ROLE_1, user2);
        acl.grantRole(ROLE_1, user2);

        assertTrue(acl.hasRole(ROLE_1, user1));
        assertTrue(acl.hasRole(ROLE_1, user2));

        // Test roles list
        bytes32[] memory roles = acl.getRoles();
        assertEq(roles.length, 1);
        assertEq(roles[0], ROLE_1);

        // Test role holders
        address[] memory roleHolders = acl.getRoleHolders(ROLE_1);
        assertEq(roleHolders.length, 2);
        assertTrue(roleHolders[0] == user1 || roleHolders[1] == user1);
        assertTrue(roleHolders[0] == user2 || roleHolders[1] == user2);

        // Test multiple roles
        vm.expectEmit(true, true, true, true);
        emit IACL.CreateRole(ROLE_2);
        vm.expectEmit(true, true, true, true);
        emit IACL.GrantRole(ROLE_2, user1);
        acl.grantRole(ROLE_2, user1);

        roles = acl.getRoles();
        assertEq(roles.length, 2);
        assertTrue(roles[0] == ROLE_1 || roles[1] == ROLE_1);
        assertTrue(roles[0] == ROLE_2 || roles[1] == ROLE_2);

        vm.stopPrank();
    }

    /// @notice U:[ACL-3]: `revokeRole` works correctly
    function test_U_ACL_03_revokeRole_works_correctly() public {
        // Setup roles
        vm.startPrank(owner);
        acl.grantRole(ROLE_1, user1);
        acl.grantRole(ROLE_1, user2);
        acl.grantRole(ROLE_2, user1);
        vm.stopPrank();

        // Only owner can revoke roles
        vm.expectRevert(
            abi.encodeWithSelector(IImmutableOwnableTrait.CallerIsNotOwnerException.selector, address(this))
        );
        acl.revokeRole(ROLE_1, user1);

        vm.startPrank(owner);

        // Test role revocation
        vm.expectEmit(true, true, true, true);
        emit IACL.RevokeRole(ROLE_1, user1);
        acl.revokeRole(ROLE_1, user1);

        assertFalse(acl.hasRole(ROLE_1, user1));
        assertTrue(acl.hasRole(ROLE_1, user2));
        assertTrue(acl.hasRole(ROLE_2, user1));

        // Second revoke should be no-op (no event)
        acl.revokeRole(ROLE_1, user1);

        // Revoking non-existent role should be no-op
        acl.revokeRole(keccak256("NON_EXISTENT_ROLE"), user1);

        // Role remains in roles list even if no holders
        acl.revokeRole(ROLE_1, user2);
        bytes32[] memory roles = acl.getRoles();
        assertEq(roles.length, 2);
        assertTrue(roles[0] == ROLE_1 || roles[1] == ROLE_1);
        assertTrue(roles[0] == ROLE_2 || roles[1] == ROLE_2);

        vm.stopPrank();
    }
}
