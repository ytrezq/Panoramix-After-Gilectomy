// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {CircuitBreaker, IPausable} from "../../src/CircuitBreaker.sol";

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

contract MockPausable is IPausable {
    uint256 private _resumeSince;

    function isPaused() external view returns (bool) {
        return block.timestamp < _resumeSince;
    }

    function pauseFor(uint256 duration) external {
        _resumeSince = block.timestamp + duration;
    }

    function getResumeSinceTimestamp() external view returns (uint256) {
        return _resumeSince;
    }

    function unpause() external {
        _resumeSince = 0;
    }
}

// ---------------------------------------------------------------------------
// Base
// ---------------------------------------------------------------------------

abstract contract TestBase is Test {
    CircuitBreaker internal cb;
    MockPausable internal mockPausable;

    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant MIN_PAUSE_DURATION = 3 days;
    uint256 internal constant MAX_PAUSE_DURATION = 30 days;
    uint256 internal constant PAUSE_DURATION = 14 days;

    uint256 internal constant MIN_HEARTBEAT_INTERVAL = 30 days;
    uint256 internal constant MAX_HEARTBEAT_INTERVAL = 1095 days;
    uint256 internal constant HEARTBEAT_INTERVAL = 365 days;

    function setUp() public virtual {
        cb = new CircuitBreaker(
            admin,
            MIN_PAUSE_DURATION,
            MAX_PAUSE_DURATION,
            MIN_HEARTBEAT_INTERVAL,
            MAX_HEARTBEAT_INTERVAL,
            PAUSE_DURATION,
            HEARTBEAT_INTERVAL
        );
        mockPausable = new MockPausable();
    }

    function _registerPauser(address _pausable, address _pauser) internal {
        vm.prank(admin);
        cb.registerPauser(_pausable, _pauser);
    }

    function _advanceToHeartbeatEdge(address _pauser) internal {
        vm.warp(cb.heartbeatExpiry(_pauser) - 1);
    }

    function _advanceToHeartbeatExpiry(address _pauser) internal {
        vm.warp(cb.heartbeatExpiry(_pauser));
    }

    function _advancePastHeartbeat(address _pauser) internal {
        vm.warp(cb.heartbeatExpiry(_pauser) + 1);
    }

    function _assertPausablesLength(uint256 expectedLength) internal view {
        assertEq(cb.getPausables().length, expectedLength);
    }

    function _assertPausablesContain(address _pausable) internal view {
        address[] memory pausables = cb.getPausables();
        bool found = false;
        for (uint256 i = 0; i < pausables.length; i++) {
            if (pausables[i] == _pausable) {
                found = true;
                break;
            }
        }
        assertTrue(found, "pausable not found in getPausables()");
    }

    function _assertPausablesExclude(address _pausable) internal view {
        address[] memory pausables = cb.getPausables();
        for (uint256 i = 0; i < pausables.length; i++) {
            assertTrue(pausables[i] != _pausable, "pausable unexpectedly found in getPausables()");
        }
    }

    function _assertNoDuplicatesInPausables() internal view {
        address[] memory pausables = cb.getPausables();
        for (uint256 i = 0; i < pausables.length; i++) {
            for (uint256 j = i + 1; j < pausables.length; j++) {
                assertTrue(pausables[i] != pausables[j], "duplicate in getPausables()");
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

abstract contract WithRegisteredPauser is TestBase {
    function setUp() public virtual override {
        super.setUp();
        _registerPauser(address(mockPausable), pauser);
    }
}

abstract contract WithThreePausables is TestBase {
    MockPausable internal pausable1;
    MockPausable internal pausable2;
    MockPausable internal pausable3;

    function setUp() public virtual override {
        super.setUp();
        pausable1 = new MockPausable();
        pausable2 = new MockPausable();
        pausable3 = new MockPausable();
        _registerPauser(address(pausable1), pauser);
        _registerPauser(address(pausable2), pauser);
        _registerPauser(address(pausable3), pauser);
    }
}
