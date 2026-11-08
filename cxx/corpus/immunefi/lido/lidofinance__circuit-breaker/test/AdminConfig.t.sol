// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {CircuitBreaker} from "../src/CircuitBreaker.sol";
import {TestBase, WithRegisteredPauser} from "./helpers/TestBase.sol";

// =============================================================================
// setPauseDuration
// =============================================================================

contract SetPauseDuration is TestBase {
    // -- Access control -------------------------------------------------------

    function test_RevertIf_SenderNotAdmin() public {
        vm.expectRevert(CircuitBreaker.SenderNotAdmin.selector);
        vm.prank(stranger);
        cb.setPauseDuration(MAX_PAUSE_DURATION);
    }

    function test_RevertIf_SenderIsPauser() public {
        vm.expectRevert(CircuitBreaker.SenderNotAdmin.selector);
        vm.prank(pauser);
        cb.setPauseDuration(MAX_PAUSE_DURATION);
    }

    function test_SucceedsWhenCalledByAdmin() public {
        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.PauseDurationUpdated(PAUSE_DURATION, MAX_PAUSE_DURATION);

        vm.prank(admin);
        cb.setPauseDuration(MAX_PAUSE_DURATION);

        assertEq(cb.pauseDuration(), MAX_PAUSE_DURATION);
    }

    // -- Validation -----------------------------------------------------------

    function test_RevertIf_BelowMin() public {
        vm.expectRevert(CircuitBreaker.PauseDurationBelowMin.selector);
        vm.prank(admin);
        cb.setPauseDuration(MIN_PAUSE_DURATION - 1);
    }

    function test_RevertIf_AboveMax() public {
        vm.expectRevert(CircuitBreaker.PauseDurationAboveMax.selector);
        vm.prank(admin);
        cb.setPauseDuration(MAX_PAUSE_DURATION + 1);
    }

    // -- Boundary values ------------------------------------------------------

    function test_SucceedsAtExactMin() public {
        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.PauseDurationUpdated(PAUSE_DURATION, MIN_PAUSE_DURATION);

        vm.prank(admin);
        cb.setPauseDuration(MIN_PAUSE_DURATION);

        assertEq(cb.pauseDuration(), MIN_PAUSE_DURATION);
    }

    function test_SucceedsAtExactMax() public {
        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.PauseDurationUpdated(PAUSE_DURATION, MAX_PAUSE_DURATION);

        vm.prank(admin);
        cb.setPauseDuration(MAX_PAUSE_DURATION);

        assertEq(cb.pauseDuration(), MAX_PAUSE_DURATION);
    }

    function test_SucceedsAtMinPlusOne() public {
        vm.prank(admin);
        cb.setPauseDuration(MIN_PAUSE_DURATION + 1);
        assertEq(cb.pauseDuration(), MIN_PAUSE_DURATION + 1);
    }

    function test_SucceedsAtMaxMinusOne() public {
        vm.prank(admin);
        cb.setPauseDuration(MAX_PAUSE_DURATION - 1);
        assertEq(cb.pauseDuration(), MAX_PAUSE_DURATION - 1);
    }

    // -- State updates --------------------------------------------------------

    function test_UpdatesStorageAndEmitsEvent() public {
        uint256 newDuration = 20 days;

        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.PauseDurationUpdated(PAUSE_DURATION, newDuration);

        vm.prank(admin);
        cb.setPauseDuration(newDuration);

        assertEq(cb.pauseDuration(), newDuration);
    }

    function test_IdempotentSetSameValue() public {
        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.PauseDurationUpdated(PAUSE_DURATION, PAUSE_DURATION);

        vm.prank(admin);
        cb.setPauseDuration(PAUSE_DURATION);

        assertEq(cb.pauseDuration(), PAUSE_DURATION);
    }

    function test_MultipleSequentialChanges() public {
        uint256[] memory durations = new uint256[](3);
        durations[0] = MIN_PAUSE_DURATION;
        durations[1] = MAX_PAUSE_DURATION;
        durations[2] = MIN_PAUSE_DURATION + 1 days;

        uint256 previous = PAUSE_DURATION;
        for (uint256 i = 0; i < durations.length; i++) {
            vm.expectEmit(false, false, false, true);
            emit CircuitBreaker.PauseDurationUpdated(previous, durations[i]);

            vm.prank(admin);
            cb.setPauseDuration(durations[i]);

            assertEq(cb.pauseDuration(), durations[i]);
            previous = durations[i];
        }
    }
}

// =============================================================================
// setHeartbeatInterval
// =============================================================================

contract SetHeartbeatInterval is TestBase {
    // -- Access control -------------------------------------------------------

    function test_RevertIf_SenderNotAdmin() public {
        vm.expectRevert(CircuitBreaker.SenderNotAdmin.selector);
        vm.prank(stranger);
        cb.setHeartbeatInterval(MAX_HEARTBEAT_INTERVAL);
    }

    function test_RevertIf_SenderIsPauser() public {
        vm.expectRevert(CircuitBreaker.SenderNotAdmin.selector);
        vm.prank(pauser);
        cb.setHeartbeatInterval(MAX_HEARTBEAT_INTERVAL);
    }

    function test_SucceedsWhenCalledByAdmin() public {
        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.HeartbeatIntervalUpdated(HEARTBEAT_INTERVAL, MAX_HEARTBEAT_INTERVAL);

        vm.prank(admin);
        cb.setHeartbeatInterval(MAX_HEARTBEAT_INTERVAL);

        assertEq(cb.heartbeatInterval(), MAX_HEARTBEAT_INTERVAL);
    }

    // -- Validation -----------------------------------------------------------

    function test_RevertIf_BelowMin() public {
        vm.expectRevert(CircuitBreaker.HeartbeatIntervalBelowMin.selector);
        vm.prank(admin);
        cb.setHeartbeatInterval(MIN_HEARTBEAT_INTERVAL - 1);
    }

    function test_RevertIf_AboveMax() public {
        vm.expectRevert(CircuitBreaker.HeartbeatIntervalAboveMax.selector);
        vm.prank(admin);
        cb.setHeartbeatInterval(MAX_HEARTBEAT_INTERVAL + 1);
    }

    // -- Boundary values ------------------------------------------------------

    function test_SucceedsAtExactMin() public {
        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.HeartbeatIntervalUpdated(HEARTBEAT_INTERVAL, MIN_HEARTBEAT_INTERVAL);

        vm.prank(admin);
        cb.setHeartbeatInterval(MIN_HEARTBEAT_INTERVAL);

        assertEq(cb.heartbeatInterval(), MIN_HEARTBEAT_INTERVAL);
    }

    function test_SucceedsAtExactMax() public {
        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.HeartbeatIntervalUpdated(HEARTBEAT_INTERVAL, MAX_HEARTBEAT_INTERVAL);

        vm.prank(admin);
        cb.setHeartbeatInterval(MAX_HEARTBEAT_INTERVAL);

        assertEq(cb.heartbeatInterval(), MAX_HEARTBEAT_INTERVAL);
    }

    // -- State updates --------------------------------------------------------

    function test_UpdatesStorageAndEmitsEvent() public {
        uint256 newInterval = 180 days;

        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.HeartbeatIntervalUpdated(HEARTBEAT_INTERVAL, newInterval);

        vm.prank(admin);
        cb.setHeartbeatInterval(newInterval);

        assertEq(cb.heartbeatInterval(), newInterval);
    }

    function test_IdempotentSetSameValue() public {
        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.HeartbeatIntervalUpdated(HEARTBEAT_INTERVAL, HEARTBEAT_INTERVAL);

        vm.prank(admin);
        cb.setHeartbeatInterval(HEARTBEAT_INTERVAL);

        assertEq(cb.heartbeatInterval(), HEARTBEAT_INTERVAL);
    }

    function test_MultipleSequentialChanges() public {
        uint256[] memory intervals = new uint256[](3);
        intervals[0] = MIN_HEARTBEAT_INTERVAL;
        intervals[1] = MAX_HEARTBEAT_INTERVAL;
        intervals[2] = MIN_HEARTBEAT_INTERVAL + 30 days;

        uint256 previous = HEARTBEAT_INTERVAL;
        for (uint256 i = 0; i < intervals.length; i++) {
            vm.expectEmit(false, false, false, true);
            emit CircuitBreaker.HeartbeatIntervalUpdated(previous, intervals[i]);

            vm.prank(admin);
            cb.setHeartbeatInterval(intervals[i]);

            assertEq(cb.heartbeatInterval(), intervals[i]);
            previous = intervals[i];
        }
    }
}

// =============================================================================
// Boundary windows — different min/max configurations
// =============================================================================

contract SetPauseDuration_TightWindow is TestBase {
    CircuitBreaker internal tight;
    uint256 internal constant FIXED = 7 days;

    function setUp() public override {
        super.setUp();
        tight = new CircuitBreaker(
            admin, FIXED, FIXED, MIN_HEARTBEAT_INTERVAL, MAX_HEARTBEAT_INTERVAL, FIXED, HEARTBEAT_INTERVAL
        );
    }

    function test_OnlyAcceptsExactValue() public {
        vm.prank(admin);
        tight.setPauseDuration(FIXED);
        assertEq(tight.pauseDuration(), FIXED);
    }

    function test_RevertIf_AboveOnly() public {
        vm.expectRevert(CircuitBreaker.PauseDurationAboveMax.selector);
        vm.prank(admin);
        tight.setPauseDuration(FIXED + 1);
    }

    function test_RevertIf_BelowOnly() public {
        vm.expectRevert(CircuitBreaker.PauseDurationBelowMin.selector);
        vm.prank(admin);
        tight.setPauseDuration(FIXED - 1);
    }
}

contract SetHeartbeatInterval_TightWindow is TestBase {
    CircuitBreaker internal tight;
    uint256 internal constant FIXED = 60 days;

    function setUp() public override {
        super.setUp();
        tight = new CircuitBreaker(admin, MIN_PAUSE_DURATION, MAX_PAUSE_DURATION, FIXED, FIXED, PAUSE_DURATION, FIXED);
    }

    function test_OnlyAcceptsExactValue() public {
        vm.prank(admin);
        tight.setHeartbeatInterval(FIXED);
        assertEq(tight.heartbeatInterval(), FIXED);
    }

    function test_RevertIf_AboveOnly() public {
        vm.expectRevert(CircuitBreaker.HeartbeatIntervalAboveMax.selector);
        vm.prank(admin);
        tight.setHeartbeatInterval(FIXED + 1);
    }

    function test_RevertIf_BelowOnly() public {
        vm.expectRevert(CircuitBreaker.HeartbeatIntervalBelowMin.selector);
        vm.prank(admin);
        tight.setHeartbeatInterval(FIXED - 1);
    }
}

contract SetPauseDuration_WideWindow is TestBase {
    CircuitBreaker internal wide;

    function setUp() public override {
        super.setUp();
        wide = new CircuitBreaker(
            admin, 1, type(uint256).max, MIN_HEARTBEAT_INTERVAL, MAX_HEARTBEAT_INTERVAL, 1, HEARTBEAT_INTERVAL
        );
    }

    function test_SucceedsAtLargeValue() public {
        uint256 large = 365 days * 100;

        vm.prank(admin);
        wide.setPauseDuration(large);

        assertEq(wide.pauseDuration(), large);
    }

    function test_SucceedsAtMaxUint() public {
        vm.prank(admin);
        wide.setPauseDuration(type(uint256).max);

        assertEq(wide.pauseDuration(), type(uint256).max);
    }
}

contract SetHeartbeatInterval_WideWindow is TestBase {
    CircuitBreaker internal wide;

    function setUp() public override {
        super.setUp();
        wide =
            new CircuitBreaker(admin, MIN_PAUSE_DURATION, MAX_PAUSE_DURATION, 1, type(uint256).max, PAUSE_DURATION, 1);
    }

    function test_SucceedsAtLargeValue() public {
        uint256 large = 365 days * 100;

        vm.prank(admin);
        wide.setHeartbeatInterval(large);

        assertEq(wide.heartbeatInterval(), large);
    }

    function test_SucceedsAtMaxUint() public {
        vm.prank(admin);
        wide.setHeartbeatInterval(type(uint256).max);

        assertEq(wide.heartbeatInterval(), type(uint256).max);
    }
}

// =============================================================================
// Effect on existing pausers
// =============================================================================

contract HeartbeatIntervalEffectOnPausers is WithRegisteredPauser {
    function test_DoesNotRetroactivelyChangeExistingExpiry() public {
        uint256 expiryBefore = cb.heartbeatExpiry(pauser);

        vm.prank(admin);
        cb.setHeartbeatInterval(MIN_HEARTBEAT_INTERVAL);

        assertEq(cb.heartbeatExpiry(pauser), expiryBefore);
    }

    function test_NextHeartbeatUsesNewInterval() public {
        vm.prank(admin);
        cb.setHeartbeatInterval(MIN_HEARTBEAT_INTERVAL);

        uint256 ts = block.timestamp;

        vm.prank(pauser);
        cb.heartbeat();

        assertEq(cb.heartbeatExpiry(pauser), ts + MIN_HEARTBEAT_INTERVAL);
    }

    function test_ReductionWorstCaseWindow() public {
        // Pauser heartbeats right before the interval reduction
        vm.prank(pauser);
        cb.heartbeat();
        uint256 expiryBeforeReduction = cb.heartbeatExpiry(pauser);

        // Admin drastically reduces interval: 365d -> 30d
        vm.prank(admin);
        cb.setHeartbeatInterval(MIN_HEARTBEAT_INTERVAL);

        // Existing expiry is unchanged -- pauser stays live for the full original window
        assertEq(cb.heartbeatExpiry(pauser), expiryBeforeReduction);
        assertTrue(cb.isPauserLive(pauser));

        // At old expiry minus 1, pauser still live (worst case)
        vm.warp(expiryBeforeReduction - 1);
        assertTrue(cb.isPauserLive(pauser));

        // Pauser can still heartbeat, but now gets the new shorter interval
        vm.prank(pauser);
        cb.heartbeat();
        assertEq(cb.heartbeatExpiry(pauser), block.timestamp + MIN_HEARTBEAT_INTERVAL);
    }
}
