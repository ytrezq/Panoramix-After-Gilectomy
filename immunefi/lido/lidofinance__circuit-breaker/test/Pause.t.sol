// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {CircuitBreaker, IPausable} from "../src/CircuitBreaker.sol";
import {Registry} from "../src/Registry.sol";
import {TestBase, WithRegisteredPauser, WithThreePausables, MockPausable} from "./helpers/TestBase.sol";

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

contract MockPausableFailsPause is IPausable {
    function isPaused() external pure returns (bool) {
        return false;
    }

    function pauseFor(uint256) external {}
}

contract MockPausableRevertsOnPause is IPausable {
    function isPaused() external pure returns (bool) {
        return false;
    }

    function pauseFor(uint256) external pure {
        revert("pauseFor: forced revert");
    }
}

contract MockPausableRevertsNoReason is IPausable {
    function isPaused() external pure returns (bool) {
        return false;
    }

    function pauseFor(uint256) external pure {
        revert();
    }
}

contract MockPausableReentrant is IPausable {
    CircuitBreaker private _cb;
    bool private _paused;
    bool private _reentered;

    constructor(CircuitBreaker cb_) {
        _cb = cb_;
    }

    function isPaused() external view returns (bool) {
        return _paused;
    }

    function pauseFor(uint256) external {
        _paused = true;
        if (!_reentered) {
            _reentered = true;
            _cb.pause(address(this));
        }
    }
}

contract MockPausableCrossReentrant is IPausable {
    CircuitBreaker private _cb;
    address private _otherPausable;
    bool private _paused;

    constructor(CircuitBreaker cb_, address otherPausable_) {
        _cb = cb_;
        _otherPausable = otherPausable_;
    }

    function isPaused() external view returns (bool) {
        return _paused;
    }

    function pauseFor(uint256) external {
        _paused = true;
        _cb.pause(_otherPausable);
    }
}

contract MockPausableAlreadyPaused is IPausable {
    function isPaused() external pure returns (bool) {
        return true;
    }

    function pauseFor(uint256) external {}
}

contract MockPausableRevertsIfAlreadyPaused is IPausable {
    uint256 private _resumeSince;

    function isPaused() external view returns (bool) {
        return block.timestamp < _resumeSince;
    }

    function pauseFor(uint256 duration) external {
        require(block.timestamp >= _resumeSince, "already paused");
        _resumeSince = block.timestamp + duration;
    }
}

// =============================================================================
// Access control
// =============================================================================

contract PauseAccessControl is WithRegisteredPauser {
    function test_RevertIf_Stranger() public {
        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(stranger);
        cb.pause(address(mockPausable));
    }

    function test_RevertIf_Admin() public {
        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(admin);
        cb.pause(address(mockPausable));
    }

    function test_RevertIf_WrongPausableForPauser() public {
        MockPausable mp2 = new MockPausable();

        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauser);
        cb.pause(address(mp2));
    }

    function test_RevertIf_NoPauserSet() public {
        MockPausable mp2 = new MockPausable();

        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauser);
        cb.pause(address(mp2));
    }

    function test_SucceedsFromCorrectPauser() public {
        vm.prank(pauser);
        cb.pause(address(mockPausable));

        assertTrue(mockPausable.isPaused());
    }
}

// =============================================================================
// Heartbeat check during pause
// =============================================================================

contract PauseHeartbeatCheck is WithRegisteredPauser {
    function test_RevertIf_HeartbeatExpired() public {
        _advancePastHeartbeat(pauser);

        vm.expectRevert(CircuitBreaker.HeartbeatExpired.selector);
        vm.prank(pauser);
        cb.pause(address(mockPausable));
    }

    function test_RevertIf_HeartbeatExpiredAtExactBoundary() public {
        _advanceToHeartbeatExpiry(pauser);

        vm.expectRevert(CircuitBreaker.HeartbeatExpired.selector);
        vm.prank(pauser);
        cb.pause(address(mockPausable));
    }

    function test_SucceedsOneSecondBeforeExpiry() public {
        _advanceToHeartbeatEdge(pauser);

        vm.expectEmit(true, true, false, true);
        emit CircuitBreaker.PauseTriggered(address(mockPausable), pauser, PAUSE_DURATION);

        vm.prank(pauser);
        cb.pause(address(mockPausable));

        assertTrue(mockPausable.isPaused());
    }
}

// =============================================================================
// Happy path
// =============================================================================

contract PauseHappyPath is WithRegisteredPauser {
    function test_PausesTargetAndEmitsFullEventSequence() public {
        vm.warp(block.timestamp + 1 hours);
        uint256 ts = block.timestamp;

        vm.expectEmit(true, true, true, true);
        emit Registry.PauserSet(address(mockPausable), pauser, address(0));
        vm.expectEmit(true, true, false, true);
        emit CircuitBreaker.PauseTriggered(address(mockPausable), pauser, PAUSE_DURATION);
        vm.expectEmit(true, false, false, true);
        emit CircuitBreaker.HeartbeatUpdated(pauser, 0);

        vm.prank(pauser);
        cb.pause(address(mockPausable));

        assertTrue(mockPausable.isPaused());
        assertEq(mockPausable.getResumeSinceTimestamp(), ts + PAUSE_DURATION);
        assertEq(cb.getPauser(address(mockPausable)), address(0));
        assertEq(cb.heartbeatExpiry(pauser), 0);
        assertFalse(cb.isPauserLive(pauser));
        assertEq(cb.getPausableCount(pauser), 0);
        assertEq(cb.getPausables().length, 0);
    }

    function test_HeartbeatClearedWhenLastPausableIsPaused() public {
        vm.warp(block.timestamp + 1 hours);

        vm.prank(pauser);
        cb.pause(address(mockPausable));

        assertEq(cb.heartbeatExpiry(pauser), 0);
        assertFalse(cb.isPauserLive(pauser));
    }
}

// =============================================================================
// Single-use enforcement
// =============================================================================

contract PauseSingleUse is WithRegisteredPauser {
    function test_UnregistersPauserAfterPause() public {
        vm.prank(pauser);
        cb.pause(address(mockPausable));

        assertEq(cb.getPauser(address(mockPausable)), address(0));
        assertEq(cb.getPausableCount(pauser), 0);
        assertEq(cb.getPausables().length, 0);
    }

    function test_RevertIf_PauseCalledTwice() public {
        vm.prank(pauser);
        cb.pause(address(mockPausable));

        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauser);
        cb.pause(address(mockPausable));
    }

    function test_RevertIf_PauseCalledTwiceEvenAfterUnpause() public {
        vm.prank(pauser);
        cb.pause(address(mockPausable));

        mockPausable.unpause();

        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauser);
        cb.pause(address(mockPausable));
    }
}

// =============================================================================
// Single-use with multiple pausables
// =============================================================================

contract PauseSingleUseMultiplePausables is WithThreePausables {
    function test_PausingOneKeepsOthers() public {
        vm.prank(pauser);
        cb.pause(address(pausable1));

        assertEq(cb.getPauser(address(pausable1)), address(0));
        assertEq(cb.getPauser(address(pausable2)), pauser);
        assertEq(cb.getPauser(address(pausable3)), pauser);
        assertEq(cb.getPausableCount(pauser), 2);
    }

    function test_SequentialPauseDecrementsThenReverts() public {
        vm.startPrank(pauser);
        cb.pause(address(pausable1));
        assertEq(cb.getPausableCount(pauser), 2);

        cb.pause(address(pausable2));
        assertEq(cb.getPausableCount(pauser), 1);

        cb.pause(address(pausable3));
        assertEq(cb.getPausableCount(pauser), 0);
        vm.stopPrank();

        // Fully unregistered now — heartbeat reverts
        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauser);
        cb.heartbeat();
    }
}

// =============================================================================
// Duration
// =============================================================================

contract PauseDuration is WithRegisteredPauser {
    function test_UsesCurrentPauseDuration() public {
        vm.prank(admin);
        cb.setPauseDuration(MAX_PAUSE_DURATION);

        vm.expectEmit(true, true, false, true);
        emit CircuitBreaker.PauseTriggered(address(mockPausable), pauser, MAX_PAUSE_DURATION);

        vm.prank(pauser);
        cb.pause(address(mockPausable));

        assertEq(mockPausable.getResumeSinceTimestamp(), block.timestamp + MAX_PAUSE_DURATION);
    }

    function test_DurationChangedBetweenPauses() public {
        MockPausable mp2 = new MockPausable();
        _registerPauser(address(mp2), pauser);

        // Pause first with default duration
        vm.prank(pauser);
        cb.pause(address(mockPausable));
        assertEq(mockPausable.getResumeSinceTimestamp(), block.timestamp + PAUSE_DURATION);

        // Admin changes duration
        vm.prank(admin);
        cb.setPauseDuration(MIN_PAUSE_DURATION);

        // Pause second with new duration
        vm.prank(pauser);
        cb.pause(address(mp2));
        assertEq(mp2.getResumeSinceTimestamp(), block.timestamp + MIN_PAUSE_DURATION);
    }
}

// =============================================================================
// PauseFailed
// =============================================================================

contract PauseFailed is TestBase {
    function test_RevertIf_IsPausedReturnsFalse() public {
        MockPausableFailsPause failing = new MockPausableFailsPause();
        _registerPauser(address(failing), pauser);

        vm.expectRevert(CircuitBreaker.PauseFailed.selector);
        vm.prank(pauser);
        cb.pause(address(failing));
    }
}

// =============================================================================
// Pausable that reverts
// =============================================================================

contract PausableReverts is TestBase {
    function test_RevertIf_PauseForRevertsWithReason() public {
        MockPausableRevertsOnPause reverting = new MockPausableRevertsOnPause();
        _registerPauser(address(reverting), pauser);

        vm.expectRevert("pauseFor: forced revert");
        vm.prank(pauser);
        cb.pause(address(reverting));
    }

    function test_RevertIf_PauseForRevertsWithoutReason() public {
        MockPausableRevertsNoReason reverting = new MockPausableRevertsNoReason();
        _registerPauser(address(reverting), pauser);

        vm.expectRevert();
        vm.prank(pauser);
        cb.pause(address(reverting));
    }

    function test_StateUnchangedAfterFailedPause() public {
        MockPausableFailsPause failing = new MockPausableFailsPause();
        _registerPauser(address(failing), pauser);

        vm.expectRevert(CircuitBreaker.PauseFailed.selector);
        vm.prank(pauser);
        cb.pause(address(failing));

        // Revert rolls back all state changes — pauser remains registered
        assertEq(cb.getPauser(address(failing)), pauser);
        assertEq(cb.getPausableCount(pauser), 1);
        assertTrue(cb.isPauserLive(pauser));
    }

    function test_StateUnchangedAfterRevertingPause() public {
        MockPausableRevertsOnPause reverting = new MockPausableRevertsOnPause();
        _registerPauser(address(reverting), pauser);

        vm.expectRevert("pauseFor: forced revert");
        vm.prank(pauser);
        cb.pause(address(reverting));

        // Pauser still registered after reverted tx
        assertEq(cb.getPauser(address(reverting)), pauser);
        assertEq(cb.getPausableCount(pauser), 1);
    }

    function test_RevertIf_PausableIsEOA() public {
        address eoa = makeAddr("eoa");
        _registerPauser(eoa, pauser);

        vm.expectRevert();
        vm.prank(pauser);
        cb.pause(eoa);
    }
}

// =============================================================================
// Reentrancy
// =============================================================================

contract PauseReentrancy is TestBase {
    function test_RevertIf_SamePausableReentrancy() public {
        MockPausableReentrant reentrant = new MockPausableReentrant(cb);
        _registerPauser(address(reentrant), pauser);

        vm.expectRevert(CircuitBreaker.ReentrantCall.selector);
        vm.prank(pauser);
        cb.pause(address(reentrant));
    }

    function test_RevertIf_CrossPausableReentrancy() public {
        MockPausable target = new MockPausable();
        MockPausableCrossReentrant reentrant = new MockPausableCrossReentrant(cb, address(target));

        _registerPauser(address(reentrant), pauser);
        _registerPauser(address(target), pauser);

        vm.expectRevert(CircuitBreaker.ReentrantCall.selector);
        vm.prank(pauser);
        cb.pause(address(reentrant));
    }

    function test_CrossPausableReentrancy_NeitherUnregistered() public {
        MockPausable target = new MockPausable();
        MockPausableCrossReentrant reentrant = new MockPausableCrossReentrant(cb, address(target));

        _registerPauser(address(reentrant), pauser);
        _registerPauser(address(target), pauser);

        vm.expectRevert(CircuitBreaker.ReentrantCall.selector);
        vm.prank(pauser);
        cb.pause(address(reentrant));

        // Entire tx reverted — both still registered
        assertEq(cb.getPauser(address(reentrant)), pauser);
        assertEq(cb.getPauser(address(target)), pauser);
        assertEq(cb.getPausableCount(pauser), 2);
    }
}

// =============================================================================
// Pausing already-paused contract
// =============================================================================

contract PauseAlreadyPaused is TestBase {
    function test_SucceedsOnAlreadyPausedContract() public {
        MockPausableAlreadyPaused alreadyPaused = new MockPausableAlreadyPaused();
        _registerPauser(address(alreadyPaused), pauser);

        vm.expectEmit(true, true, false, true);
        emit CircuitBreaker.PauseTriggered(address(alreadyPaused), pauser, PAUSE_DURATION);

        vm.prank(pauser);
        cb.pause(address(alreadyPaused));

        // Succeeds — CircuitBreaker doesn't check pre-pause state
        assertEq(cb.getPauser(address(alreadyPaused)), address(0));
    }

    function test_SucceedsOnManuallyPrePausedMock() public {
        _registerPauser(address(mockPausable), pauser);

        // Manually set paused before calling pause
        mockPausable.pauseFor(1 days);

        vm.prank(pauser);
        cb.pause(address(mockPausable));

        assertTrue(mockPausable.isPaused());
        assertEq(cb.getPauser(address(mockPausable)), address(0));
    }

    function test_RevertIf_PausableRejectsPauseWhenAlreadyPaused() public {
        MockPausableRevertsIfAlreadyPaused reverting = new MockPausableRevertsIfAlreadyPaused();
        _registerPauser(address(reverting), pauser);

        // Pre-pause so the mock's own guard rejects the next pauseFor
        reverting.pauseFor(1 days);
        assertTrue(reverting.isPaused());

        vm.expectRevert("already paused");
        vm.prank(pauser);
        cb.pause(address(reverting));

        // Pauser still registered after reverted tx
        assertEq(cb.getPauser(address(reverting)), pauser);
        assertEq(cb.getPausableCount(pauser), 1);
    }
}

// =============================================================================
// Transient storage reset
// =============================================================================

contract PauseTransientStorage is TestBase {
    function test_LockResetsBetweenTransactions() public {
        MockPausable mp1 = new MockPausable();
        MockPausable mp2 = new MockPausable();
        _registerPauser(address(mp1), pauser);
        _registerPauser(address(mp2), pauser);

        // First pause in tx 1
        vm.prank(pauser);
        cb.pause(address(mp1));
        assertTrue(mp1.isPaused());

        // Second pause in tx 2 — lock should be reset (transient storage)
        vm.prank(pauser);
        cb.pause(address(mp2));
        assertTrue(mp2.isPaused());
    }
}

// =============================================================================
// Pauser replaced before pause
// =============================================================================

contract PauseAfterReplacement is WithRegisteredPauser {
    function test_RevertIf_PauserReplacedBeforePause() public {
        address pauser2 = makeAddr("pauser2");
        vm.prank(admin);
        cb.registerPauser(address(mockPausable), pauser2);

        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauser);
        cb.pause(address(mockPausable));
    }

    function test_RevertIf_PauserUnregisteredByAdmin() public {
        vm.prank(admin);
        cb.registerPauser(address(mockPausable), address(0));

        vm.expectRevert(CircuitBreaker.SenderNotPauser.selector);
        vm.prank(pauser);
        cb.pause(address(mockPausable));
    }
}

// =============================================================================
// Full lifecycle
// =============================================================================

contract PauseFullLifecycle is TestBase {
    function test_RegisterPauseRearmPause() public {
        _registerPauser(address(mockPausable), pauser);

        vm.prank(pauser);
        cb.pause(address(mockPausable));
        assertTrue(mockPausable.isPaused());
        assertEq(cb.getPauser(address(mockPausable)), address(0));

        // Reset mock and re-register
        mockPausable.unpause();
        _registerPauser(address(mockPausable), pauser);

        vm.prank(pauser);
        cb.pause(address(mockPausable));
        assertTrue(mockPausable.isPaused());
    }

    function test_AdminIsAlsoPauser() public {
        _registerPauser(address(mockPausable), admin);

        // Admin can pause (acting as pauser)
        vm.prank(admin);
        cb.pause(address(mockPausable));
        assertTrue(mockPausable.isPaused());

        // Admin can still configure (acting as admin)
        vm.prank(admin);
        cb.setPauseDuration(MAX_PAUSE_DURATION);
        assertEq(cb.pauseDuration(), MAX_PAUSE_DURATION);
    }

    function test_CrossPausableHeartbeatThenPause() public {
        MockPausable mp2 = new MockPausable();
        _registerPauser(address(mockPausable), pauser);
        _registerPauser(address(mp2), pauser);

        vm.prank(pauser);
        cb.heartbeat();

        vm.warp(block.timestamp + 1 hours);

        vm.prank(pauser);
        cb.pause(address(mp2));

        assertEq(cb.heartbeatExpiry(pauser), block.timestamp + HEARTBEAT_INTERVAL);
        assertTrue(mp2.isPaused());
        assertEq(cb.getPauser(address(mockPausable)), pauser);
    }
}
