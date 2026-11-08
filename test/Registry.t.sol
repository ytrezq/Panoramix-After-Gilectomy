// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {CircuitBreaker} from "../src/CircuitBreaker.sol";
import {Registry} from "../src/Registry.sol";
import {TestBase, WithRegisteredPauser, MockPausable} from "./helpers/TestBase.sol";

// =============================================================================
// Access control
// =============================================================================

contract RegistryAccessControl is TestBase {
    function test_RevertIf_SenderNotAdmin() public {
        vm.expectRevert(CircuitBreaker.SenderNotAdmin.selector);
        vm.prank(stranger);
        cb.registerPauser(address(mockPausable), pauser);
    }

    function test_RevertIf_SenderIsPauser() public {
        vm.expectRevert(CircuitBreaker.SenderNotAdmin.selector);
        vm.prank(pauser);
        cb.registerPauser(address(mockPausable), pauser);
    }

    function test_SucceedsFromAdmin() public {
        vm.prank(admin);
        cb.registerPauser(address(mockPausable), pauser);

        assertEq(cb.getPauser(address(mockPausable)), pauser);
    }
}

// =============================================================================
// Validation
// =============================================================================

contract RegistryValidation is TestBase {
    function test_RevertIf_PausableZero_WithNonZeroPauser() public {
        vm.expectRevert(Registry.PausableZero.selector);
        vm.prank(admin);
        cb.registerPauser(address(0), pauser);
    }

    function test_RevertIf_PausableZero_WithZeroPauser() public {
        vm.expectRevert(Registry.PausableZero.selector);
        vm.prank(admin);
        cb.registerPauser(address(0), address(0));
    }
}

// =============================================================================
// Registration
// =============================================================================

contract RegistryRegistration is TestBase {
    function test_RegistersNewPausable() public {
        vm.expectEmit(true, true, true, true);
        emit Registry.PauserSet(address(mockPausable), address(0), pauser);
        vm.expectEmit(true, false, false, true);
        emit CircuitBreaker.HeartbeatUpdated(pauser, block.timestamp + HEARTBEAT_INTERVAL);

        vm.prank(admin);
        cb.registerPauser(address(mockPausable), pauser);

        assertEq(cb.getPauser(address(mockPausable)), pauser);
        _assertPausablesContain(address(mockPausable));
        assertEq(cb.getPausableCount(pauser), 1);
        assertTrue(cb.isPauserLive(pauser));
        assertEq(cb.heartbeatExpiry(pauser), block.timestamp + HEARTBEAT_INTERVAL);
    }

    function test_MultiplePausablesToSamePauser() public {
        MockPausable mp2 = new MockPausable();

        _registerPauser(address(mockPausable), pauser);

        uint256 firstExpiry = cb.heartbeatExpiry(pauser);
        vm.warp(block.timestamp + 100);

        _registerPauser(address(mp2), pauser);

        assertEq(cb.getPausableCount(pauser), 2);
        _assertPausablesContain(address(mockPausable));
        _assertPausablesContain(address(mp2));
        // Heartbeat refreshed on second registration
        assertGt(cb.heartbeatExpiry(pauser), firstExpiry);
    }

    function test_MultiplePausablesToDifferentPausers() public {
        address pauser2 = makeAddr("pauser2");
        MockPausable mp2 = new MockPausable();

        _registerPauser(address(mockPausable), pauser);
        _registerPauser(address(mp2), pauser2);

        assertEq(cb.getPausableCount(pauser), 1);
        assertEq(cb.getPausableCount(pauser2), 1);
        assertTrue(cb.isPauserLive(pauser));
        assertTrue(cb.isPauserLive(pauser2));
        assertEq(cb.getPauser(address(mockPausable)), pauser);
        assertEq(cb.getPauser(address(mp2)), pauser2);
    }

    function test_ManyPausablesToSamePauser() public {
        for (uint256 i = 0; i < 10; i++) {
            MockPausable mp = new MockPausable();
            _registerPauser(address(mp), pauser);
        }

        assertEq(cb.getPausableCount(pauser), 10);
        _assertPausablesLength(10);
    }

    function test_HeartbeatRefreshedOnEachRegistration() public {
        _registerPauser(address(mockPausable), pauser);
        uint256 firstExpiry = cb.heartbeatExpiry(pauser);

        vm.warp(block.timestamp + 1000);

        MockPausable mp2 = new MockPausable();
        _registerPauser(address(mp2), pauser);

        uint256 secondExpiry = cb.heartbeatExpiry(pauser);
        assertEq(secondExpiry, block.timestamp + HEARTBEAT_INTERVAL);
        assertGt(secondExpiry, firstExpiry);
    }
}

// =============================================================================
// Replacement
// =============================================================================

contract RegistryReplacement is WithRegisteredPauser {
    function test_ReplacesPauser() public {
        address pauser2 = makeAddr("pauser2");

        vm.expectEmit(true, true, true, true);
        emit Registry.PauserSet(address(mockPausable), pauser, pauser2);
        vm.expectEmit(true, false, false, true);
        emit CircuitBreaker.HeartbeatUpdated(pauser2, block.timestamp + HEARTBEAT_INTERVAL);

        vm.prank(admin);
        cb.registerPauser(address(mockPausable), pauser2);

        assertEq(cb.getPauser(address(mockPausable)), pauser2);
        assertEq(cb.getPausableCount(pauser), 0);
        assertEq(cb.getPausableCount(pauser2), 1);
        // Array unchanged (still contains the pausable)
        _assertPausablesLength(1);
        _assertPausablesContain(address(mockPausable));
    }

    function test_SamePauserReassignment_RefreshesHeartbeat() public {
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL / 2);

        vm.expectEmit(true, true, true, true);
        emit Registry.PauserSet(address(mockPausable), pauser, pauser);
        vm.expectEmit(true, false, false, true);
        emit CircuitBreaker.HeartbeatUpdated(pauser, block.timestamp + HEARTBEAT_INTERVAL);

        vm.prank(admin);
        cb.registerPauser(address(mockPausable), pauser);

        assertEq(cb.heartbeatExpiry(pauser), block.timestamp + HEARTBEAT_INTERVAL);
        assertEq(cb.getPausableCount(pauser), 1);
        _assertPausablesLength(1);
        _assertNoDuplicatesInPausables();
    }

    function test_ReplacementWithMultiplePausables_OldPauserKeepsRemaining() public {
        address pauserB = makeAddr("pauserB");
        MockPausable mp2 = new MockPausable();
        _registerPauser(address(mp2), pauser);

        assertEq(cb.getPausableCount(pauser), 2);

        // Replace one pausable's pauser from pauser -> pauserB
        vm.prank(admin);
        cb.registerPauser(address(mockPausable), pauserB);

        assertEq(cb.getPausableCount(pauser), 1);
        assertEq(cb.getPausableCount(pauserB), 1);
        assertEq(cb.getPauser(address(mockPausable)), pauserB);
        assertEq(cb.getPauser(address(mp2)), pauser);
    }
}

// =============================================================================
// Unregistration
// =============================================================================

contract RegistryUnregistration is WithRegisteredPauser {
    function test_UnregistersAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Registry.PauserSet(address(mockPausable), pauser, address(0));
        // Heartbeat cleared because pauser has no remaining pausables
        vm.expectEmit(true, false, false, true);
        emit CircuitBreaker.HeartbeatUpdated(pauser, 0);

        vm.prank(admin);
        cb.registerPauser(address(mockPausable), address(0));

        assertEq(cb.getPauser(address(mockPausable)), address(0));
        _assertPausablesLength(0);
        assertEq(cb.getPausableCount(pauser), 0);
        assertEq(cb.heartbeatExpiry(pauser), 0);
    }

    function test_IdempotentUnregistration() public {
        // Unregister first
        vm.prank(admin);
        cb.registerPauser(address(mockPausable), address(0));

        // Unregister again (already zero) -- should not revert
        vm.expectEmit(true, true, true, true);
        emit Registry.PauserSet(address(mockPausable), address(0), address(0));

        vm.prank(admin);
        cb.registerPauser(address(mockPausable), address(0));

        assertEq(cb.getPauser(address(mockPausable)), address(0));
        _assertPausablesLength(0);
    }

    function test_UnregisterOneOfMultiple() public {
        MockPausable mp2 = new MockPausable();
        _registerPauser(address(mp2), pauser);

        assertEq(cb.getPausableCount(pauser), 2);

        vm.prank(admin);
        cb.registerPauser(address(mockPausable), address(0));

        assertEq(cb.getPausableCount(pauser), 1);
        _assertPausablesLength(1);
        _assertPausablesContain(address(mp2));
        _assertPausablesExclude(address(mockPausable));
    }
}

// =============================================================================
// Swap-and-pop
// =============================================================================

contract RegistrySwapAndPop is TestBase {
    MockPausable internal mpA;
    MockPausable internal mpB;
    MockPausable internal mpC;

    address internal pauser2 = makeAddr("pauser2");
    address internal pauser3 = makeAddr("pauser3");

    function setUp() public override {
        super.setUp();
        mpA = new MockPausable();
        mpB = new MockPausable();
        mpC = new MockPausable();
        _registerPauser(address(mpA), pauser);
        _registerPauser(address(mpB), pauser2);
        _registerPauser(address(mpC), pauser3);
    }

    function test_RemoveFirst() public {
        vm.prank(admin);
        cb.registerPauser(address(mpA), address(0));

        address[] memory pausables = cb.getPausables();
        assertEq(pausables.length, 2);
        // Last element (mpC) swapped into position 0
        assertEq(pausables[0], address(mpC));
        assertEq(pausables[1], address(mpB));
    }

    function test_RemoveMiddle() public {
        vm.prank(admin);
        cb.registerPauser(address(mpB), address(0));

        address[] memory pausables = cb.getPausables();
        assertEq(pausables.length, 2);
        assertEq(pausables[0], address(mpA));
        // Last element (mpC) swapped into position 1
        assertEq(pausables[1], address(mpC));
    }

    function test_RemoveLast() public {
        vm.prank(admin);
        cb.registerPauser(address(mpC), address(0));

        address[] memory pausables = cb.getPausables();
        assertEq(pausables.length, 2);
        // Just pop, no swap needed
        assertEq(pausables[0], address(mpA));
        assertEq(pausables[1], address(mpB));
    }

    function test_RemoveOnlyElement() public {
        // Start fresh with just one
        MockPausable single = new MockPausable();
        // Use a separate CB so we start clean
        CircuitBreaker localCb = new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            HEARTBEAT_INTERVAL
        );

        vm.startPrank(admin);
        localCb.registerPauser(address(single), pauser);
        assertEq(localCb.getPausables().length, 1);

        localCb.registerPauser(address(single), address(0));
        assertEq(localCb.getPausables().length, 0);
        vm.stopPrank();
    }

    function test_RemoveAll_OneByOne() public {
        vm.startPrank(admin);
        cb.registerPauser(address(mpA), address(0));
        cb.registerPauser(address(mpB), address(0));
        cb.registerPauser(address(mpC), address(0));
        vm.stopPrank();

        _assertPausablesLength(0);
    }

    function test_NoDuplicatesAfterSwapAndPop() public {
        // Register 2 more for 5 total
        MockPausable mpD = new MockPausable();
        MockPausable mpE = new MockPausable();
        address pauser4 = makeAddr("pauser4");
        address pauser5 = makeAddr("pauser5");
        _registerPauser(address(mpD), pauser4);
        _registerPauser(address(mpE), pauser5);

        _assertPausablesLength(5);

        // Remove 2
        vm.startPrank(admin);
        cb.registerPauser(address(mpB), address(0));
        cb.registerPauser(address(mpD), address(0));
        vm.stopPrank();

        _assertPausablesLength(3);
        _assertNoDuplicatesInPausables();
    }
}

// =============================================================================
// Re-registration
// =============================================================================

contract RegistryReRegistration is TestBase {
    function test_ReRegisterAfterUnregistration_SamePauser() public {
        _registerPauser(address(mockPausable), pauser);

        vm.prank(admin);
        cb.registerPauser(address(mockPausable), address(0));
        _assertPausablesLength(0);

        _registerPauser(address(mockPausable), pauser);

        assertEq(cb.getPauser(address(mockPausable)), pauser);
        _assertPausablesLength(1);
        _assertPausablesContain(address(mockPausable));
        _assertNoDuplicatesInPausables();
    }

    function test_ReRegisterAfterUnregistration_DifferentPauser() public {
        address pauser2 = makeAddr("pauser2");

        _registerPauser(address(mockPausable), pauser);

        vm.prank(admin);
        cb.registerPauser(address(mockPausable), address(0));
        _assertPausablesLength(0);

        _registerPauser(address(mockPausable), pauser2);

        assertEq(cb.getPauser(address(mockPausable)), pauser2);
        assertEq(cb.getPausableCount(pauser2), 1);
        _assertPausablesLength(1);
        _assertPausablesContain(address(mockPausable));
        _assertNoDuplicatesInPausables();
    }

    function test_ReRegisterAfterPauseConsumption() public {
        _registerPauser(address(mockPausable), pauser);

        // Pause auto-unregisters the pauser
        vm.prank(pauser);
        cb.pause(address(mockPausable));

        assertTrue(mockPausable.isPaused());
        assertEq(cb.getPauser(address(mockPausable)), address(0));
        _assertPausablesLength(0);

        // Reset mock state so it can be paused again
        mockPausable.unpause();

        // Re-register
        _registerPauser(address(mockPausable), pauser);

        assertEq(cb.getPauser(address(mockPausable)), pauser);
        assertTrue(cb.isPauserLive(pauser));

        // Can pause again
        vm.prank(pauser);
        cb.pause(address(mockPausable));
        assertTrue(mockPausable.isPaused());
    }
}

// =============================================================================
// Heartbeat on registration
// =============================================================================

contract RegistryHeartbeatOnRegistration is TestBase {
    function test_HeartbeatNotRequiredActiveOnRegistration() public {
        _registerPauser(address(mockPausable), pauser);

        // Let heartbeat expire
        vm.warp(cb.heartbeatExpiry(pauser) + 1);
        assertFalse(cb.isPauserLive(pauser));

        // Register new pausable for same pauser -- should not revert
        MockPausable mp2 = new MockPausable();
        _registerPauser(address(mp2), pauser);

        // Heartbeat refreshed
        assertTrue(cb.isPauserLive(pauser));
        assertEq(cb.heartbeatExpiry(pauser), block.timestamp + HEARTBEAT_INTERVAL);
    }

    function test_ReRegisterExpiredPauser_RefreshesAndCanPause() public {
        _registerPauser(address(mockPausable), pauser);

        // Let heartbeat expire
        vm.warp(cb.heartbeatExpiry(pauser) + 1);
        assertFalse(cb.isPauserLive(pauser));

        // Re-register same pausable + same pauser
        vm.expectEmit(true, true, true, true);
        emit Registry.PauserSet(address(mockPausable), pauser, pauser);
        vm.expectEmit(true, false, false, true);
        emit CircuitBreaker.HeartbeatUpdated(pauser, block.timestamp + HEARTBEAT_INTERVAL);

        vm.prank(admin);
        cb.registerPauser(address(mockPausable), pauser);

        assertTrue(cb.isPauserLive(pauser));

        // Can pause
        vm.prank(pauser);
        cb.pause(address(mockPausable));
        assertTrue(mockPausable.isPaused());
    }
}

// =============================================================================
// Large scale
// =============================================================================

contract RegistryLargeScale is TestBase {
    function test_TwentyPausablesEnumerationCorrectness() public {
        address[] memory mps = new address[](20);
        for (uint256 i = 0; i < 20; i++) {
            mps[i] = address(new MockPausable());
            _registerPauser(mps[i], pauser);
        }

        assertEq(cb.getPausableCount(pauser), 20);
        _assertPausablesLength(20);
        _assertNoDuplicatesInPausables();

        // Remove first (index 0) -- last swaps in
        vm.startPrank(admin);
        cb.registerPauser(mps[0], address(0));
        assertEq(cb.getPausableCount(pauser), 19);
        _assertPausablesLength(19);
        _assertPausablesExclude(mps[0]);
        _assertNoDuplicatesInPausables();

        // Remove last currently in array
        cb.registerPauser(mps[19], address(0));
        assertEq(cb.getPausableCount(pauser), 18);
        _assertPausablesLength(18);
        _assertPausablesExclude(mps[19]);
        _assertNoDuplicatesInPausables();

        // Remove a middle element
        cb.registerPauser(mps[10], address(0));
        assertEq(cb.getPausableCount(pauser), 17);
        _assertPausablesLength(17);
        _assertPausablesExclude(mps[10]);
        _assertNoDuplicatesInPausables();

        vm.stopPrank();

        // Remaining pausables are all still present
        for (uint256 i = 1; i < 20; i++) {
            if (i == 10 || i == 19) continue;
            _assertPausablesContain(mps[i]);
        }
    }
}

// =============================================================================
// View defaults
// =============================================================================

contract RegistryViewDefaults is TestBase {
    function test_GetPauser_ReturnsZeroForUnregistered() public view {
        assertEq(cb.getPauser(address(mockPausable)), address(0));
    }

    function test_GetPausableCount_ReturnsZeroForUnknown() public view {
        assertEq(cb.getPausableCount(stranger), 0);
    }

    function test_GetPausables_EmptyByDefault() public view {
        assertEq(cb.getPausables().length, 0);
    }
}
