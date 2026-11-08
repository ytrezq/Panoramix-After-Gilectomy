// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {CircuitBreaker} from "../src/CircuitBreaker.sol";
import {TestBase, WithRegisteredPauser, WithThreePausables, MockPausable} from "./helpers/TestBase.sol";

// =============================================================================
// HeartbeatAccessControl
// =============================================================================

contract HeartbeatAccessControl is TestBase {
    function test_RevertIf_NotRegistered() public {
        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauser);
        cb.heartbeat();
    }

    function test_RevertIf_Stranger() public {
        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(stranger);
        cb.heartbeat();
    }

    function test_RevertIf_AdminNotRegistered() public {
        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(admin);
        cb.heartbeat();
    }

    function test_SucceedsFromRegisteredPauser() public {
        _registerPauser(address(mockPausable), pauser);

        vm.prank(pauser);
        cb.heartbeat();

        assertTrue(cb.isPauserLive(pauser));
    }
}

// =============================================================================
// HeartbeatExpiry
// =============================================================================

contract HeartbeatExpiry is WithRegisteredPauser {
    function test_SucceedsImmediatelyAfterRegistration() public {
        vm.prank(pauser);
        cb.heartbeat();

        assertTrue(cb.isPauserLive(pauser));
    }

    function test_SucceedsOneSecondBeforeExpiry() public {
        _advanceToHeartbeatEdge(pauser);
        uint256 ts = block.timestamp;

        vm.expectEmit(true, false, false, true);
        emit CircuitBreaker.HeartbeatUpdated(pauser, ts + HEARTBEAT_INTERVAL);

        vm.prank(pauser);
        cb.heartbeat();

        assertEq(cb.heartbeatExpiry(pauser), ts + HEARTBEAT_INTERVAL);
    }

    function test_RevertIf_AtExactExpiry() public {
        _advanceToHeartbeatExpiry(pauser);

        vm.expectRevert(CircuitBreaker.HeartbeatExpired.selector);
        vm.prank(pauser);
        cb.heartbeat();
    }

    function test_RevertIf_PastExpiry() public {
        _advancePastHeartbeat(pauser);

        vm.expectRevert(CircuitBreaker.HeartbeatExpired.selector);
        vm.prank(pauser);
        cb.heartbeat();
    }
}

// =============================================================================
// HeartbeatState
// =============================================================================

contract HeartbeatState is WithRegisteredPauser {
    function test_UpdatesExpiryAndEmitsEvent() public {
        vm.warp(block.timestamp + 1 hours);
        uint256 ts = block.timestamp;

        vm.expectEmit(true, false, false, true);
        emit CircuitBreaker.HeartbeatUpdated(pauser, ts + HEARTBEAT_INTERVAL);

        vm.prank(pauser);
        cb.heartbeat();

        assertEq(cb.heartbeatExpiry(pauser), ts + HEARTBEAT_INTERVAL);
    }

    function test_RepeatedHeartbeatsExtendWindow() public {
        vm.prank(pauser);
        cb.heartbeat();
        uint256 firstExpiry = cb.heartbeatExpiry(pauser);

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL / 2);

        vm.prank(pauser);
        cb.heartbeat();
        uint256 secondExpiry = cb.heartbeatExpiry(pauser);

        assertGt(secondExpiry, firstExpiry);
        assertEq(secondExpiry, block.timestamp + HEARTBEAT_INTERVAL);
    }

    function test_ChainOfHeartbeatsKeepsPauserAliveIndefinitely() public {
        for (uint256 i = 0; i < 5; i++) {
            _advanceToHeartbeatEdge(pauser);
            assertTrue(cb.isPauserLive(pauser));

            vm.prank(pauser);
            cb.heartbeat();

            assertEq(cb.heartbeatExpiry(pauser), block.timestamp + HEARTBEAT_INTERVAL);
        }

        assertTrue(cb.isPauserLive(pauser));
    }
}

// =============================================================================
// HeartbeatAfterUnregistration
// =============================================================================

contract HeartbeatAfterUnregistration is WithRegisteredPauser {
    function test_RevertIf_UnregisteredByAdmin() public {
        vm.prank(admin);
        cb.registerPauser(address(mockPausable), address(0));

        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauser);
        cb.heartbeat();
    }

    function test_UnregistrationClearsHeartbeatOfAbandonedPauser() public {
        // Heartbeat is still active
        assertTrue(cb.isPauserLive(pauser));

        vm.prank(admin);
        cb.registerPauser(address(mockPausable), address(0));

        // Heartbeat cleared since pauser has no pausables left
        assertEq(cb.heartbeatExpiry(pauser), 0);
        assertFalse(cb.isPauserLive(pauser));

        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauser);
        cb.heartbeat();
    }
}

// =============================================================================
// HeartbeatWithChangedInterval
// =============================================================================

contract HeartbeatWithChangedInterval is WithRegisteredPauser {
    function test_NextHeartbeatUsesNewInterval() public {
        vm.prank(admin);
        cb.setHeartbeatInterval(MIN_HEARTBEAT_INTERVAL);

        uint256 ts = block.timestamp;

        vm.prank(pauser);
        cb.heartbeat();

        assertEq(cb.heartbeatExpiry(pauser), ts + MIN_HEARTBEAT_INTERVAL);
    }

    function test_ChangedIntervalDoesNotAffectCurrentExpiry() public {
        uint256 expiryBefore = cb.heartbeatExpiry(pauser);

        vm.prank(admin);
        cb.setHeartbeatInterval(MIN_HEARTBEAT_INTERVAL);

        assertEq(cb.heartbeatExpiry(pauser), expiryBefore);
    }
}

// =============================================================================
// HeartbeatMultiplePausers
// =============================================================================

contract HeartbeatMultiplePausers is TestBase {
    function test_IndependentTracking() public {
        address pauserA = makeAddr("pauserA");
        address pauserB = makeAddr("pauserB");
        MockPausable mpA = new MockPausable();
        MockPausable mpB = new MockPausable();

        _registerPauser(address(mpA), pauserA);
        _registerPauser(address(mpB), pauserB);

        uint256 expiryB = cb.heartbeatExpiry(pauserB);

        vm.warp(block.timestamp + 1 hours);

        vm.prank(pauserA);
        cb.heartbeat();

        assertEq(cb.heartbeatExpiry(pauserA), block.timestamp + HEARTBEAT_INTERVAL);
        assertEq(cb.heartbeatExpiry(pauserB), expiryB);
        assertTrue(cb.isPauserLive(pauserA));
        assertTrue(cb.isPauserLive(pauserB));
    }

    function test_OneExpiresOtherDoesNot() public {
        address pauserA = makeAddr("pauserA");
        address pauserB = makeAddr("pauserB");
        MockPausable mpA = new MockPausable();
        MockPausable mpB = new MockPausable();

        _registerPauser(address(mpA), pauserA);

        // Advance time so pauserA is near expiry, then register pauserB
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL - 1);
        _registerPauser(address(mpB), pauserB);

        // Advance 2 more seconds: pauserA expires, pauserB still live
        vm.warp(block.timestamp + 2);

        assertFalse(cb.isPauserLive(pauserA));
        assertTrue(cb.isPauserLive(pauserB));
    }
}

// =============================================================================
// HeartbeatAfterPauseConsumption
// =============================================================================

contract HeartbeatAfterPauseConsumption is WithThreePausables {
    function test_StillWorksAfterOneRegistrationConsumed() public {
        vm.prank(pauser);
        cb.pause(address(pausable1));

        assertEq(cb.getPausableCount(pauser), 2);

        vm.warp(block.timestamp + 1 hours);

        vm.prank(pauser);
        cb.heartbeat();

        assertEq(cb.heartbeatExpiry(pauser), block.timestamp + HEARTBEAT_INTERVAL);
    }

    function test_HeartbeatRefreshedDuringPause() public {
        vm.warp(block.timestamp + 1 hours);
        uint256 ts = block.timestamp;

        vm.prank(pauser);
        cb.pause(address(pausable1));

        // pause calls _setHeartbeatExpiry, so expiry should be refreshed
        assertEq(cb.heartbeatExpiry(pauser), ts + HEARTBEAT_INTERVAL);
    }

    function test_RevertIf_AllRegistrationsConsumed() public {
        vm.startPrank(pauser);
        cb.pause(address(pausable1));
        cb.pause(address(pausable2));
        cb.pause(address(pausable3));
        vm.stopPrank();

        assertEq(cb.getPausableCount(pauser), 0);

        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauser);
        cb.heartbeat();
    }
}

// =============================================================================
// IsPauserLive
// =============================================================================

contract IsPauserLive is TestBase {
    function test_TrueBeforeExpiry() public {
        _registerPauser(address(mockPausable), pauser);
        assertTrue(cb.isPauserLive(pauser));
    }

    function test_FalseAtExactExpiry() public {
        _registerPauser(address(mockPausable), pauser);
        _advanceToHeartbeatExpiry(pauser);
        assertFalse(cb.isPauserLive(pauser));
    }

    function test_FalseAfterExpiry() public {
        _registerPauser(address(mockPausable), pauser);
        _advancePastHeartbeat(pauser);
        assertFalse(cb.isPauserLive(pauser));
    }

    function test_FalseForNeverRegisteredAddress() public view {
        assertEq(cb.heartbeatExpiry(stranger), 0);
        assertFalse(cb.isPauserLive(stranger));
    }

    function test_FalseForAddressZero() public view {
        assertFalse(cb.isPauserLive(address(0)));
    }

    function test_FalseAfterAdminUnregistersLastPausable() public {
        _registerPauser(address(mockPausable), pauser);
        assertTrue(cb.isPauserLive(pauser));

        // Admin unregisters — pauser has no pausables left, so heartbeat is cleared
        vm.prank(admin);
        cb.registerPauser(address(mockPausable), address(0));

        assertEq(cb.getPausableCount(pauser), 0);
        assertEq(cb.heartbeatExpiry(pauser), 0);
        assertFalse(cb.isPauserLive(pauser));
    }

    function test_TrueWhenReplacedButStillRegisteredElsewhere() public {
        address pauserB = makeAddr("pauserB");
        MockPausable mp2 = new MockPausable();

        _registerPauser(address(mockPausable), pauser);
        _registerPauser(address(mp2), pauser);
        assertTrue(cb.isPauserLive(pauser));

        // Admin reassigns only one of the pauser's pausables
        vm.prank(admin);
        cb.registerPauser(address(mockPausable), pauserB);

        // Heartbeat preserved because pauser still has mp2
        assertEq(cb.getPausableCount(pauser), 1);
        assertTrue(cb.isPauserLive(pauser));
    }

    function test_FalseAfterExpiryEvenIfStillRegistered() public {
        _registerPauser(address(mockPausable), pauser);
        _advancePastHeartbeat(pauser);

        // Still registered
        assertEq(cb.getPausableCount(pauser), 1);
        // But heartbeat expired
        assertFalse(cb.isPauserLive(pauser));
    }
}

