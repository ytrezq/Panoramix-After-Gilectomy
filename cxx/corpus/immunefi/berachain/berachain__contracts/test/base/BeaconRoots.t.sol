// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import { Mock4788BeaconRoots } from "@mock/pol/Mock4788BeaconRoots.sol";
import { BeaconRoots } from "src/libraries/BeaconRoots.sol";

/// @notice A test suite for the BeaconRoots library.
contract BeaconRootsTest is Test {
    uint64 public constant VALID_TIMESTAMP = 1_234_567_890;
    uint64 public constant INVALID_TIMESTAMP = 9_876_543_210;
    bytes32 public constant MOCK_ROOT = bytes32(uint256(0xdeadbeef));

    BeaconRootsLibraryCaller public caller;
    Mock4788BeaconRoots mockBeaconRoots;

    function setUp() public {
        caller = new BeaconRootsLibraryCaller();

        // Mock calls to BeaconRoots.ADDRESS to use our mock contract.
        vm.etch(BeaconRoots.ADDRESS, address(new Mock4788BeaconRoots()).code);
        mockBeaconRoots = Mock4788BeaconRoots(BeaconRoots.ADDRESS);
        mockBeaconRoots.setIsTimestampValid(true);
        mockBeaconRoots.setMockBeaconBlockRoot(MOCK_ROOT);
    }

    function test_IsParentBlockRootAt_Success() public {
        mockBeaconRoots.setIsTimestampValid(true);
        bool success = BeaconRoots.isParentBlockRootAt(VALID_TIMESTAMP);
        assertTrue(success, "Should return true for a valid timestamp");
    }

    function test_IsParentBlockRootAt_Failure() public {
        mockBeaconRoots.setIsTimestampValid(false);
        bool success = BeaconRoots.isParentBlockRootAt(INVALID_TIMESTAMP);
        assertFalse(success, "Should return false for an invalid timestamp");
    }

    function test_GetParentBlockRootAt_Success() public {
        mockBeaconRoots.setIsTimestampValid(true);
        bytes32 root = caller.getParentBlockRootAt(VALID_TIMESTAMP);
        assertEq(root, MOCK_ROOT, "Should return the correct root for a valid timestamp");
    }

    function test_GetParentBlockRootAt_Failure() public {
        mockBeaconRoots.setIsTimestampValid(false);
        vm.expectRevert(BeaconRoots.RootNotFound.selector);
        caller.getParentBlockRootAt(INVALID_TIMESTAMP);
    }
}

/// @dev Used to call the BeaconRoots library functions but in an external function.
contract BeaconRootsLibraryCaller {
    function getParentBlockRootAt(uint64 ts) external view returns (bytes32) {
        return BeaconRoots.getParentBlockRootAt(ts);
    }
}
