// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { RecapitalizationModuleHarness } from "../utils/Harnesses.sol";
import { MockGlobals, MockToken }        from "../utils/Mocks.sol";
import { TestBase }                      from "../utils/TestBase.sol";

contract RecapitalizationModuleTestBase is TestBase {

    address governor;
    address treasury;

    uint32 start;

    uint32[] windowStarts;

    uint208[] issuanceRates;

    MockGlobals globals;
    MockToken   token;

    RecapitalizationModuleHarness module;

    function setUp() public virtual {
        governor = makeAddr("governor");
        treasury = makeAddr("treasury");

        globals = new MockGlobals();
        globals.__setGovernor(governor);
        globals.__setMapleTreasury(treasury);
        globals.__setIsValidScheduledCall(true);
        globals.__setIsInstance(true);

        token = new MockToken();
        token.__setGlobals(address(globals));

        module = new RecapitalizationModuleHarness(address(token));

        start = uint32(block.timestamp);

        vm.startPrank(governor);
    }

    function assertWindow(uint16 windowId, uint16 nextWindowId, uint32 windowStart, uint208 issuanceRate) internal {
        (
            uint16  nextWindowId_,
            uint32  windowStart_,
            uint208 issuanceRate_
        ) = module.windows(windowId);

        assertEq(nextWindowId_, nextWindowId, "nextWindowId");
        assertEq(windowStart_,  windowStart,  "windowStart");
        assertEq(issuanceRate_, issuanceRate, "issuanceRate");
    }

    function expectTreasuryMint(uint256 amount) internal {
        token.__expectCall();
        token.mint(treasury, amount);
    }

    function expectUnscheduleCall() internal {
        globals.__expectCall();
        globals.unscheduleCall(governor, "RM:SCHEDULE", abi.encodeWithSelector(module.schedule.selector, windowStarts, issuanceRates));
    }

}

contract ConstructorTests is RecapitalizationModuleTestBase {

    function test_recapitalizationModule_constructor() external {
        assertEq(module.token(), address(token));

        assertEq(module.lastClaimedTimestamp(),  0);
        assertEq(module.lastClaimedWindowId(),   0);
        assertEq(module.lastScheduledWindowId(), 0);

        assertWindow(0, 0, 0, 0);
    }
}

contract ClaimTests is RecapitalizationModuleTestBase {

    event Claimed(uint256 amountClaimed, uint16 lastClaimedWindowId);

    function setUp() public override {
        super.setUp();

        vm.stopPrank();
    }

    function test_claim_noClaimer() external {
        globals.__setIsInstance(false);

        vm.expectRevert("RM:NOT_CLAIMER");
        module.claim();
    }

    function test_claim_zeroClaim_atomic() external {
        vm.expectRevert("RM:C:ZERO_CLAIM");
        module.claim();
    }

    function test_claim_zeroClaim_afterWarp() external {
        vm.warp(start + 10 days);
        vm.expectRevert("RM:C:ZERO_CLAIM");
        module.claim();
    }

    function test_claim_zeroClaim_emptyWindow() external {
        windowStarts.push(start + 5 days);
        issuanceRates.push(0);

        vm.prank(governor);
        module.schedule(windowStarts, issuanceRates);

        vm.warp(start + 10 days);
        vm.expectRevert("RM:C:ZERO_CLAIM");
        module.claim();
    }

    function test_claim_zeroClaim_beforeWindow() external {
        windowStarts.push(start + 20 days);
        issuanceRates.push(1e18);

        vm.prank(governor);
        module.schedule(windowStarts, issuanceRates);

        vm.warp(start + 10 days);
        vm.expectRevert("RM:C:ZERO_CLAIM");
        module.claim();
    }

    function test_claim_duringWindow() external {
        windowStarts.push(start);
        issuanceRates.push(1e18);

        vm.warp(start);
        vm.prank(governor);
        module.schedule(windowStarts, issuanceRates);

        vm.warp(start + 40 days);

        uint256 expectedClaim = 1e18 * 40 days;

        assertEq(module.claimable(start + 40 days), expectedClaim);

        expectTreasuryMint(expectedClaim);
        uint256 actualClaim = module.claim();

        assertEq(actualClaim, expectedClaim);

        assertEq(module.lastClaimedTimestamp(), start + 40 days);
        assertEq(module.lastClaimedWindowId(),  1);
    }

    function test_claim_afterWindow() external {
        windowStarts.push(start);
        windowStarts.push(start + 50 days);

        issuanceRates.push(1e18);
        issuanceRates.push(0);

        vm.warp(start);
        vm.prank(governor);
        module.schedule(windowStarts, issuanceRates);

        vm.warp(start + 65 days);

        uint256 expectedClaim = 1e18 * 50 days;

        assertEq(module.claimable(start + 65 days), expectedClaim);

        expectTreasuryMint(expectedClaim);
        uint256 actualClaim = module.claim();

        assertEq(actualClaim, expectedClaim);

        assertEq(module.lastClaimedTimestamp(), start + 65 days);
        assertEq(module.lastClaimedWindowId(),  2);
    }

    function test_claim_betweenWindows() external {
        windowStarts.push(start);
        windowStarts.push(start + 50 days);

        issuanceRates.push(1e18);
        issuanceRates.push(0);

        vm.warp(start);
        vm.prank(governor);
        module.schedule(windowStarts, issuanceRates);

        vm.warp(start + 50 days);

        uint256 expectedClaim = 1e18 * 50 days;

        assertEq(module.claimable(start + 50 days), expectedClaim);

        expectTreasuryMint(expectedClaim);
        uint256 actualClaim = module.claim();

        assertEq(actualClaim, expectedClaim);

        assertEq(module.lastClaimedTimestamp(), start + 50 days);
        assertEq(module.lastClaimedWindowId(),  2);
    }

    function test_claim_threeWindows() external {
        windowStarts.push(start);
        windowStarts.push(start + 50 days);
        windowStarts.push(start + 85 days);

        issuanceRates.push(0.95e18);
        issuanceRates.push(0.96e18);
        issuanceRates.push(0.97e18);

        vm.warp(start);
        vm.prank(governor);
        module.schedule(windowStarts, issuanceRates);

        vm.warp(start + 65 days);

        uint256 expectedClaim =  0.95e18 * 50 days + 0.96e18 * 15 days;

        assertEq(module.claimable(start + 65 days), expectedClaim);

        expectTreasuryMint(expectedClaim);
        uint256 actualClaim = module.claim();

        assertEq(actualClaim, expectedClaim);

        assertEq(module.lastClaimedTimestamp(), start + 65 days);
        assertEq(module.lastClaimedWindowId(),  2);
    }

    function test_claim_sevenWindows() external {
        windowStarts.push(start);
        windowStarts.push(start + 50 days);
        windowStarts.push(start + 85 days);
        windowStarts.push(start + 120 days);
        windowStarts.push(start + 150 days);
        windowStarts.push(start + 190 days);
        windowStarts.push(start + 300 days);

        issuanceRates.push(0.95e18);
        issuanceRates.push(0.96e18);
        issuanceRates.push(0.97e18);
        issuanceRates.push(0);
        issuanceRates.push(1e18);
        issuanceRates.push(0);
        issuanceRates.push(0.98e18);

        vm.warp(start);
        vm.prank(governor);
        module.schedule(windowStarts, issuanceRates);

        vm.warp(start + 20 days);
        expectTreasuryMint(0.95e18 * 20 days);
        module.claim();

        assertEq(module.lastClaimedTimestamp(), start + 20 days);
        assertEq(module.lastClaimedWindowId(),  1);

        vm.warp(start + 60 days);
        expectTreasuryMint(0.95e18 * 30 days + 0.96e18 * 10 days);
        module.claim();

        assertEq(module.lastClaimedTimestamp(), start + 60 days);
        assertEq(module.lastClaimedWindowId(),  2);

        vm.warp(start + 100 days);
        expectTreasuryMint(0.96e18 * 25 days + 0.97e18 * 15 days);
        module.claim();

        assertEq(module.lastClaimedTimestamp(), start + 100 days);
        assertEq(module.lastClaimedWindowId(),  3);

        vm.warp(start + 200 days);
        expectTreasuryMint(0.97e18 * 20 days + 1e18 * 40 days);
        module.claim();

        assertEq(module.lastClaimedTimestamp(), start + 200 days);
        assertEq(module.lastClaimedWindowId(),  6);
    }

    function test_claim_afterReschedule() external {
        // TODO
    }

}

contract ClaimableTests is RecapitalizationModuleTestBase {

    uint256 constant MAX_IR      = 1e18;
    uint256 constant MAX_OFFSET  = 365 days;
    uint256 constant MAX_WINDOWS = 10;

    function claimable() internal view returns (uint256 claimableAmount) {
        uint16 windowId;

        while (true) {
            ( uint16 nextWindowId, uint32 windowStart, uint208 issuanceRate ) = module.windows(windowId);

            if (nextWindowId == 0) break;

            windowId = nextWindowId;

            ( , uint32 windowEnd, ) = module.windows(windowId);

            claimableAmount += issuanceRate * (windowEnd - windowStart);
        }
    }

    function schedule(uint16 windowCount, uint32 minWindowStart, uint256 windowSeed) internal returns (uint32 lastWindowStart) {
        uint32[]  memory windowStarts_  = new uint32[](windowCount);
        uint208[] memory issuanceRates_ = new uint208[](windowCount);

        for (uint i; i < windowCount; ++i) {
            uint256 seed = uint256(keccak256(abi.encode(windowSeed, i)));

            windowStarts_[i]  = uint32(bound(seed, minWindowStart, minWindowStart + MAX_OFFSET));
            issuanceRates_[i] = uint208(bound(seed, 0, MAX_IR));

            minWindowStart = windowStarts_[i] + 1 seconds;
        }

        module.schedule(windowStarts_, issuanceRates_);

        lastWindowStart = minWindowStart - 1 seconds;
    }

    function testFuzz_claimable(uint16 windowCount, uint256 windowSeed) external {
        windowCount = uint16(bound(windowCount, 1, MAX_WINDOWS));

        uint32 to = schedule(windowCount, start, windowSeed);

        assertEq(module.claimable(to), claimable());
    }

}

contract FindInsertionPointTests is RecapitalizationModuleTestBase {

    function setUp() public override {
        super.setUp();

        windowStarts.push(start + 50 days);
        windowStarts.push(start + 160 days);
        windowStarts.push(start + 365 days);

        issuanceRates.push(0.94e18);
        issuanceRates.push(0.95e18);
        issuanceRates.push(0.96e18);

        vm.warp(start);
        module.schedule(windowStarts, issuanceRates);
    }

    function test_findInsertionPoint_noClaim() external {
        assertEq(module.lastClaimedWindowId(), 0);

        assertEq(module.findInsertionPoint(start + 365 days - 1 seconds), 2);
        assertEq(module.findInsertionPoint(start + 365 days),             2);
        assertEq(module.findInsertionPoint(start + 365 days + 1 seconds), 3);
    }

    function test_findInsertionPoint_previousToLastWindowClaimed() external {
        vm.warp(start + 160 days);
        module.claim();

        assertEq(module.lastClaimedWindowId(), 2);

        assertEq(module.findInsertionPoint(start + 365 days - 1 seconds), 2);
        assertEq(module.findInsertionPoint(start + 365 days),             2);
        assertEq(module.findInsertionPoint(start + 365 days + 1 seconds), 3);
    }

    function test_findInsertionPoint_lastWindowClaimed() external {
        vm.warp(start + 365 days);
        module.claim();

        assertEq(module.lastClaimedWindowId(), 3);

        assertEq(module.findInsertionPoint(start + 365 days),             3);
        assertEq(module.findInsertionPoint(start + 365 days + 1 seconds), 3);
    }

}

contract ScheduleTests is RecapitalizationModuleTestBase {

    event WindowScheduled(uint16 indexed newWindowId, uint32 indexed windowStart, uint208 issuanceRate, uint16 previousWindowId);

    function test_schedule_notGovernor() external {
        vm.stopPrank();
        vm.expectRevert("RM:NOT_GOVERNOR");
        module.schedule(windowStarts, issuanceRates);
    }

    function test_schedule_notScheduled() external {
        globals.__setIsValidScheduledCall(false);

        vm.expectRevert("RM:NOT_SCHEDULED");
        module.schedule(windowStarts, issuanceRates);
    }

    function test_schedule_lengthMismatch() external {
        windowStarts.push(start);
        windowStarts.push(start + 10 days);

        issuanceRates.push(1e18);

        vm.expectRevert("RM:VW:LENGTH_MISMATCH");
        module.schedule(windowStarts, issuanceRates);
    }

    function test_schedule_noArrays() external {
        vm.expectRevert("RM:VW:EMPTY_ARRAYS");
        module.schedule(windowStarts, issuanceRates);
    }

    function test_schedule_outOfDate() external {
        windowStarts.push(start - 1 seconds);
        issuanceRates.push(1e18);

        vm.expectRevert("RM:VW:OUT_OF_DATE");
        module.schedule(windowStarts, issuanceRates);
    }

    function test_schedule_outOfOrder() external {
        windowStarts.push(start + 100 days);
        windowStarts.push(start + 10 days);

        issuanceRates.push(0.95e18);
        issuanceRates.push(1e18);

        vm.expectRevert("RM:VW:OUT_OF_ORDER");
        module.schedule(windowStarts, issuanceRates);
    }

    function test_schedule_basic() external {
        windowStarts.push(start + 10 days);
        issuanceRates.push(0.9e18);

        expectUnscheduleCall();

        vm.expectEmit();
        emit WindowScheduled(1, start + 10 days, 0.9e18, 0);

        module.schedule(windowStarts, issuanceRates);

        assertEq(module.lastScheduledWindowId(), 1);

        assertWindow(0, 1, 0,               0);
        assertWindow(1, 0, start + 10 days, 0.9e18);
    }

    function test_schedule_simultaneously() external {
        windowStarts.push(start + 10 days);
        windowStarts.push(start + 100 days);

        issuanceRates.push(0.9e18);
        issuanceRates.push(0.95e18);

        expectUnscheduleCall();

        vm.expectEmit();
        emit WindowScheduled(1, start + 10 days,  0.9e18, 0);

        vm.expectEmit();
        emit WindowScheduled(2, start + 100 days, 0.95e18, 1);

        module.schedule(windowStarts, issuanceRates);

        assertEq(module.lastScheduledWindowId(), 2);

        assertWindow(0, 1, 0,                0);
        assertWindow(1, 2, start + 10 days,  0.9e18);
        assertWindow(2, 0, start + 100 days, 0.95e18);
    }

    function test_schedule_sequentially() external {
        windowStarts.push(start + 10 days);
        issuanceRates.push(0.9e18);

        expectUnscheduleCall();

        vm.expectEmit();
        emit WindowScheduled(1, start + 10 days,  0.9e18, 0);

        module.schedule(windowStarts, issuanceRates);

        windowStarts[0] = start + 100 days;
        issuanceRates[0] = 0.95e18;

        expectUnscheduleCall();

        vm.expectEmit();
        emit WindowScheduled(2, start + 100 days, 0.95e18, 1);

        module.schedule(windowStarts, issuanceRates);

        assertEq(module.lastScheduledWindowId(), 2);

        assertWindow(0, 1, 0,                0);
        assertWindow(1, 2, start + 10 days,  0.9e18);
        assertWindow(2, 0, start + 100 days, 0.95e18);
    }

    function test_schedule_sequentiallyWithWarp() external {
        windowStarts.push(start + 10 days);
        issuanceRates.push(0.9e18);

        expectUnscheduleCall();

        vm.expectEmit();
        emit WindowScheduled(1, start + 10 days,  0.9e18, 0);

        vm.warp(start + 5 days);
        module.schedule(windowStarts, issuanceRates);

        windowStarts[0] = start + 100 days;
        issuanceRates[0] = 0.95e18;

        expectUnscheduleCall();
        vm.warp(start + 95 days);

        vm.expectEmit();
        emit WindowScheduled(2, start + 100 days, 0.95e18, 1);

        module.schedule(windowStarts, issuanceRates);

        assertEq(module.lastScheduledWindowId(), 2);

        assertWindow(0, 1, 0,                0);
        assertWindow(1, 2, start + 10 days,  0.9e18);
        assertWindow(2, 0, start + 100 days, 0.95e18);
    }

    function test_schedule_append() external {
        windowStarts.push(start + 10 days);
        windowStarts.push(start + 100 days);

        issuanceRates.push(0.9e18);
        issuanceRates.push(0.95e18);

        expectUnscheduleCall();

        vm.expectEmit();
        emit WindowScheduled(1, start + 10 days,  0.9e18, 0);

        vm.expectEmit();
        emit WindowScheduled(2, start + 100 days, 0.95e18, 1);

        module.schedule(windowStarts, issuanceRates);

        windowStarts[0] = start + 150 days;
        windowStarts[1] = start + 200 days;

        issuanceRates[0] = 0.96e18;
        issuanceRates[1] = 0.99e18;

        expectUnscheduleCall();

        vm.expectEmit();
        emit WindowScheduled(3, start + 150 days, 0.96e18, 2);

        vm.expectEmit();
        emit WindowScheduled(4, start + 200 days, 0.99e18, 3);

        module.schedule(windowStarts, issuanceRates);

        assertEq(module.lastScheduledWindowId(), 4);

        assertWindow(0, 1, 0,                0);
        assertWindow(1, 2, start + 10 days,  0.9e18);
        assertWindow(2, 3, start + 100 days, 0.95e18);
        assertWindow(3, 4, start + 150 days, 0.96e18);
        assertWindow(4, 0, start + 200 days, 0.99e18);
    }

    function test_schedule_insert() external {
        windowStarts.push(start + 10 days);
        windowStarts.push(start + 100 days);

        issuanceRates.push(0.9e18);
        issuanceRates.push(0.95e18);

        expectUnscheduleCall();

        vm.expectEmit();
        emit WindowScheduled(1, start + 10 days,  0.9e18, 0);

        vm.expectEmit();
        emit WindowScheduled(2, start + 100 days, 0.95e18, 1);

        module.schedule(windowStarts, issuanceRates);

        windowStarts[0] = start + 50 days;
        windowStarts[1] = start + 120 days;

        issuanceRates[0] = 0.96e18;
        issuanceRates[1] = 0.99e18;

        expectUnscheduleCall();

        vm.expectEmit();
        emit WindowScheduled(3, start + 50 days,  0.96e18, 1);

        vm.expectEmit();
        emit WindowScheduled(4, start + 120 days, 0.99e18, 3);

        module.schedule(windowStarts, issuanceRates);

        assertEq(module.lastScheduledWindowId(), 4);

        assertWindow(0, 1, 0,                0);
        assertWindow(1, 3, start + 10 days,  0.9e18);
        assertWindow(3, 4, start + 50 days,  0.96e18);
        assertWindow(4, 0, start + 120 days, 0.99e18);
    }

    function test_schedule_duplicate() public {
        windowStarts.push(start);
        windowStarts.push(start + 1 seconds);

        issuanceRates.push(100);
        issuanceRates.push(150);

        // Schedule the initial windows.
        module.schedule(windowStarts, issuanceRates);

        assertEq(module.lastScheduledWindowId(), 2);

        assertWindow(0, 1, 0,                 0);
        assertWindow(1, 2, start,             100);
        assertWindow(2, 0, start + 1 seconds, 150);

        vm.warp(start + 1 seconds);
        module.claim();

        assertEq(module.lastClaimedTimestamp(), start + 1 seconds);
        assertEq(module.lastClaimedWindowId(),  2);

        windowStarts.pop();
        windowStarts.pop();
        windowStarts.push(start + 1 seconds);

        issuanceRates.pop();
        issuanceRates.pop();
        issuanceRates.push(200);

        // Schedule a window with a duplicate starting time.
        vm.expectRevert("RM:S:DUPLICATE_WINDOW");
        module.schedule(windowStarts, issuanceRates);

        windowStarts.pop();
        windowStarts.push(start + 2 seconds);

        // Schedule a window with a valid starting time.
        module.schedule(windowStarts, issuanceRates);

        assertEq(module.lastScheduledWindowId(), 3);

        assertWindow(0, 1, 0,                 0);
        assertWindow(1, 2, start,             100);
        assertWindow(2, 3, start + 1 seconds, 150);
        assertWindow(3, 0, start + 2 seconds, 200);
    }

}

contract ViewFunctionTests is RecapitalizationModuleTestBase {

    function setUp() public override {
        super.setUp();
        vm.stopPrank();

        windowStarts.push(start);
        windowStarts.push(start + 50 days);
        windowStarts.push(start + 85 days);
        windowStarts.push(start + 120 days);
        windowStarts.push(start + 150 days);
        windowStarts.push(start + 190 days);
        windowStarts.push(start + 300 days);

        issuanceRates.push(0.95e18);
        issuanceRates.push(0.96e18);
        issuanceRates.push(0.97e18);
        issuanceRates.push(0);
        issuanceRates.push(1e18);
        issuanceRates.push(0);
        issuanceRates.push(0.98e18);

        vm.warp(start);
        vm.prank(governor);
        module.schedule(windowStarts, issuanceRates);
    }

    function test_viewFunctions() external {
        vm.warp(start - 1 seconds);

        assertEq(module.currentIssuanceRate(), 0);
        assertEq(module.currentWindowId(),     0);
        assertEq(module.currentWindowStart(),  0);

        vm.warp(start);

        assertEq(module.currentIssuanceRate(), 0.95e18);
        assertEq(module.currentWindowId(),     1);
        assertEq(module.currentWindowStart(),  start);

        vm.warp(start + 50 days - 1 seconds);

        assertEq(module.currentIssuanceRate(), 0.95e18);
        assertEq(module.currentWindowId(),     1);
        assertEq(module.currentWindowStart(),  start);

        vm.warp(start + 50 days);

        assertEq(module.currentIssuanceRate(), 0.96e18);
        assertEq(module.currentWindowId(),     2);
        assertEq(module.currentWindowStart(),  start + 50 days);

        vm.warp(start + 85 days - 1 seconds);

        assertEq(module.currentIssuanceRate(), 0.96e18);
        assertEq(module.currentWindowId(),     2);
        assertEq(module.currentWindowStart(),  start + 50 days);

        vm.warp(start + 85 days);

        assertEq(module.currentIssuanceRate(), 0.97e18);
        assertEq(module.currentWindowId(),     3);
        assertEq(module.currentWindowStart(),  start + 85 days);

        vm.warp(start + 120 days - 1 seconds);

        assertEq(module.currentIssuanceRate(), 0.97e18);
        assertEq(module.currentWindowId(),     3);
        assertEq(module.currentWindowStart(),  start + 85 days);

        vm.warp(start + 120 days);

        assertEq(module.currentIssuanceRate(), 0);
        assertEq(module.currentWindowId(),     4);
        assertEq(module.currentWindowStart(),  start + 120 days);

        vm.warp(start + 150 days - 1 seconds);

        assertEq(module.currentIssuanceRate(), 0);
        assertEq(module.currentWindowId(),     4);
        assertEq(module.currentWindowStart(),  start + 120 days);

        vm.warp(start + 150 days);

        assertEq(module.currentIssuanceRate(), 1e18);
        assertEq(module.currentWindowId(),     5);
        assertEq(module.currentWindowStart(),  start + 150 days);

        vm.warp(start + 190 days - 1 seconds);

        assertEq(module.currentIssuanceRate(), 1e18);
        assertEq(module.currentWindowId(),     5);
        assertEq(module.currentWindowStart(),  start + 150 days);

        vm.warp(start + 190 days);

        assertEq(module.currentIssuanceRate(), 0);
        assertEq(module.currentWindowId(),     6);
        assertEq(module.currentWindowStart(),  start + 190 days);

        vm.warp(start + 300 days - 1 seconds);

        assertEq(module.currentIssuanceRate(), 0);
        assertEq(module.currentWindowId(),     6);
        assertEq(module.currentWindowStart(),  start + 190 days);

        vm.warp(start + 300 days);

        assertEq(module.currentIssuanceRate(), 0.98e18);
        assertEq(module.currentWindowId(),     7);
        assertEq(module.currentWindowStart(),  start + 300 days);

        vm.warp(start + 300 days + 1 seconds);

        assertEq(module.currentIssuanceRate(), 0.98e18);
        assertEq(module.currentWindowId(),     7);
        assertEq(module.currentWindowStart(),  start + 300 days);
    }

}
