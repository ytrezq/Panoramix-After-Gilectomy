// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {CircuitBreaker} from "../src/CircuitBreaker.sol";
import {TestBase} from "./helpers/TestBase.sol";

// =============================================================================
// Parameter validation
// =============================================================================

contract ConstructorValidation is TestBase {
    function test_RevertIf_ZeroAdmin() public {
        vm.expectRevert(CircuitBreaker.AdminZero.selector);
        new CircuitBreaker(
            address(0),
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            HEARTBEAT_INTERVAL
        );
    }

    function test_RevertIf_ZeroMinPauseDuration() public {
        vm.expectRevert(CircuitBreaker.MinPauseDurationZero.selector);
        new CircuitBreaker(
            admin,
            0,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            HEARTBEAT_INTERVAL
        );
    }

    function test_RevertIf_MinPauseDurationExceedsMax() public {
        vm.expectRevert(CircuitBreaker.MinPauseDurationExceedsMax.selector);
        new CircuitBreaker(
            admin,
            MAX_PAUSE_DURATION + 1,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            HEARTBEAT_INTERVAL
        );
    }

    function test_RevertIf_ZeroMinHeartbeatInterval() public {
        vm.expectRevert(CircuitBreaker.MinHeartbeatIntervalZero.selector);
        new CircuitBreaker(
            admin, MIN_PAUSE_DURATION, MAX_PAUSE_DURATION, 0, MAX_HEARTBEAT_INTERVAL, PAUSE_DURATION, HEARTBEAT_INTERVAL
        );
    }

    function test_RevertIf_MinHeartbeatIntervalExceedsMax() public {
        vm.expectRevert(CircuitBreaker.MinHeartbeatIntervalExceedsMax.selector);
        new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MAX_HEARTBEAT_INTERVAL + 1,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            HEARTBEAT_INTERVAL
        );
    }

    function test_RevertIf_PauseDurationBelowMin() public {
        vm.expectRevert(CircuitBreaker.PauseDurationBelowMin.selector);
        new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            MIN_PAUSE_DURATION - 1,
            HEARTBEAT_INTERVAL
        );
    }

    function test_RevertIf_PauseDurationAboveMax() public {
        vm.expectRevert(CircuitBreaker.PauseDurationAboveMax.selector);
        new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            MAX_PAUSE_DURATION + 1,
            HEARTBEAT_INTERVAL
        );
    }

    function test_RevertIf_HeartbeatIntervalBelowMin() public {
        vm.expectRevert(CircuitBreaker.HeartbeatIntervalBelowMin.selector);
        new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL - 1
        );
    }

    function test_RevertIf_HeartbeatIntervalAboveMax() public {
        vm.expectRevert(CircuitBreaker.HeartbeatIntervalAboveMax.selector);
        new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            MAX_HEARTBEAT_INTERVAL + 1
        );
    }

    function test_RevertIf_MultipleInvalidParams_RevertsWithFirstCheck() public {
        // admin=0 AND minPauseDuration=0 — should revert with AdminZero (first check)
        vm.expectRevert(CircuitBreaker.AdminZero.selector);
        new CircuitBreaker(
            address(0),
            0,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            HEARTBEAT_INTERVAL
        );
    }
}

// =============================================================================
// Boundary values
// =============================================================================

contract ConstructorBoundaryValues is TestBase {
    function test_MinEqualsMaxPauseDuration() public {
        uint256 fixedDuration = 7 days;
        CircuitBreaker fresh = new CircuitBreaker(
            admin,
            fixedDuration,
            fixedDuration,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            fixedDuration,
            HEARTBEAT_INTERVAL
        );

        assertEq(fresh.MIN_PAUSE_DURATION(), fixedDuration);
        assertEq(fresh.MAX_PAUSE_DURATION(), fixedDuration);
        assertEq(fresh.pauseDuration(), fixedDuration);

        // Setting the same value is a no-op (no revert)
        vm.prank(admin);
        fresh.setPauseDuration(fixedDuration);
    }

    function test_MinEqualsMaxHeartbeatInterval() public {
        uint256 fixedInterval = 60 days;
        CircuitBreaker fresh = new CircuitBreaker(
            admin, MIN_PAUSE_DURATION, MAX_PAUSE_DURATION, fixedInterval, fixedInterval, PAUSE_DURATION, fixedInterval
        );

        assertEq(fresh.MIN_HEARTBEAT_INTERVAL(), fixedInterval);
        assertEq(fresh.MAX_HEARTBEAT_INTERVAL(), fixedInterval);
        assertEq(fresh.heartbeatInterval(), fixedInterval);

        vm.prank(admin);
        fresh.setHeartbeatInterval(fixedInterval);
    }

    function test_InitialPauseDurationAtLowerBound() public {
        CircuitBreaker fresh = new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            MIN_PAUSE_DURATION,
            HEARTBEAT_INTERVAL
        );

        assertEq(fresh.pauseDuration(), MIN_PAUSE_DURATION);
    }

    function test_InitialPauseDurationAtUpperBound() public {
        CircuitBreaker fresh = new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            MAX_PAUSE_DURATION,
            HEARTBEAT_INTERVAL
        );

        assertEq(fresh.pauseDuration(), MAX_PAUSE_DURATION);
    }

    function test_InitialHeartbeatIntervalAtLowerBound() public {
        CircuitBreaker fresh = new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL
        );

        assertEq(fresh.heartbeatInterval(), MIN_HEARTBEAT_INTERVAL);
    }

    function test_InitialHeartbeatIntervalAtUpperBound() public {
        CircuitBreaker fresh = new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            MAX_HEARTBEAT_INTERVAL
        );

        assertEq(fresh.heartbeatInterval(), MAX_HEARTBEAT_INTERVAL);
    }

    function test_SmallestValidMinPauseDuration() public {
        CircuitBreaker fresh =
            new CircuitBreaker(admin, 1, 1, MIN_HEARTBEAT_INTERVAL, MAX_HEARTBEAT_INTERVAL, 1, HEARTBEAT_INTERVAL);

        assertEq(fresh.MIN_PAUSE_DURATION(), 1);
        assertEq(fresh.MAX_PAUSE_DURATION(), 1);
        assertEq(fresh.pauseDuration(), 1);
    }

    function test_SmallestValidMinHeartbeatInterval() public {
        CircuitBreaker fresh =
            new CircuitBreaker(admin, MIN_PAUSE_DURATION, MAX_PAUSE_DURATION, 1, 1, PAUSE_DURATION, 1);

        assertEq(fresh.MIN_HEARTBEAT_INTERVAL(), 1);
        assertEq(fresh.MAX_HEARTBEAT_INTERVAL(), 1);
        assertEq(fresh.heartbeatInterval(), 1);
    }
}

// =============================================================================
// Initialization — happy path state + events
// =============================================================================

contract ConstructorInitialization is TestBase {
    function test_SetsImmutablesCorrectly() public view {
        assertEq(cb.ADMIN(), admin);
        assertEq(cb.MIN_PAUSE_DURATION(), MIN_PAUSE_DURATION);
        assertEq(cb.MAX_PAUSE_DURATION(), MAX_PAUSE_DURATION);
        assertEq(cb.MIN_HEARTBEAT_INTERVAL(), MIN_HEARTBEAT_INTERVAL);
        assertEq(cb.MAX_HEARTBEAT_INTERVAL(), MAX_HEARTBEAT_INTERVAL);
    }

    function test_SetsMutableStateCorrectly() public view {
        assertEq(cb.pauseDuration(), PAUSE_DURATION);
        assertEq(cb.heartbeatInterval(), HEARTBEAT_INTERVAL);
    }

    function test_EmptyRegistryOnDeploy() public view {
        assertEq(cb.getPausables().length, 0);
        assertEq(cb.getPausableCount(admin), 0);
        assertEq(cb.getPausableCount(pauser), 0);
        assertEq(cb.getPausableCount(stranger), 0);
    }

    function test_EmitsEventsInOrder() public {
        vm.expectEmit(true, false, false, true);
        emit CircuitBreaker.CircuitBreakerInitialized(
            admin, MIN_PAUSE_DURATION, MAX_PAUSE_DURATION, MIN_HEARTBEAT_INTERVAL, MAX_HEARTBEAT_INTERVAL
        );
        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.PauseDurationUpdated(0, PAUSE_DURATION);
        vm.expectEmit(false, false, false, true);
        emit CircuitBreaker.HeartbeatIntervalUpdated(0, HEARTBEAT_INTERVAL);

        new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            HEARTBEAT_INTERVAL
        );
    }
}
