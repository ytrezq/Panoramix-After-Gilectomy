// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {CircuitBreaker} from "../src/CircuitBreaker.sol";
import {TestBase, MockPausable} from "./helpers/TestBase.sol";

contract FullLifecycle is TestBase {
    MockPausable internal pausableA;
    MockPausable internal pausableB;
    MockPausable internal pausableC;

    address internal pauserA = makeAddr("pauserA");
    address internal pauserB = makeAddr("pauserB");

    function test_FullOperationalLifecycle() public {
        pausableA = new MockPausable();
        pausableB = new MockPausable();
        pausableC = new MockPausable();

        // =====================================================================
        // Phase 1: Initial registration
        // Admin registers pauserA for pausableA and pausableB,
        //                  pauserB for pausableC.
        // =====================================================================

        vm.startPrank(admin);
        cb.registerPauser(address(pausableA), pauserA);
        cb.registerPauser(address(pausableB), pauserA);
        cb.registerPauser(address(pausableC), pauserB);
        vm.stopPrank();

        assertEq(cb.getPausableCount(pauserA), 2);
        assertEq(cb.getPausableCount(pauserB), 1);
        assertEq(cb.getPausables().length, 3);
        assertTrue(cb.isPauserLive(pauserA));
        assertTrue(cb.isPauserLive(pauserB));

        // =====================================================================
        // Phase 2: Heartbeats over time
        // Both pausers maintain liveness across several intervals.
        // =====================================================================

        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + HEARTBEAT_INTERVAL - 1 hours);

            vm.prank(pauserA);
            cb.heartbeat();

            vm.prank(pauserB);
            cb.heartbeat();

            assertTrue(cb.isPauserLive(pauserA));
            assertTrue(cb.isPauserLive(pauserB));
        }

        // =====================================================================
        // Phase 3: Admin reconfigures pause duration
        // Governance decides emergency pauses should be shorter.
        // =====================================================================

        vm.prank(admin);
        cb.setPauseDuration(MIN_PAUSE_DURATION);
        assertEq(cb.pauseDuration(), MIN_PAUSE_DURATION);

        // =====================================================================
        // Phase 4: Emergency — pauserA pauses pausableA
        // Single-use: pauserA loses pausableA but keeps pausableB.
        // =====================================================================

        vm.expectEmit(true, true, false, true);
        emit CircuitBreaker.PauseTriggered(address(pausableA), pauserA, MIN_PAUSE_DURATION);

        vm.prank(pauserA);
        cb.pause(address(pausableA));

        assertTrue(pausableA.isPaused());
        assertEq(cb.getPauser(address(pausableA)), address(0));
        assertEq(cb.getPausableCount(pauserA), 1);
        assertEq(cb.getPauser(address(pausableB)), pauserA);

        // =====================================================================
        // Phase 5: Admin re-arms pausableA with pauserA
        // =====================================================================

        // Wait for pause to expire, then re-register
        vm.warp(block.timestamp + MIN_PAUSE_DURATION);
        assertFalse(pausableA.isPaused());

        vm.prank(admin);
        cb.registerPauser(address(pausableA), pauserA);

        assertEq(cb.getPausableCount(pauserA), 2);
        assertEq(cb.getPausables().length, 3);

        // =====================================================================
        // Phase 6: Admin replaces pauserB with pauserA on pausableC
        // pauserB is fully removed, pauserA now covers all 3.
        // =====================================================================

        vm.prank(admin);
        cb.registerPauser(address(pausableC), pauserA);

        assertEq(cb.getPauser(address(pausableC)), pauserA);
        assertEq(cb.getPausableCount(pauserA), 3);
        assertEq(cb.getPausableCount(pauserB), 0);

        // pauserB can no longer heartbeat
        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauserB);
        cb.heartbeat();

        // =====================================================================
        // Phase 7: Admin increases heartbeat interval
        // =====================================================================

        uint256 oldExpiry = cb.heartbeatExpiry(pauserA);

        vm.prank(admin);
        cb.setHeartbeatInterval(MAX_HEARTBEAT_INTERVAL);

        // Existing expiry unchanged
        assertEq(cb.heartbeatExpiry(pauserA), oldExpiry);

        // Next heartbeat uses new interval
        vm.prank(pauserA);
        cb.heartbeat();
        assertEq(cb.heartbeatExpiry(pauserA), block.timestamp + MAX_HEARTBEAT_INTERVAL);

        // =====================================================================
        // Phase 8: pauserA pauses all remaining pausables sequentially
        // =====================================================================

        vm.startPrank(pauserA);

        cb.pause(address(pausableB));
        assertTrue(pausableB.isPaused());
        assertEq(cb.getPausableCount(pauserA), 2);

        cb.pause(address(pausableC));
        assertTrue(pausableC.isPaused());
        assertEq(cb.getPausableCount(pauserA), 1);

        cb.pause(address(pausableA));
        assertTrue(pausableA.isPaused());
        assertEq(cb.getPausableCount(pauserA), 0);

        vm.stopPrank();

        // =====================================================================
        // Phase 9: System is fully drained — no pausers, no pausables
        // =====================================================================

        assertEq(cb.getPausables().length, 0);

        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauserA);
        cb.heartbeat();

        // =====================================================================
        // Phase 10: Admin rebuilds from scratch with new committee
        // =====================================================================

        address pauserC = makeAddr("pauserC");

        pausableA.unpause();
        pausableB.unpause();
        pausableC.unpause();

        vm.prank(admin);
        cb.setPauseDuration(MAX_PAUSE_DURATION);

        vm.startPrank(admin);
        cb.registerPauser(address(pausableA), pauserC);
        cb.registerPauser(address(pausableB), pauserC);
        cb.registerPauser(address(pausableC), pauserC);
        vm.stopPrank();

        assertEq(cb.getPausableCount(pauserC), 3);
        assertEq(cb.getPausables().length, 3);
        assertTrue(cb.isPauserLive(pauserC));

        // pauserC can pause
        vm.prank(pauserC);
        cb.pause(address(pausableC));

        assertTrue(pausableC.isPaused());
        assertEq(pausableC.getResumeSinceTimestamp(), block.timestamp + MAX_PAUSE_DURATION);
        assertEq(cb.getPausableCount(pauserC), 2);
    }
}
