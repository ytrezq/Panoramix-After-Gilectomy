// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./CapyfiBaseTest.sol"; 
import {Whitelist} from "src/contracts/Access/Whitelist.sol"; 
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

// ---------------------------------------------------------------------
// Whitelist Tests
// ---------------------------------------------------------------------
contract WhitelistTest is CapyfiBaseTest {
    /// @notice Verifies that the admin has the admin role by default
    function testInitialAdminRole() public view {
        // admin was set during initialization
        bool isAdminRole = whitelist.hasRole(whitelist.DEFAULT_ADMIN_ROLE(), admin);
        assertTrue(isAdminRole, "admin should have DEFAULT_ADMIN_ROLE");
    }

    /// @notice Ensures an admin can add a user to the whitelist
    function testAddUserToWhitelist() public {
        // user1 is not whitelisted
        assertFalse(whitelist.isWhitelisted(user1));

        // admin adds user1
        vm.startPrank(admin);
        whitelist.grantRole(whitelist.WHITELISTED_ROLE(), user1);
        vm.stopPrank();

        // Now user1 is whitelisted
        assertTrue(whitelist.isWhitelisted(user1));
    }

    /// @notice Ensures a non-admin cannot add a user to the whitelist
    function testNonAdminCannotAddWhitelist() public {
        // user2 tries
        vm.startPrank(user2);
        try whitelist.grantRole(whitelist.WHITELISTED_ROLE(), user1) {
            assert(false); // Should not succeed
        } catch {
            // Expected to revert
        }
        vm.stopPrank();

        // still not whitelisted
        assertFalse(whitelist.isWhitelisted(user1));
    }

    /// @notice Ensures an admin can remove a user from the whitelist
    function testRemoveWhitelisted() public {
        // admin whitelists user1
        vm.startPrank(admin);
        whitelist.grantRole(whitelist.WHITELISTED_ROLE(), user1);
        assertTrue(whitelist.isWhitelisted(user1));

        // remove user1
        whitelist.revokeRole(whitelist.WHITELISTED_ROLE(), user1);
        vm.stopPrank();

        // user1 no longer whitelisted
        assertFalse(whitelist.isWhitelisted(user1));
    }

    /// @notice Ensures only an existing admin can add a new admin
    function testOnlyAdminCanAddAdmin() public {
        // user2 tries to add user1 as a new admin => revert
        vm.startPrank(user2);
        try whitelist.grantRole(whitelist.DEFAULT_ADMIN_ROLE(), user1) {
            assert(false); // Should not succeed
        } catch {
            // Expected to revert
        }
        vm.stopPrank();

        // admin can successfully add user1 as an admin
        vm.startPrank(admin);
        whitelist.grantRole(whitelist.DEFAULT_ADMIN_ROLE(), user1);
        vm.stopPrank();

        // Check the role
        bool hasAdminRole = whitelist.hasRole(whitelist.DEFAULT_ADMIN_ROLE(), user1);
        assertTrue(hasAdminRole, "user1 should have DEFAULT_ADMIN_ROLE now");
    }

    /// @notice Verifies that a newly added admin can also add addresses to the whitelist
    function testNewAdminCanAddWhitelisted() public {
        // admin adds user2 as a new admin
        vm.startPrank(admin);
        whitelist.grantRole(whitelist.DEFAULT_ADMIN_ROLE(), user2);
        vm.stopPrank();

        // user2 is now an admin and can add user1 to the whitelist
        vm.startPrank(user2);
        whitelist.grantRole(whitelist.WHITELISTED_ROLE(), user1);
        vm.stopPrank();
        assertTrue(whitelist.isWhitelisted(user1), "user1 should be whitelisted by user2");
    }

    /// @notice Ensures only a admin can remove another admin
    function testOnlyAdminCanRemoveAdmin() public {
        // admin grants user1 the admin role
        vm.startPrank(admin);
        whitelist.grantRole(whitelist.DEFAULT_ADMIN_ROLE(), user1);
        vm.stopPrank();

        // user2 (non-admin) tries to remove admin from user1 => revert
        vm.startPrank(user2);
        try whitelist.revokeRole(whitelist.DEFAULT_ADMIN_ROLE(), user1) {
            assert(false); // Should not succeed
        } catch {
            // Expected to revert
        }
        vm.stopPrank();

        // admin can remove user1 as an admin
        vm.startPrank(admin);
        whitelist.revokeRole(whitelist.DEFAULT_ADMIN_ROLE(), user1);
        vm.stopPrank();
        bool stillAdmin = whitelist.hasRole(whitelist.DEFAULT_ADMIN_ROLE(), user1);
        assertFalse(stillAdmin, "user1 should no longer have DEFAULT_ADMIN_ROLE");
    }
    
    /// @notice Test the activation and deactivation functionality
    function testActivateAndDeactivateWhitelist() public {
        // Whitelist should be active by default
        assertTrue(whitelist.isActive(), "Whitelist should be active by default");
        
        // Deactivate whitelist
        vm.prank(admin);
        whitelist.deactivate();
        
        // Check deactivated state
        assertFalse(whitelist.isActive(), "Whitelist should be deactivated");
        
        // Reactivate whitelist
        vm.prank(admin);
        whitelist.activate();
        
        // Check activated state
        assertTrue(whitelist.isActive(), "Whitelist should be activated again");
    }
    
    /// @notice Test upgrading the implementation
    function testUpgradeImplementation() public {
        // Create a new implementation
        vm.startPrank(admin);
        Whitelist newImplementation = new Whitelist();
        
        // Get initial proxy implementation
        // address initialImplementation = address(whitelistImplementation);
        
        // Perform the upgrade - we don't test for the event since it's internal
        whitelist.upgradeTo(address(newImplementation));
        vm.stopPrank();
        
        // Verify whitelist still functions after upgrade
        vm.startPrank(admin);
        whitelist.grantRole(whitelist.WHITELISTED_ROLE(), user1);
        vm.stopPrank();
        assertTrue(whitelist.isWhitelisted(user1), "Whitelist should still function after upgrade");
    }
    
    /// @notice Test that non-admins cannot upgrade the implementation
    function testNonAdminCannotUpgrade() public {
        // Create a new implementation
        Whitelist newImplementation = new Whitelist();
        
        // user1 tries to upgrade => should revert
        vm.prank(user1);
        vm.expectRevert(); // The exact error depends on OpenZeppelin implementation
        whitelist.upgradeTo(address(newImplementation));
    }
    
    /// @notice Test isAdmin function
    function testIsAdminFunction() public {
        // Check that admin is detected as admin
        assertTrue(whitelist.isAdmin(admin), "Admin should be detected as admin");
        
        // Check that user1 is initially not an admin
        assertFalse(whitelist.isAdmin(user1), "User1 should not be admin initially");
        
                // Add user1 as admin
        vm.startPrank(admin);
        whitelist.grantRole(whitelist.DEFAULT_ADMIN_ROLE(), user1);
        vm.stopPrank();

        // Now user1 should be an admin
        assertTrue(whitelist.isAdmin(user1), "User1 should be admin after granting role");
    }

    function testRemovingAndRestoringAdminRole() public {
        // This test verifies what happens when an admin removes their DEFAULT_ADMIN_ROLE
        
        // First, verify admin is currently the only admin with the role
        uint256 adminCount = whitelist.getRoleMemberCount(whitelist.DEFAULT_ADMIN_ROLE());
        assertEq(adminCount, 1, "There should be exactly one admin initially");
        
        // First, let's add another admin so we can test behavior
        vm.startPrank(admin);
        whitelist.grantRole(whitelist.DEFAULT_ADMIN_ROLE(), user1);
        vm.stopPrank();
        
        // Verify we now have two admins
        adminCount = whitelist.getRoleMemberCount(whitelist.DEFAULT_ADMIN_ROLE());
        assertEq(adminCount, 2, "Admin count should be 2 after adding user1");
        
        // Admin removes their own DEFAULT_ADMIN_ROLE
        vm.startPrank(admin);
        whitelist.revokeRole(whitelist.DEFAULT_ADMIN_ROLE(), admin);
        vm.stopPrank();
        
        // Verify the admin count is now 1
        adminCount = whitelist.getRoleMemberCount(whitelist.DEFAULT_ADMIN_ROLE());
        assertEq(adminCount, 1, "Admin count should be 1 after admin removes their role");
        assertFalse(whitelist.isAdmin(admin), "Admin should no longer have DEFAULT_ADMIN_ROLE");
        assertTrue(whitelist.isAdmin(user1), "User1 should still have DEFAULT_ADMIN_ROLE");
        
        // Admin no longer has DEFAULT_ADMIN_ROLE after removing themselves
        assertFalse(whitelist.hasRole(whitelist.DEFAULT_ADMIN_ROLE(), admin), "Admin should no longer have DEFAULT_ADMIN_ROLE");
        
                // The other admin (user1) can add the original admin back
        vm.startPrank(user1);
        whitelist.grantRole(whitelist.DEFAULT_ADMIN_ROLE(), admin);
        vm.stopPrank();

        // Now the original admin should have DEFAULT_ADMIN_ROLE again
        assertTrue(whitelist.isAdmin(admin), "Admin should have DEFAULT_ADMIN_ROLE again after user1 adds them");
    }

    function testRevertWhenNonAdminAttemptsUpgrade() public {
        // Create a new implementation for the upgrade attempt
        Whitelist newImplementation = new Whitelist();
        
        // Non-admin attempts to upgrade
        address nonAdmin = address(0x3);
        
        vm.startPrank(nonAdmin);
        // The UUPSUpgradeable uses _authorizeUpgrade with onlyRole(DEFAULT_ADMIN_ROLE) modifier
        // When called through upgradeTo, it will revert with the AccessControl error
        vm.expectRevert();
        whitelist.upgradeTo(address(newImplementation));
        vm.stopPrank();
    }

    /// @notice Tests that the onlyWhitelisted modifier properly restricts access
    function testOnlyWhitelistedModifier() public {
        // Deploy WhitelistTester contract with correct initialization
        WhitelistTester tester = new WhitelistTester();
        
        // Initialize via constructor
        bytes memory initData = abi.encodeWithSelector(
            Whitelist.initialize.selector,
            admin
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(tester),
            initData
        );
        tester = WhitelistTester(address(proxy));
        
        // Initially user1 is not whitelisted, attempt to call restricted function
        vm.prank(user1);
        vm.expectRevert("WhitelistAccess: caller does not have the WHITELISTED_ROLE role");
        tester.restrictedFunction();
        
        // Add user1 to whitelist
        vm.startPrank(admin);
        tester.grantRole(tester.WHITELISTED_ROLE(), user1);
        vm.stopPrank();

        // User1 should now be able to call the restricted function
        vm.prank(user1);
        tester.restrictedFunction();
        assertTrue(tester.functionCalled(), "Function should have been called successfully");
        
        // Remove user1 from whitelist
        vm.startPrank(admin);
        tester.revokeRole(tester.WHITELISTED_ROLE(), user1);
        vm.stopPrank();
        
        // User1 should no longer be able to call the restricted function
        vm.prank(user1);
        vm.expectRevert("WhitelistAccess: caller does not have the WHITELISTED_ROLE role");
        tester.restrictedFunction();
    }
}

/// @notice Contract that inherits from Whitelist to test the onlyWhitelisted modifier
contract WhitelistTester is Whitelist {
    bool public functionCalled;
    
    /// @notice Function that uses the onlyWhitelisted modifier from Whitelist
    function restrictedFunction() external onlyWhitelisted {
        functionCalled = true;
    }
}